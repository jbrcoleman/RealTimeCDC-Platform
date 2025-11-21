"""
Flink Job: Real-Time Customer Segmentation (RFM Analysis)

RFM = Recency, Frequency, Monetary
Tracks customer behavior and segments them in real-time:
- Recency: Days since last order
- Frequency: Total number of orders
- Monetary: Total amount spent

Segments:
- VIP: High frequency + high monetary
- Regular: Medium frequency + medium monetary
- At-Risk: High recency (haven't ordered recently)
- New: Low frequency (1-2 orders)
- Churned: Very high recency (no orders in 90+ days)

Input Topics:
  - dbserver1.public.orders

Output:
  - DynamoDB table: cdc-platform-customer-segments
"""

import json
import sys
import os
from datetime import datetime, timedelta
from decimal import Decimal

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from pyflink.datastream import StreamExecutionEnvironment
from pyflink.common.serialization import SimpleStringSchema
from pyflink.datastream.connectors.kafka import KafkaSource, KafkaOffsetsInitializer
from pyflink.common.watermark_strategy import WatermarkStrategy
from pyflink.datastream.functions import RuntimeContext, KeyedProcessFunction
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


class CustomerState:
    """State object for customer metrics"""

    def __init__(self):
        self.customer_id = None
        self.first_order_date = None
        self.last_order_date = None
        self.total_orders = 0
        self.total_spent = Decimal('0')

    def to_dict(self):
        return {
            'customer_id': self.customer_id,
            'first_order_date': self.first_order_date,
            'last_order_date': self.last_order_date,
            'total_orders': self.total_orders,
            'total_spent': str(self.total_spent),
        }

    @staticmethod
    def from_dict(data):
        state = CustomerState()
        state.customer_id = data.get('customer_id')
        state.first_order_date = data.get('first_order_date')
        state.last_order_date = data.get('last_order_date')
        state.total_orders = data.get('total_orders', 0)
        state.total_spent = Decimal(data.get('total_spent', '0'))
        return state


class RFMSegmentationFunction(KeyedProcessFunction):
    """
    Stateful function to track customer metrics and assign segments.

    Maintains per-customer state and updates on each order event.
    """

    def __init__(self):
        self.customer_state = None
        self.dynamodb_sink = None

    def open(self, runtime_context: RuntimeContext):
        """Initialize state and DynamoDB connection"""
        # Define state descriptor
        state_descriptor = ValueStateDescriptor(
            'customer_state',
            Types.STRING()  # Store as JSON string
        )
        self.customer_state: ValueState = runtime_context.get_state(state_descriptor)

        # Initialize DynamoDB sink
        table_name = get_table_name('customer-segments')
        self.dynamodb_sink = TimestampedDynamoDBSink(table_name, batch_size=25)

    def process_element(self, value, ctx: KeyedProcessFunction.Context):
        """
        Process each order event and update customer state.

        Args:
            value: JSON string of order event
            ctx: Processing context
        """
        event = json.loads(value)
        op_type = extract_operation_type(event)

        # Only process creates and updates
        if op_type not in ('c', 'u', 'r'):
            return

        customer_id = event.get('customer_id')
        if not customer_id:
            return

        # Get existing state or create new
        state_json = self.customer_state.value()
        if state_json:
            state = CustomerState.from_dict(json.loads(state_json))
        else:
            state = CustomerState()
            state.customer_id = customer_id

        # Extract order data
        total_amount = parse_debezium_decimal(event.get('total_amount', 0), scale=2)
        order_created_at = event.get('created_at')

        if not order_created_at:
            # Fallback to current time
            order_created_at = datetime.utcnow().isoformat()

        # Update state
        state.total_orders += 1
        state.total_spent += total_amount
        state.last_order_date = order_created_at

        if not state.first_order_date:
            state.first_order_date = order_created_at

        # Calculate RFM metrics
        rfm_metrics = self._calculate_rfm(state)

        # Determine segment
        segment = self._assign_segment(rfm_metrics)

        # Prepare output
        result = {
            'customer_id': customer_id,
            'segment': segment,
            'recency_days': rfm_metrics['recency_days'],
            'frequency': rfm_metrics['frequency'],
            'monetary_value': rfm_metrics['monetary_value'],
            'total_orders': state.total_orders,
            'total_spent': float(state.total_spent),
            'first_order_date': state.first_order_date,
            'last_order_date': state.last_order_date,
            'avg_order_value': float(state.total_spent / state.total_orders) if state.total_orders > 0 else 0,
        }

        # Write to DynamoDB
        self.dynamodb_sink.write(result)

        # Save updated state
        self.customer_state.update(json.dumps(state.to_dict()))

        # Emit result
        yield json.dumps(result)

    def _calculate_rfm(self, state: CustomerState):
        """
        Calculate RFM scores.

        Returns:
            dict: RFM metrics
        """
        now = datetime.utcnow()

        # Recency: Days since last order
        if state.last_order_date:
            try:
                last_order = datetime.fromisoformat(state.last_order_date.replace('Z', '+00:00'))
                recency_days = (now - last_order).days
            except Exception:
                recency_days = 0
        else:
            recency_days = 999

        # Frequency: Total orders
        frequency = state.total_orders

        # Monetary: Total spent
        monetary_value = float(state.total_spent)

        return {
            'recency_days': recency_days,
            'frequency': frequency,
            'monetary_value': monetary_value,
        }

    def _assign_segment(self, rfm):
        """
        Assign customer segment based on RFM scores.

        Business rules:
        - VIP: Frequent buyers (5+ orders) with high spend ($500+)
        - Regular: 3-4 orders, moderate spend
        - New: 1-2 orders
        - At-Risk: Haven't ordered in 30+ days, but had 3+ orders
        - Churned: No order in 90+ days

        Args:
            rfm: RFM metrics dict

        Returns:
            str: Segment name
        """
        recency = rfm['recency_days']
        frequency = rfm['frequency']
        monetary = rfm['monetary_value']

        # Churned: No order in 90+ days
        if recency > 90:
            return 'Churned'

        # VIP: High frequency + high monetary
        if frequency >= 5 and monetary >= 500:
            return 'VIP'

        # At-Risk: Haven't ordered recently but were active
        if recency > 30 and frequency >= 3:
            return 'At-Risk'

        # New: Only 1-2 orders
        if frequency <= 2:
            return 'New'

        # Regular: Everyone else
        return 'Regular'

    def close(self):
        """Cleanup resources"""
        if self.dynamodb_sink:
            self.dynamodb_sink.close()


def main():
    """Main Flink job entry point"""

    # Create execution environment
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(2)
    env.enable_checkpointing(60000)

    # Configure Kafka source
    kafka_props = get_kafka_properties()
    kafka_bootstrap = kafka_props['bootstrap.servers']

    kafka_source = KafkaSource.builder() \
        .set_bootstrap_servers(kafka_bootstrap) \
        .set_topics('dbserver1.public.orders') \
        .set_group_id('flink-customer-segmentation') \
        .set_starting_offsets(KafkaOffsetsInitializer.earliest()) \
        .set_value_only_deserializer(SimpleStringSchema()) \
        .build()

    # Use no watermarks for now to get job running
    watermark_strategy = WatermarkStrategy.no_watermarks()

    # Create data stream
    orders_stream = env.from_source(
        kafka_source,
        watermark_strategy,
        'Orders Source'
    )

    # Apply customer segmentation (keyed by customer_id)
    segmented_stream = orders_stream \
        .map(lambda x: (json.loads(x).get('customer_id'), x)) \
        .key_by(lambda x: x[0]) \
        .process(RFMSegmentationFunction()) \
        .map(lambda x: x[1])

    # Print results
    segmented_stream.print()

    # Execute job
    env.execute('Real-Time Customer Segmentation (RFM)')


if __name__ == '__main__':
    main()
