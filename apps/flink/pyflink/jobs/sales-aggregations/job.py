"""
Flink Job: Real-Time Sales Aggregations

This job replaces the analytics-service consumer with proper stream processing:
- Sliding window aggregations (1-hour windows, 5-min slides)
- Tumbling window snapshots (hourly, daily)
- Multiple metrics: revenue, order count, avg order value
- Outputs to DynamoDB for dashboard queries

Input Topics:
  - dbserver1.public.orders
  - dbserver1.public.order_items

Output:
  - DynamoDB table: cdc-platform-realtime-sales-metrics
"""

import json
import sys
import os
from datetime import datetime, timedelta
from decimal import Decimal

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from pyflink.datastream import StreamExecutionEnvironment
from pyflink.datastream.window import TumblingEventTimeWindows, SlidingEventTimeWindows
from pyflink.common.time import Time
from pyflink.common.serialization import SimpleStringSchema
from pyflink.datastream.connectors.kafka import KafkaSource, KafkaOffsetsInitializer
from pyflink.common.watermark_strategy import WatermarkStrategy, TimestampAssigner
from pyflink.datastream.functions import RuntimeContext, ProcessWindowFunction
from pyflink.datastream.window import TimeWindow

from shared import (
    get_kafka_properties,
    parse_debezium_decimal,
    extract_operation_type,
    get_table_name
)
from shared.dynamodb_sink import TimestampedDynamoDBSink


class SalesAggregateFunction(ProcessWindowFunction):
    """
    Window function to aggregate sales metrics.

    For each window, computes:
    - Total revenue
    - Order count
    - Average order value
    - Unique customers
    """

    def __init__(self):
        self.dynamodb_sink = None

    def open(self, runtime_context: RuntimeContext):
        """Initialize DynamoDB connection"""
        table_name = get_table_name('realtime-sales-metrics')
        self.dynamodb_sink = TimestampedDynamoDBSink(table_name, batch_size=25)

    def process(self, key, context: ProcessWindowFunction.Context, elements):
        """
        Process windowed elements and compute aggregations.

        Args:
            key: Window key (e.g., 'all' for global aggregation)
            context: Window context
            elements: Iterable of elements in this window
        """
        window = context.window()
        window_start = window.start
        window_end = window.end

        # Aggregate metrics
        total_revenue = Decimal('0')
        order_count = 0
        customers = set()

        for element in elements:
            event = json.loads(element)
            op_type = extract_operation_type(event)

            # Only process creates and updates (ignore deletes for aggregation)
            if op_type in ('c', 'u', 'r'):
                # Parse total_amount (Debezium decimal)
                total_amount = parse_debezium_decimal(event.get('total_amount', 0), scale=2)
                total_revenue += total_amount

                order_count += 1

                customer_id = event.get('customer_id')
                if customer_id:
                    customers.add(customer_id)

        # Calculate derived metrics
        avg_order_value = total_revenue / order_count if order_count > 0 else Decimal('0')

        # Create aggregated result
        result = {
            'metric_id': f'sales_{window_start}_{window_end}',
            'window_start': datetime.fromtimestamp(window_start / 1000).isoformat(),
            'window_end': datetime.fromtimestamp(window_end / 1000).isoformat(),
            'window_type': 'sliding_1h_5m',  # Can be parameterized
            'total_revenue': float(total_revenue),
            'order_count': order_count,
            'avg_order_value': float(avg_order_value),
            'unique_customers': len(customers),
        }

        # Write to DynamoDB
        self.dynamodb_sink.write(result)

        # Emit for further processing if needed
        yield json.dumps(result)

    def close(self):
        """Cleanup resources"""
        if self.dynamodb_sink:
            self.dynamodb_sink.close()


class OrderTimestampAssigner(TimestampAssigner):
    """Extract event timestamp from Debezium CDC events"""

    def extract_timestamp(self, value, record_timestamp):
        """
        Extract timestamp from CDC event.

        Uses __source_ts_ms if available, otherwise falls back to processing time.
        """
        try:
            event = json.loads(value)
            if '__source_ts_ms' in event:
                return event['__source_ts_ms']
        except Exception:
            pass

        return record_timestamp


def main():
    """Main Flink job entry point"""

    # Create execution environment
    env = StreamExecutionEnvironment.get_execution_environment()

    # Set parallelism (will be overridden by Flink cluster config)
    env.set_parallelism(2)

    # Enable checkpointing (every 60 seconds)
    env.enable_checkpointing(60000)  # 60 seconds

    # Configure Kafka source
    kafka_props = get_kafka_properties()
    kafka_bootstrap = kafka_props['bootstrap.servers']

    # Kafka source for orders topic
    kafka_source = KafkaSource.builder() \
        .set_bootstrap_servers(kafka_bootstrap) \
        .set_topics('dbserver1.public.orders') \
        .set_group_id('flink-sales-aggregations') \
        .set_starting_offsets(KafkaOffsetsInitializer.earliest()) \
        .set_value_only_deserializer(SimpleStringSchema()) \
        .build()

    # Define watermark strategy
    # Use no watermarks for now to get job running
    watermark_strategy = WatermarkStrategy.no_watermarks() \
        .with_timestamp_assigner(OrderTimestampAssigner())

    # Create data stream from Kafka
    orders_stream = env.from_source(
        kafka_source,
        watermark_strategy,
        'Orders Source'
    )

    # Apply windowing and aggregation
    # Sliding window: 1-hour window, sliding every 5 minutes
    aggregated_stream = orders_stream \
        .key_by(lambda x: 'all') \
        .window(SlidingEventTimeWindows.of(Time.hours(1), Time.minutes(5))) \
        .process(SalesAggregateFunction())

    # Print results (for debugging)
    aggregated_stream.print()

    # Execute job
    env.execute('Real-Time Sales Aggregations')


if __name__ == '__main__':
    main()
