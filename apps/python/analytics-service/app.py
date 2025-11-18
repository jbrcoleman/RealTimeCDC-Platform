#!/usr/bin/env python3
"""
Analytics Service - Real-time CDC Consumer
Aggregates order and sales data from Kafka CDC events and writes to S3
"""

import os
import json
import logging
import signal
import sys
from typing import Dict, Any, Optional
from datetime import datetime, date
from collections import defaultdict
from decimal import Decimal

import boto3
from confluent_kafka import Consumer, KafkaError, KafkaException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment variables
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'cdc-platform-kafka-bootstrap.kafka.svc.cluster.local:9092')
KAFKA_GROUP_ID = os.getenv('KAFKA_GROUP_ID', 'analytics-service-group')
KAFKA_TOPICS = os.getenv('KAFKA_TOPICS', 'dbserver1.public.orders,dbserver1.public.order_items').split(',')
S3_BUCKET = os.getenv('S3_BUCKET', '')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')
FLUSH_INTERVAL = int(os.getenv('FLUSH_INTERVAL', '300'))  # Flush every 5 minutes

# Initialize AWS clients
s3_client = boto3.client('s3', region_name=AWS_REGION)

# Global flag for graceful shutdown
running = True

# In-memory aggregation buffers
sales_by_date = defaultdict(lambda: {'total_amount': Decimal('0'), 'order_count': 0})
product_sales = defaultdict(lambda: {'quantity_sold': 0, 'total_revenue': Decimal('0')})
customer_metrics = defaultdict(lambda: {'order_count': 0, 'total_spent': Decimal('0')})
order_status_counts = defaultdict(int)

last_flush_time = datetime.utcnow()


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global running
    logger.info(f"Received signal {signum}, initiating graceful shutdown...")
    running = False


def parse_cdc_event(message: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Parse Debezium CDC event structure
    Handles ExtractNewRecordState transformation where data is flattened
    """
    try:
        payload = message.get('payload', {})

        # Check if this is an ExtractNewRecordState transformed message
        # (has __op, __source_table, data directly in payload)
        if '__op' in payload:
            operation = payload.get('__op')
            table = payload.get('__source_table', '')
            is_deleted = payload.get('__deleted', 'false') == 'true'

            # For delete operations, the data is in the payload (before state)
            # For create/update, the data is also directly in payload (after state)
            if is_deleted or operation == 'd':
                before = {k: v for k, v in payload.items() if not k.startswith('__')}
                after = None
            else:
                before = None
                after = {k: v for k, v in payload.items() if not k.startswith('__')}

            return {
                'operation': operation,
                'before': before,
                'after': after,
                'table': table,
                'timestamp': payload.get('__source_ts_ms', 0)
            }

        # Standard Debezium format (non-transformed)
        else:
            operation = payload.get('op')
            before = payload.get('before')
            after = payload.get('after')
            source = payload.get('source', {})
            table = source.get('table', '')

            return {
                'operation': operation,
                'before': before,
                'after': after,
                'table': table,
                'timestamp': payload.get('ts_ms', 0)
            }
    except Exception as e:
        logger.error(f"Error parsing CDC event: {e}")
        return None


def process_order_event(event: Dict[str, Any]):
    """
    Process order CDC events
    Aggregates daily sales and customer metrics
    """
    try:
        operation = event['operation']
        after = event['after']
        before = event['before']

        if operation in ['c', 'r']:  # Create or Read (snapshot)
            if after:
                order_date = after['created_at'][:10]  # Extract YYYY-MM-DD
                customer_id = after['customer_id']
                total_amount = Decimal(str(after['total_amount']))
                status = after['status']

                # Aggregate daily sales
                sales_by_date[order_date]['total_amount'] += total_amount
                sales_by_date[order_date]['order_count'] += 1

                # Aggregate customer metrics
                customer_metrics[customer_id]['order_count'] += 1
                customer_metrics[customer_id]['total_spent'] += total_amount

                # Track order status distribution
                order_status_counts[status] += 1

                logger.debug(f"Processed order: order_id={after['id']}, amount={total_amount}, status={status}")

        elif operation == 'u':  # Update
            # Handle status changes
            if before and after:
                old_status = before['status']
                new_status = after['status']

                if old_status != new_status:
                    order_status_counts[old_status] -= 1
                    order_status_counts[new_status] += 1
                    logger.info(f"Order {after['id']} status changed: {old_status} -> {new_status}")

    except Exception as e:
        logger.error(f"Error processing order event: {e}")


def process_order_item_event(event: Dict[str, Any]):
    """
    Process order_items CDC events
    Aggregates product sales metrics
    """
    try:
        operation = event['operation']
        after = event['after']

        if operation in ['c', 'r'] and after:  # Create or Read (snapshot)
            product_id = after['product_id']
            quantity = after['quantity']
            price = Decimal(str(after['price']))

            # Aggregate product sales
            product_sales[product_id]['quantity_sold'] += quantity
            product_sales[product_id]['total_revenue'] += (price * quantity)

            logger.debug(f"Processed order_item: product_id={product_id}, quantity={quantity}")

    except Exception as e:
        logger.error(f"Error processing order_item event: {e}")


def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


def flush_analytics_to_s3():
    """
    Flush aggregated analytics to S3
    Creates separate files for different analytics views
    """
    if not S3_BUCKET:
        logger.warning("S3 bucket not configured, skipping flush")
        return

    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')

    try:
        # 1. Daily Sales Report
        if sales_by_date:
            daily_sales = {
                'report_type': 'daily_sales',
                'generated_at': datetime.utcnow().isoformat(),
                'data': dict(sales_by_date)
            }

            s3_client.put_object(
                Bucket=S3_BUCKET,
                Key=f"analytics/daily_sales/{timestamp}.json",
                Body=json.dumps(daily_sales, default=decimal_default),
                ContentType='application/json'
            )
            logger.info(f"Flushed daily sales: {len(sales_by_date)} days")

        # 2. Product Sales Report
        if product_sales:
            # Sort by revenue (top sellers)
            sorted_products = sorted(
                product_sales.items(),
                key=lambda x: x[1]['total_revenue'],
                reverse=True
            )

            product_report = {
                'report_type': 'product_sales',
                'generated_at': datetime.utcnow().isoformat(),
                'data': dict(sorted_products[:100])  # Top 100 products
            }

            s3_client.put_object(
                Bucket=S3_BUCKET,
                Key=f"analytics/product_sales/{timestamp}.json",
                Body=json.dumps(product_report, default=decimal_default),
                ContentType='application/json'
            )
            logger.info(f"Flushed product sales: {len(product_sales)} products")

        # 3. Customer Metrics Report
        if customer_metrics:
            # Sort by total spent (top customers)
            sorted_customers = sorted(
                customer_metrics.items(),
                key=lambda x: x[1]['total_spent'],
                reverse=True
            )

            customer_report = {
                'report_type': 'customer_metrics',
                'generated_at': datetime.utcnow().isoformat(),
                'data': dict(sorted_customers[:100])  # Top 100 customers
            }

            s3_client.put_object(
                Bucket=S3_BUCKET,
                Key=f"analytics/customer_metrics/{timestamp}.json",
                Body=json.dumps(customer_report, default=decimal_default),
                ContentType='application/json'
            )
            logger.info(f"Flushed customer metrics: {len(customer_metrics)} customers")

        # 4. Order Status Distribution
        if order_status_counts:
            status_report = {
                'report_type': 'order_status_distribution',
                'generated_at': datetime.utcnow().isoformat(),
                'data': dict(order_status_counts)
            }

            s3_client.put_object(
                Bucket=S3_BUCKET,
                Key=f"analytics/order_status/{timestamp}.json",
                Body=json.dumps(status_report),
                ContentType='application/json'
            )
            logger.info(f"Flushed order status distribution")

        # 5. Summary Report
        summary = {
            'report_type': 'summary',
            'generated_at': datetime.utcnow().isoformat(),
            'metrics': {
                'total_orders': sum(day['order_count'] for day in sales_by_date.values()),
                'total_revenue': sum(day['total_amount'] for day in sales_by_date.values()),
                'unique_customers': len(customer_metrics),
                'unique_products_sold': len(product_sales),
                'order_status_breakdown': dict(order_status_counts)
            }
        }

        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=f"analytics/summary/{timestamp}.json",
            Body=json.dumps(summary, default=decimal_default),
            ContentType='application/json'
        )
        logger.info("Flushed summary report")

        logger.info(f"Successfully flushed all analytics to S3: s3://{S3_BUCKET}/analytics/")

    except Exception as e:
        logger.error(f"Error flushing analytics to S3: {e}")


def process_message(msg):
    """Process a single Kafka message"""
    try:
        value = json.loads(msg.value().decode('utf-8'))
        topic = msg.topic()

        # Parse CDC event structure
        event = parse_cdc_event(value)
        if not event:
            logger.warning(f"Failed to parse CDC event from topic {topic}")
            return

        # Route to appropriate handler
        if event['table'] == 'orders':
            process_order_event(event)
        elif event['table'] == 'order_items':
            process_order_item_event(event)
        else:
            logger.debug(f"Skipping unknown table: {event['table']}")

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
    except Exception as e:
        logger.error(f"Error processing message: {e}")


def should_flush() -> bool:
    """Check if it's time to flush analytics to S3"""
    global last_flush_time
    elapsed = (datetime.utcnow() - last_flush_time).total_seconds()
    return elapsed >= FLUSH_INTERVAL


def main():
    """Main consumer loop"""
    global running, last_flush_time

    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    logger.info("Starting Analytics Service...")
    logger.info(f"Kafka Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Consumer Group: {KAFKA_GROUP_ID}")
    logger.info(f"Topics: {KAFKA_TOPICS}")
    logger.info(f"S3 Bucket: {S3_BUCKET}")
    logger.info(f"Flush Interval: {FLUSH_INTERVAL}s")

    # Configure Kafka consumer
    conf = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'group.id': KAFKA_GROUP_ID,
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': True,
        'auto.commit.interval.ms': 5000,
        'session.timeout.ms': 30000,
        'heartbeat.interval.ms': 10000
    }

    consumer = Consumer(conf)

    try:
        consumer.subscribe(KAFKA_TOPICS)
        logger.info(f"Subscribed to topics: {KAFKA_TOPICS}")

        msg_count = 0
        while running:
            msg = consumer.poll(timeout=1.0)

            if msg is None:
                # Check if we should flush
                if should_flush():
                    flush_analytics_to_s3()
                    last_flush_time = datetime.utcnow()
                continue

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    logger.debug(f"Reached end of partition {msg.partition()}")
                elif msg.error():
                    logger.error(f"Kafka error: {msg.error()}")
                    raise KafkaException(msg.error())
            else:
                process_message(msg)
                msg_count += 1

                if msg_count % 100 == 0:
                    logger.info(f"Processed {msg_count} messages")

                # Periodic flush check
                if should_flush():
                    flush_analytics_to_s3()
                    last_flush_time = datetime.utcnow()

        # Final flush before shutdown
        logger.info(f"Shutting down after processing {msg_count} messages")
        flush_analytics_to_s3()

    except Exception as e:
        logger.error(f"Fatal error in consumer: {e}")
        sys.exit(1)
    finally:
        logger.info("Closing consumer...")
        consumer.close()
        logger.info("Consumer closed successfully")


if __name__ == '__main__':
    main()
