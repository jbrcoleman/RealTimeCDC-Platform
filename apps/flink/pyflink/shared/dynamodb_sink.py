"""DynamoDB sink function for Flink jobs"""
import boto3
import json
from datetime import datetime
from decimal import Decimal
from .config import get_aws_region, get_dynamodb_endpoint


class DynamoDBSink:
    """
    Custom sink function for writing Flink stream data to DynamoDB.

    This is a simple implementation. For production, consider using
    Flink's AsyncIO or custom async sink for better performance.
    """

    def __init__(self, table_name, batch_size=25):
        """
        Initialize DynamoDB sink.

        Args:
            table_name: DynamoDB table name
            batch_size: Number of items to batch before writing (max 25 for DynamoDB)
        """
        self.table_name = table_name
        self.batch_size = min(batch_size, 25)  # DynamoDB batch limit
        self.batch = []

        # Initialize DynamoDB client
        region = get_aws_region()
        endpoint = get_dynamodb_endpoint()

        if endpoint:
            self.dynamodb = boto3.resource('dynamodb', region_name=region, endpoint_url=endpoint)
        else:
            self.dynamodb = boto3.resource('dynamodb', region_name=region)

        self.table = self.dynamodb.Table(table_name)

    def write(self, item):
        """
        Write a single item to DynamoDB (batched).

        Args:
            item: Dictionary representing the item to write
        """
        # Convert to DynamoDB-compatible format
        dynamodb_item = self._convert_to_dynamodb_item(item)

        self.batch.append(dynamodb_item)

        # Flush if batch is full
        if len(self.batch) >= self.batch_size:
            self.flush()

    def flush(self):
        """Flush buffered items to DynamoDB"""
        if not self.batch:
            return

        try:
            # Use batch_writer for efficient writes
            with self.table.batch_writer() as batch:
                for item in self.batch:
                    batch.put_item(Item=item)

            print(f"Wrote {len(self.batch)} items to {self.table_name}")
            self.batch = []
        except Exception as e:
            print(f"Error writing to DynamoDB: {e}")
            # In production, consider DLQ or retry logic
            self.batch = []

    def _convert_to_dynamodb_item(self, item):
        """
        Convert Python dict to DynamoDB-compatible format.

        DynamoDB doesn't support:
        - None values (use empty string or omit)
        - float (use Decimal)
        - nested None values
        """
        dynamodb_item = {}

        for key, value in item.items():
            if value is None:
                continue  # Skip None values

            if isinstance(value, float):
                dynamodb_item[key] = Decimal(str(value))
            elif isinstance(value, dict):
                dynamodb_item[key] = self._convert_to_dynamodb_item(value)
            elif isinstance(value, list):
                dynamodb_item[key] = [
                    self._convert_to_dynamodb_item(v) if isinstance(v, dict) else v
                    for v in value if v is not None
                ]
            else:
                dynamodb_item[key] = value

        return dynamodb_item

    def close(self):
        """Flush remaining items on close"""
        self.flush()


class TimestampedDynamoDBSink(DynamoDBSink):
    """DynamoDB sink that automatically adds timestamps"""

    def write(self, item):
        """Add timestamp before writing"""
        item['updated_at'] = datetime.utcnow().isoformat()
        super().write(item)
