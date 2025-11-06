#!/usr/bin/env python3
"""
Search Indexer Service - Real-time CDC Consumer
Maintains a searchable product index in DynamoDB by consuming product CDC events
"""

import os
import json
import logging
import signal
import sys
import re
from typing import Dict, Any, Optional, List
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
KAFKA_GROUP_ID = os.getenv('KAFKA_GROUP_ID', 'search-indexer-group')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'dbserver1.public.products')
DYNAMODB_TABLE = os.getenv('DYNAMODB_TABLE', 'product-search-index')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)

# Global flag for graceful shutdown
running = True


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global running
    logger.info(f"Received signal {signum}, initiating graceful shutdown...")
    running = False


def create_search_index_table():
    """
    Create DynamoDB table optimized for product search
    Includes GSI for searching by name
    """
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
                    {'AttributeName': 'product_id', 'AttributeType': 'N'},
                    {'AttributeName': 'name_lower', 'AttributeType': 'S'},
                    {'AttributeName': 'price', 'AttributeType': 'N'}
                ],
                GlobalSecondaryIndexes=[
                    {
                        'IndexName': 'name-index',
                        'KeySchema': [
                            {'AttributeName': 'name_lower', 'KeyType': 'HASH'}
                        ],
                        'Projection': {'ProjectionType': 'ALL'}
                    },
                    {
                        'IndexName': 'price-index',
                        'KeySchema': [
                            {'AttributeName': 'price', 'KeyType': 'HASH'}
                        ],
                        'Projection': {'ProjectionType': 'ALL'}
                    }
                ],
                BillingMode='PAY_PER_REQUEST'
            )

            table.wait_until_exists()
            logger.info(f"DynamoDB table '{DYNAMODB_TABLE}' created successfully")
        else:
            logger.error(f"Error checking/creating DynamoDB table: {e}")
            raise


def parse_cdc_event(message: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Parse Debezium CDC event structure"""
    try:
        payload = message.get('payload', {})
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


def tokenize_text(text: str) -> List[str]:
    """
    Tokenize text for search indexing
    Converts to lowercase and splits on non-alphanumeric characters
    """
    if not text:
        return []

    # Convert to lowercase and split on non-alphanumeric
    tokens = re.findall(r'\w+', text.lower())
    return list(set(tokens))  # Remove duplicates


def build_search_index(product: Dict[str, Any]) -> Dict[str, Any]:
    """
    Build a searchable index document for a product
    Includes tokenized fields for full-text search
    """
    product_id = product['id']
    name = product.get('name', '')
    description = product.get('description', '')
    price = float(product.get('price', 0))

    # Tokenize name and description for search
    name_tokens = tokenize_text(name)
    desc_tokens = tokenize_text(description)
    all_tokens = list(set(name_tokens + desc_tokens))

    # Build search document
    search_doc = {
        'product_id': product_id,
        'name': name,
        'name_lower': name.lower(),
        'description': description,
        'price': int(price * 100),  # Store as cents for DynamoDB Number type
        'price_display': f"${price:.2f}",
        'stock_quantity': product.get('stock_quantity', 0),
        'search_tokens': all_tokens,  # For client-side filtering
        'indexed_at': datetime.utcnow().isoformat(),
        'cdc_timestamp': product.get('updated_at', product.get('created_at', ''))
    }

    return search_doc


def index_product(product: Dict[str, Any]) -> bool:
    """
    Index a product for search
    Creates/updates the search index in DynamoDB
    """
    try:
        search_doc = build_search_index(product)
        table = dynamodb.Table(DYNAMODB_TABLE)

        table.put_item(Item=search_doc)

        logger.info(f"Indexed product: id={product['id']}, name='{product['name']}'")
        return True

    except Exception as e:
        logger.error(f"Error indexing product {product.get('id')}: {e}")
        return False


def delete_product_from_index(product_id: int) -> bool:
    """Remove a product from the search index"""
    try:
        table = dynamodb.Table(DYNAMODB_TABLE)

        table.delete_item(Key={'product_id': product_id})

        logger.info(f"Deleted product from index: id={product_id}")
        return True

    except Exception as e:
        logger.error(f"Error deleting product {product_id} from index: {e}")
        return False


def process_product_event(event: Dict[str, Any]) -> bool:
    """
    Process product CDC events
    Indexes products for search
    """
    try:
        operation = event['operation']
        after = event['after']
        before = event['before']

        if operation in ['c', 'r', 'u']:  # Create, Read (snapshot), Update
            if after:
                return index_product(after)

        elif operation == 'd':  # Delete
            if before:
                product_id = before['id']
                return delete_product_from_index(product_id)

        return False

    except Exception as e:
        logger.error(f"Error processing product event: {e}")
        return False


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

        # Process product events
        if event['table'] == 'products':
            process_product_event(event)
        else:
            logger.debug(f"Skipping unknown table: {event['table']}")

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
    except Exception as e:
        logger.error(f"Error processing message: {e}")


def main():
    """Main consumer loop"""
    global running

    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    logger.info("Starting Search Indexer Service...")
    logger.info(f"Kafka Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Consumer Group: {KAFKA_GROUP_ID}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    logger.info(f"DynamoDB Table: {DYNAMODB_TABLE}")

    # Create DynamoDB table if needed
    create_search_index_table()

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
        consumer.subscribe([KAFKA_TOPIC])
        logger.info(f"Subscribed to topic: {KAFKA_TOPIC}")

        msg_count = 0
        indexed_count = 0

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
                process_message(msg)
                msg_count += 1
                indexed_count += 1

                if msg_count % 100 == 0:
                    logger.info(f"Processed {msg_count} messages, indexed {indexed_count} products")

        logger.info(f"Shutting down after processing {msg_count} messages")

    except Exception as e:
        logger.error(f"Fatal error in consumer: {e}")
        sys.exit(1)
    finally:
        logger.info("Closing consumer...")
        consumer.close()
        logger.info("Consumer closed successfully")


if __name__ == '__main__':
    main()
