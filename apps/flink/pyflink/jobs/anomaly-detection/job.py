"""
Flink Job: Real-Time Anomaly Detection

Detects suspicious patterns in order data:
- Spike Detection: Customer placing many orders in short time
- Large Order Detection: Orders with unusually high amounts
- Rapid Sequential Orders: Multiple orders within minutes
- Statistical Anomalies: Orders outside normal distribution (z-score)

Input Topics:
  - dbserver1.public.orders
  - dbserver1.public.order_items

Output:
  - DynamoDB table: cdc-platform-anomaly-alerts
  - Optional: SNS notifications for critical anomalies
"""

import json
import sys
import os
from datetime import datetime, timedelta
from decimal import Decimal
import statistics

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from pyflink.datastream import StreamExecutionEnvironment
from pyflink.common.serialization import SimpleStringSchema
from pyflink.datastream.connectors.kafka import KafkaSource, KafkaOffsetsInitializer
from pyflink.common.watermark_strategy import WatermarkStrategy
from pyflink.datastream.functions import RuntimeContext, KeyedProcessFunction
from pyflink.datastream.window import TumblingEventTimeWindows
from pyflink.common.time import Time
from pyflink.datastream.state import ValueStateDescriptor, ListStateDescriptor, ValueState, ListState
from pyflink.common.typeinfo import Types

from shared import (
    get_kafka_properties,
    parse_debezium_decimal,
    extract_operation_type,
    get_table_name
)
from shared.dynamodb_sink import TimestampedDynamoDBSink


class AnomalyState:
    """State tracking for anomaly detection"""

    def __init__(self):
        self.recent_orders = []  # List of (timestamp, amount) tuples
        self.total_orders = 0
        self.total_amount = Decimal('0')
        self.order_amounts = []  # For statistical analysis

    def to_dict(self):
        return {
            'recent_orders': [(ts, str(amt)) for ts, amt in self.recent_orders],
            'total_orders': self.total_orders,
            'total_amount': str(self.total_amount),
            'order_amounts': [str(amt) for amt in self.order_amounts],
        }

    @staticmethod
    def from_dict(data):
        state = AnomalyState()
        state.recent_orders = [(ts, Decimal(amt)) for ts, amt in data.get('recent_orders', [])]
        state.total_orders = data.get('total_orders', 0)
        state.total_amount = Decimal(data.get('total_amount', '0'))
        state.order_amounts = [Decimal(amt) for amt in data.get('order_amounts', [])]
        return state


class AnomalyDetectionFunction(KeyedProcessFunction):
    """
    Stateful anomaly detection per customer.

    Detects:
    1. Order spike: > 5 orders in 1 hour
    2. Large order: > 3 standard deviations from mean
    3. Rapid orders: 2+ orders within 5 minutes
    """

    # Anomaly thresholds
    ORDER_SPIKE_THRESHOLD = 5  # orders per hour
    ORDER_SPIKE_WINDOW_MS = 3600000  # 1 hour in milliseconds
    RAPID_ORDER_WINDOW_MS = 300000  # 5 minutes
    LARGE_ORDER_ZSCORE = 3.0  # 3 standard deviations
    LARGE_ORDER_MIN_AMOUNT = 1000.0  # Absolute minimum for large order

    def __init__(self):
        self.customer_state = None
        self.dynamodb_sink = None

    def open(self, runtime_context: RuntimeContext):
        """Initialize state and connections"""
        state_descriptor = ValueStateDescriptor(
            'anomaly_state',
            Types.STRING()
        )
        self.customer_state: ValueState = runtime_context.get_state(state_descriptor)

        table_name = get_table_name('anomaly-alerts')
        self.dynamodb_sink = TimestampedDynamoDBSink(table_name, batch_size=10)

    def process_element(self, value, ctx: KeyedProcessFunction.Context):
        """Process each order and check for anomalies"""
        event = json.loads(value)
        op_type = extract_operation_type(event)

        if op_type not in ('c', 'u', 'r'):
            return

        customer_id = event.get('customer_id')
        if not customer_id:
            return

        # Get state
        state_json = self.customer_state.value()
        if state_json:
            state = AnomalyState.from_dict(json.loads(state_json))
        else:
            state = AnomalyState()

        # Extract order data
        order_amount = parse_debezium_decimal(event.get('total_amount', 0), scale=2)
        order_timestamp = ctx.timestamp() if ctx.timestamp() else int(datetime.utcnow().timestamp() * 1000)
        order_id = event.get('id')

        # Update state
        state.recent_orders.append((order_timestamp, order_amount))
        state.total_orders += 1
        state.total_amount += order_amount
        state.order_amounts.append(float(order_amount))

        # Trim old orders (keep only last 24 hours for stats)
        cutoff_time = order_timestamp - (24 * 3600000)  # 24 hours ago
        state.recent_orders = [(ts, amt) for ts, amt in state.recent_orders if ts > cutoff_time]
        if len(state.order_amounts) > 100:
            state.order_amounts = state.order_amounts[-100:]  # Keep last 100 for stats

        # Detect anomalies
        anomalies = []

        # 1. Order Spike Detection
        spike_cutoff = order_timestamp - self.ORDER_SPIKE_WINDOW_MS
        recent_count = sum(1 for ts, _ in state.recent_orders if ts > spike_cutoff)
        if recent_count > self.ORDER_SPIKE_THRESHOLD:
            anomalies.append({
                'type': 'order_spike',
                'severity': 'high',
                'description': f'Customer placed {recent_count} orders in the last hour',
                'details': {
                    'order_count': recent_count,
                    'threshold': self.ORDER_SPIKE_THRESHOLD,
                }
            })

        # 2. Rapid Sequential Orders
        rapid_cutoff = order_timestamp - self.RAPID_ORDER_WINDOW_MS
        rapid_count = sum(1 for ts, _ in state.recent_orders if ts > rapid_cutoff)
        if rapid_count >= 2:
            anomalies.append({
                'type': 'rapid_orders',
                'severity': 'medium',
                'description': f'Customer placed {rapid_count} orders within 5 minutes',
                'details': {
                    'order_count': rapid_count,
                    'window_minutes': 5,
                }
            })

        # 3. Large Order Detection (Statistical)
        if len(state.order_amounts) >= 3:  # Need at least 3 orders for stats
            mean = statistics.mean(state.order_amounts)
            stdev = statistics.stdev(state.order_amounts) if len(state.order_amounts) > 1 else 0

            if stdev > 0:
                z_score = (float(order_amount) - mean) / stdev
                if z_score > self.LARGE_ORDER_ZSCORE:
                    anomalies.append({
                        'type': 'statistical_outlier',
                        'severity': 'medium',
                        'description': f'Order amount ${float(order_amount):.2f} is {z_score:.2f} std devs above mean',
                        'details': {
                            'order_amount': float(order_amount),
                            'mean_amount': mean,
                            'z_score': z_score,
                        }
                    })

        # 4. Absolute Large Order
        if float(order_amount) > self.LARGE_ORDER_MIN_AMOUNT:
            anomalies.append({
                'type': 'large_order',
                'severity': 'low',
                'description': f'Large order amount: ${float(order_amount):.2f}',
                'details': {
                    'order_amount': float(order_amount),
                    'threshold': self.LARGE_ORDER_MIN_AMOUNT,
                }
            })

        # Write anomalies to DynamoDB
        for anomaly in anomalies:
            alert = {
                'alert_id': f'{customer_id}_{order_id}_{anomaly["type"]}',
                'customer_id': customer_id,
                'order_id': order_id,
                'anomaly_type': anomaly['type'],
                'severity': anomaly['severity'],
                'description': anomaly['description'],
                'details': anomaly['details'],
                'order_amount': float(order_amount),
                'timestamp': datetime.fromtimestamp(order_timestamp / 1000).isoformat(),
                'total_customer_orders': state.total_orders,
            }

            self.dynamodb_sink.write(alert)
            yield json.dumps(alert)

        # Save updated state
        self.customer_state.update(json.dumps(state.to_dict()))

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

    kafka_source = KafkaSource.builder() \
        .set_bootstrap_servers(kafka_bootstrap) \
        .set_topics('dbserver1.public.orders') \
        .set_group_id('flink-anomaly-detection') \
        .set_starting_offsets(KafkaOffsetsInitializer.earliest()) \
        .set_value_only_deserializer(SimpleStringSchema()) \
        .build()

    # Use no watermarks for now to get job running
    watermark_strategy = WatermarkStrategy.no_watermarks()

    orders_stream = env.from_source(
        kafka_source,
        watermark_strategy,
        'Orders Source'
    )

    # Apply anomaly detection (keyed by customer_id)
    anomaly_stream = orders_stream \
        .map(lambda x: (json.loads(x).get('customer_id'), x)) \
        .key_by(lambda x: x[0]) \
        .process(AnomalyDetectionFunction()) \
        .map(lambda x: x[1])

    # Print anomalies
    anomaly_stream.print()

    env.execute('Real-Time Anomaly Detection')


if __name__ == '__main__':
    main()
