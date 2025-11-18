#!/usr/bin/env python3
"""
Inventory Service - Real-time CDC Consumer
Tracks product inventory levels by consuming Kafka CDC events
"""

import os
import json
import logging
import signal
import sys
import base64
from typing import Dict, Any, Optional
from datetime import datetime

import boto3
from confluent_kafka import Consumer, KafkaError, KafkaException
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment variables
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'cdc-platform-kafka-bootstrap.kafka.svc.cluster.local:9092')
KAFKA_GROUP_ID = os.getenv('KAFKA_GROUP_ID', 'inventory-service-group')
KAFKA_TOPICS = os.getenv('KAFKA_TOPICS', 'dbserver1.public.products,dbserver1.public.order_items').split(',')
DYNAMODB_TABLE = os.getenv('DYNAMODB_TABLE', 'inventory-realtime')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')
DLQ_S3_BUCKET = os.getenv('DLQ_S3_BUCKET', '')

# Initialize AWS clients (Pod Identity provides credentials automatically)
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
s3_client = boto3.client('s3', region_name=AWS_REGION)

# Global flag for graceful shutdown
running = True


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global running
    logger.info(f"Received signal {signum}, initiating graceful shutdown...")
    running = False


def create_dynamodb_table_if_not_exists():
    """Create DynamoDB table for inventory tracking if it doesn't exist"""
    try:
        table = dynamodb.Table(DYNAMODB_TABLE)
        table.load()
        logger.info(f"DynamoDB table '{DYNAMODB_TABLE}' already exists")
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            logger.info(f"Creating DynamoDB table '{DYNAMODB_TABLE}'...")
            table = dynamodb.create_table(
                TableName=DYNAMODB_TABLE,
                KeySchema=[
                    {'AttributeName': 'product_id', 'KeyType': 'HASH'}
                ],
                AttributeDefinitions=[
                    {'AttributeName': 'product_id', 'AttributeType': 'N'}
                ],
                BillingMode='PAY_PER_REQUEST'
            )
            table.wait_until_exists()
            logger.info(f"DynamoDB table '{DYNAMODB_TABLE}' created successfully")
        else:
            logger.error(f"Error checking/creating DynamoDB table: {e}")
            raise


def parse_cdc_event(message: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Parse Debezium CDC event structure
    Handles both standard and ExtractNewRecordState transformed messages

    ExtractNewRecordState format (flattened):
    {
        "payload": {
            "id": 1,
            "name": "Product",
            "__op": "c",
            "__source_table": "products",
            "__deleted": "false"
        }
    }

    Standard Debezium format:
    {
        "payload": {
            "before": {...},
            "after": {...},
            "op": "c|u|d|r",
            "source": {...}
        }
    }
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


def decode_decimal_bytes(encoded_bytes: str, scale: int = 2) -> float:
    """
    Decode Debezium-encoded decimal bytes
    Debezium encodes DECIMAL as base64-encoded bytes
    """
    try:
        if isinstance(encoded_bytes, (int, float)):
            return float(encoded_bytes)

        # Decode base64
        decimal_bytes = base64.b64decode(encoded_bytes)

        # Convert bytes to integer (big-endian)
        value = int.from_bytes(decimal_bytes, byteorder='big', signed=True)

        # Apply scale (divide by 10^scale)
        return value / (10 ** scale)
    except Exception as e:
        logger.warning(f"Could not decode decimal bytes '{encoded_bytes}': {e}")
        return 0.0


def process_product_event(event: Dict[str, Any]) -> bool:
    """
    Process product CDC events (CREATE, UPDATE, DELETE)
    Updates DynamoDB with current product inventory
    """
    try:
        operation = event['operation']
        after = event['after']
        before = event['before']

        table = dynamodb.Table(DYNAMODB_TABLE)

        if operation in ['c', 'r', 'u']:  # Create, Read (snapshot), Update
            if after:
                product_id = after['id']

                # Handle Debezium-encoded decimal
                price_raw = after.get('price', 0)
                price = decode_decimal_bytes(price_raw) if isinstance(price_raw, str) else float(price_raw)

                item = {
                    'product_id': product_id,
                    'name': after['name'],
                    'description': after.get('description', ''),
                    'price': f"{price:.2f}",  # Store as formatted string
                    'stock_quantity': after['stock_quantity'],
                    'last_updated': datetime.utcnow().isoformat(),
                    'cdc_timestamp': event['timestamp']
                }

                table.put_item(Item=item)
                logger.info(f"Updated inventory for product_id={product_id}, stock={after['stock_quantity']}")
                return True

        elif operation == 'd':  # Delete
            if before:
                product_id = before['id']
                table.delete_item(Key={'product_id': product_id})
                logger.info(f"Deleted product_id={product_id} from inventory")
                return True

        return False

    except Exception as e:
        logger.error(f"Error processing product event: {e}")
        return False


def process_order_item_event(event: Dict[str, Any]) -> bool:
    """
    Process order_items CDC events
    Decrements product inventory when order items are created
    """
    try:
        operation = event['operation']
        after = event['after']

        # Only process CREATE operations (new orders reduce inventory)
        if operation in ['c', 'r'] and after:
            product_id = after['product_id']
            quantity = after['quantity']

            table = dynamodb.Table(DYNAMODB_TABLE)

            # Atomic decrement of stock_quantity
            response = table.update_item(
                Key={'product_id': product_id},
                UpdateExpression='ADD stock_quantity :decr SET last_updated = :timestamp',
                ExpressionAttributeValues={
                    ':decr': -quantity,
                    ':timestamp': datetime.utcnow().isoformat()
                },
                ReturnValues='UPDATED_NEW'
            )

            new_stock = response['Attributes'].get('stock_quantity', 0)
            logger.info(f"Decremented inventory for product_id={product_id} by {quantity}, new stock={new_stock}")

            # Alert if stock is low
            if new_stock < 10:
                logger.warning(f"LOW STOCK ALERT: product_id={product_id} has only {new_stock} items remaining")

            return True

        return False

    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            logger.error(f"Product not found in inventory: product_id={after.get('product_id')}")
        else:
            logger.error(f"Error processing order_item event: {e}")
        return False
    except Exception as e:
        logger.error(f"Error processing order_item event: {e}")
        return False


def send_to_dlq(topic: str, message: str, error: str):
    """Send failed messages to Dead Letter Queue (S3)"""
    if not DLQ_S3_BUCKET:
        logger.warning("DLQ S3 bucket not configured, skipping DLQ write")
        return

    try:
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S_%f')
        key = f"dlq/inventory-service/{topic}/{timestamp}.json"

        dlq_payload = {
            'topic': topic,
            'message': message,
            'error': error,
            'timestamp': datetime.utcnow().isoformat(),
            'service': 'inventory-service'
        }

        s3_client.put_object(
            Bucket=DLQ_S3_BUCKET,
            Key=key,
            Body=json.dumps(dlq_payload),
            ContentType='application/json'
        )

        logger.info(f"Sent failed message to DLQ: s3://{DLQ_S3_BUCKET}/{key}")
    except Exception as e:
        logger.error(f"Failed to write to DLQ: {e}")


def process_message(msg):
    """Process a single Kafka message"""
    try:
        # Parse JSON message
        value = json.loads(msg.value().decode('utf-8'))
        topic = msg.topic()

        # Parse CDC event structure
        event = parse_cdc_event(value)
        if not event:
            logger.warning(f"Failed to parse CDC event from topic {topic}")
            send_to_dlq(topic, msg.value().decode('utf-8'), "Failed to parse CDC event")
            return

        # Route to appropriate handler based on table
        success = False
        if event['table'] == 'products':
            success = process_product_event(event)
        elif event['table'] == 'order_items':
            success = process_order_item_event(event)
        else:
            logger.warning(f"Unknown table: {event['table']}")

        if not success:
            send_to_dlq(topic, msg.value().decode('utf-8'), "Processing failed")

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        send_to_dlq(msg.topic(), msg.value().decode('utf-8'), f"JSON decode error: {e}")
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        send_to_dlq(msg.topic(), msg.value().decode('utf-8'), f"Processing error: {e}")


def main():
    """Main consumer loop"""
    global running

    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    logger.info("Starting Inventory Service...")
    logger.info(f"Kafka Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Consumer Group: {KAFKA_GROUP_ID}")
    logger.info(f"Topics: {KAFKA_TOPICS}")
    logger.info(f"DynamoDB Table: {DYNAMODB_TABLE}")

    # Create DynamoDB table if needed
    create_dynamodb_table_if_not_exists()

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
        # Subscribe to topics
        consumer.subscribe(KAFKA_TOPICS)
        logger.info(f"Subscribed to topics: {KAFKA_TOPICS}")

        # Main consumption loop
        msg_count = 0
        while running:
            msg = consumer.poll(timeout=1.0)

            if msg is None:
                continue

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    logger.debug(f"Reached end of partition {msg.partition()}")
                elif msg.error():
                    logger.error(f"Kafka error: {msg.error()}")
                    raise KafkaException(msg.error())
            else:
                # Process message
                process_message(msg)
                msg_count += 1

                if msg_count % 100 == 0:
                    logger.info(f"Processed {msg_count} messages")

        logger.info(f"Shutting down after processing {msg_count} messages")

    except Exception as e:
        logger.error(f"Fatal error in consumer: {e}")
        sys.exit(1)
    finally:
        # Clean shutdown
        logger.info("Closing consumer...")
        consumer.close()
        logger.info("Consumer closed successfully")


if __name__ == '__main__':
    main()
