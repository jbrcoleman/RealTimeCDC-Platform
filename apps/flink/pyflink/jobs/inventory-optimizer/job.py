"""
Flink Job: Inventory Optimization Engine

Provides predictive inventory insights:
- Stock velocity tracking (sales rate over time)
- Stockout predictions (days until out of stock)
- Restock recommendations with quantities
- Dead stock identification (no sales in N days)
- Trending product detection (velocity changes)

Input Topics:
  - dbserver1.public.products (for current stock levels)
  - dbserver1.public.order_items (for sales tracking)

Output:
  - DynamoDB table: cdc-platform-inventory-insights
"""

import json
import sys
import os
from datetime import datetime, timedelta
from decimal import Decimal
from collections import deque

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from pyflink.datastream import StreamExecutionEnvironment
from pyflink.common.serialization import SimpleStringSchema
from pyflink.datastream.connectors.kafka import KafkaSource, KafkaOffsetsInitializer
from pyflink.common.watermark_strategy import WatermarkStrategy
from pyflink.datastream.functions import RuntimeContext, KeyedProcessFunction, CoProcessFunction
from pyflink.common.time import Time
from pyflink.datastream.state import ValueStateDescriptor, ValueState
from pyflink.common.typeinfo import Types

from shared import (
    get_kafka_properties,
    parse_debezium_decimal,
    extract_operation_type,
    get_table_name
)
from shared.dynamodb_sink import TimestampedDynamoDBSink


class InventoryState:
    """State for tracking product inventory metrics"""

    def __init__(self):
        self.product_id = None
        self.product_name = None
        self.current_stock = 0
        self.price = Decimal('0')
        self.sales_history = []  # List of (timestamp, quantity) tuples
        self.last_restock_date = None
        self.last_sale_date = None

    def to_dict(self):
        return {
            'product_id': self.product_id,
            'product_name': self.product_name,
            'current_stock': self.current_stock,
            'price': str(self.price),
            'sales_history': [(ts, qty) for ts, qty in self.sales_history],
            'last_restock_date': self.last_restock_date,
            'last_sale_date': self.last_sale_date,
        }

    @staticmethod
    def from_dict(data):
        state = InventoryState()
        state.product_id = data.get('product_id')
        state.product_name = data.get('product_name')
        state.current_stock = data.get('current_stock', 0)
        state.price = Decimal(data.get('price', '0'))
        state.sales_history = [(ts, qty) for ts, qty in data.get('sales_history', [])]
        state.last_restock_date = data.get('last_restock_date')
        state.last_sale_date = data.get('last_sale_date')
        return state


class InventoryOptimizationFunction(CoProcessFunction):
    """
    Co-process products and order_items streams to track inventory.

    Stream 1: Products (stock updates)
    Stream 2: Order Items (sales events)
    """

    # Configuration
    VELOCITY_WINDOW_DAYS = 7  # Calculate velocity over 7 days
    LOW_STOCK_THRESHOLD = 10  # Alert when stock < 10
    DEAD_STOCK_DAYS = 30  # No sales in 30 days = dead stock
    LEAD_TIME_DAYS = 7  # Assume 7 days to restock

    def __init__(self):
        self.inventory_state = None
        self.dynamodb_sink = None

    def open(self, runtime_context: RuntimeContext):
        """Initialize state and connections"""
        state_descriptor = ValueStateDescriptor(
            'inventory_state',
            Types.STRING()
        )
        self.inventory_state: ValueState = runtime_context.get_state(state_descriptor)

        table_name = get_table_name('inventory-insights')
        self.dynamodb_sink = TimestampedDynamoDBSink(table_name, batch_size=25)

    def process_element1(self, value, ctx: CoProcessFunction.Context):
        """
        Process product updates (stock changes, new products).

        Args:
            value: JSON string of product event
        """
        event = json.loads(value)
        op_type = extract_operation_type(event)

        if op_type == 'd':  # Skip deletes
            return

        product_id = event.get('id')
        if not product_id:
            return

        # Get or create state
        state = self._get_or_create_state(product_id)

        # Update product info
        old_stock = state.current_stock
        state.product_id = product_id
        state.product_name = event.get('name', 'Unknown')
        state.current_stock = event.get('stock_quantity', 0)
        state.price = parse_debezium_decimal(event.get('price', 0), scale=2)

        # Detect restock event (stock increased)
        if state.current_stock > old_stock:
            state.last_restock_date = datetime.utcnow().isoformat()

        # Calculate insights and emit
        yield from self._calculate_insights(state)

        # Save state
        self._save_state(state)

    def process_element2(self, value, ctx: CoProcessFunction.Context):
        """
        Process order item events (sales).

        Args:
            value: JSON string of order_item event
        """
        event = json.loads(value)
        op_type = extract_operation_type(event)

        if op_type not in ('c', 'r'):  # Only process creates and reads
            return

        product_id = event.get('product_id')
        if not product_id:
            return

        # Get or create state
        state = self._get_or_create_state(product_id)

        # Record sale
        quantity = event.get('quantity', 0)
        timestamp = int(datetime.utcnow().timestamp() * 1000)
        state.sales_history.append((timestamp, quantity))
        state.last_sale_date = datetime.fromtimestamp(timestamp / 1000).isoformat()

        # Trim old sales (keep only VELOCITY_WINDOW_DAYS)
        cutoff_time = timestamp - (self.VELOCITY_WINDOW_DAYS * 24 * 3600000)
        state.sales_history = [(ts, qty) for ts, qty in state.sales_history if ts > cutoff_time]

        # Update stock (decrement)
        state.current_stock = max(0, state.current_stock - quantity)

        # Calculate insights and emit
        yield from self._calculate_insights(state)

        # Save state
        self._save_state(state)

    def _get_or_create_state(self, product_id):
        """Get existing state or create new"""
        state_json = self.inventory_state.value()
        if state_json:
            return InventoryState.from_dict(json.loads(state_json))
        else:
            state = InventoryState()
            state.product_id = product_id
            return state

    def _save_state(self, state: InventoryState):
        """Save state"""
        self.inventory_state.update(json.dumps(state.to_dict()))

    def _calculate_insights(self, state: InventoryState):
        """
        Calculate inventory insights.

        Returns:
            Generator of insight dicts
        """
        now = datetime.utcnow()

        # Calculate velocity (units per day)
        velocity = self._calculate_velocity(state)

        # Calculate days until stockout
        days_until_stockout = None
        if velocity > 0:
            days_until_stockout = state.current_stock / velocity
        else:
            days_until_stockout = 999  # No recent sales

        # Determine stock status
        stock_status = self._get_stock_status(state, days_until_stockout)

        # Check for dead stock
        is_dead_stock = self._is_dead_stock(state)

        # Calculate restock recommendation
        restock_recommendation = self._get_restock_recommendation(
            state, velocity, days_until_stockout
        )

        # Prepare output
        insight = {
            'product_id': state.product_id,
            'product_name': state.product_name,
            'current_stock': state.current_stock,
            'price': float(state.price),
            'stock_status': stock_status,
            'velocity_units_per_day': round(velocity, 2),
            'days_until_stockout': round(days_until_stockout, 1) if days_until_stockout < 999 else None,
            'is_dead_stock': is_dead_stock,
            'restock_recommendation': restock_recommendation,
            'last_sale_date': state.last_sale_date,
            'last_restock_date': state.last_restock_date,
            'total_sales_7d': sum(qty for _, qty in state.sales_history),
        }

        # Write to DynamoDB
        self.dynamodb_sink.write(insight)

        yield json.dumps(insight)

    def _calculate_velocity(self, state: InventoryState):
        """
        Calculate sales velocity (units per day).

        Args:
            state: InventoryState

        Returns:
            float: Units sold per day
        """
        if not state.sales_history:
            return 0.0

        total_quantity = sum(qty for _, qty in state.sales_history)
        days = self.VELOCITY_WINDOW_DAYS

        return total_quantity / days

    def _get_stock_status(self, state: InventoryState, days_until_stockout):
        """
        Determine stock status.

        Returns:
            str: 'critical', 'low', 'healthy', or 'overstocked'
        """
        if state.current_stock == 0:
            return 'out_of_stock'

        if days_until_stockout is None or days_until_stockout > 60:
            return 'healthy'

        if days_until_stockout <= self.LEAD_TIME_DAYS:
            return 'critical'  # Will run out before restock arrives

        if state.current_stock < self.LOW_STOCK_THRESHOLD:
            return 'low'

        if days_until_stockout < 30:
            return 'low'

        return 'healthy'

    def _is_dead_stock(self, state: InventoryState):
        """Check if product is dead stock (no sales in DEAD_STOCK_DAYS)"""
        if not state.last_sale_date:
            return True  # Never sold

        try:
            last_sale = datetime.fromisoformat(state.last_sale_date)
            days_since_sale = (datetime.utcnow() - last_sale).days
            return days_since_sale > self.DEAD_STOCK_DAYS
        except Exception:
            return False

    def _get_restock_recommendation(self, state: InventoryState, velocity, days_until_stockout):
        """
        Generate restock recommendation.

        Logic:
        - If critical or low, recommend restocking
        - Restock quantity = (velocity * 30 days) - current_stock
        - Ensures 30-day supply

        Returns:
            dict or None
        """
        if days_until_stockout is None or days_until_stockout > 30:
            return None

        if velocity == 0:
            return None

        # Target: 30 days of supply
        target_stock = velocity * 30
        restock_quantity = max(0, target_stock - state.current_stock)

        if restock_quantity < 5:
            return None  # Not worth restocking yet

        return {
            'action': 'restock',
            'recommended_quantity': int(restock_quantity),
            'urgency': 'high' if days_until_stockout <= self.LEAD_TIME_DAYS else 'medium',
            'reason': f'Current stock will last {days_until_stockout:.1f} days at current velocity',
        }

    def close(self):
        """Cleanup"""
        if self.dynamodb_sink:
            self.dynamodb_sink.close()


def main():
    """Main Flink job entry point"""

    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(2)
    env.enable_checkpointing(60000)

    kafka_props = get_kafka_properties()
    kafka_bootstrap = kafka_props['bootstrap.servers']

    # Products stream
    products_source = KafkaSource.builder() \
        .set_bootstrap_servers(kafka_bootstrap) \
        .set_topics('dbserver1.public.products') \
        .set_group_id('flink-inventory-optimizer-products') \
        .set_starting_offsets(KafkaOffsetsInitializer.earliest()) \
        .set_value_only_deserializer(SimpleStringSchema()) \
        .build()

    # Order items stream
    order_items_source = KafkaSource.builder() \
        .set_bootstrap_servers(kafka_bootstrap) \
        .set_topics('dbserver1.public.order_items') \
        .set_group_id('flink-inventory-optimizer-items') \
        .set_starting_offsets(KafkaOffsetsInitializer.earliest()) \
        .set_value_only_deserializer(SimpleStringSchema()) \
        .build()

    # Use no watermarks for now to get job running
    watermark_strategy = WatermarkStrategy.no_watermarks()

    # Create streams
    products_stream = env.from_source(products_source, watermark_strategy, 'Products Source')
    order_items_stream = env.from_source(order_items_source, watermark_strategy, 'Order Items Source')

    # Key both streams by product_id
    keyed_products = products_stream.map(lambda x: (json.loads(x).get('id'), x)).key_by(lambda x: x[0])
    keyed_order_items = order_items_stream.map(lambda x: (json.loads(x).get('product_id'), x)).key_by(lambda x: x[0])

    # Connect streams and apply co-process function
    insights_stream = keyed_products.connect(keyed_order_items).process(InventoryOptimizationFunction()).map(lambda x: x[1])

    # Print insights
    insights_stream.print()

    env.execute('Inventory Optimization Engine')


if __name__ == '__main__':
    main()
