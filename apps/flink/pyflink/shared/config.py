"""Configuration utilities for Flink jobs"""
import os


def get_aws_region():
    """Get AWS region from environment"""
    return os.getenv('AWS_REGION', 'us-east-1')


def get_dynamodb_endpoint():
    """Get DynamoDB endpoint (useful for local testing)"""
    return os.getenv('DYNAMODB_ENDPOINT', None)


def get_s3_checkpoint_path():
    """Get S3 path for Flink checkpoints"""
    bucket = os.getenv('S3_CHECKPOINT_BUCKET', 'flink-checkpoints')
    return f's3://{bucket}/checkpoints'


def get_table_name(base_name):
    """
    Get DynamoDB table name with environment prefix.

    Args:
        base_name: Base table name (e.g., 'sales_metrics')

    Returns:
        str: Prefixed table name (e.g., 'cdc-platform-sales-metrics')
    """
    prefix = os.getenv('TABLE_PREFIX', 'cdc-platform')
    return f'{prefix}-{base_name}'
