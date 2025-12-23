"""
Prometheus metrics instrumentation for CDC consumer applications.

This module provides common Prometheus metrics and utilities for tracking
consumer application performance and health.
"""

from prometheus_client import Counter, Histogram, Gauge, Summary, start_http_server, Info
import functools
import time
import logging

logger = logging.getLogger(__name__)


# Application info
app_info = Info('consumer_app', 'Consumer application information')

# Message processing metrics
messages_processed = Counter(
    'consumer_messages_processed_total',
    'Total number of messages processed',
    ['topic', 'service']
)

messages_failed = Counter(
    'consumer_messages_failed_total',
    'Total number of messages that failed processing',
    ['topic', 'service', 'error_type']
)

# Processing duration
processing_duration = Histogram(
    'consumer_processing_duration_seconds',
    'Time spent processing messages',
    ['topic', 'service'],
    buckets=[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0]
)

processing_latency = Summary(
    'consumer_processing_latency_seconds',
    'Processing latency (time from message timestamp to processing)',
    ['topic', 'service']
)

# Consumer lag
consumer_lag = Gauge(
    'consumer_lag',
    'Current consumer lag (messages behind)',
    ['topic', 'partition', 'service', 'consumer_group']
)

# Batch processing metrics
batch_size = Histogram(
    'consumer_batch_size',
    'Number of messages in processed batch',
    ['service'],
    buckets=[1, 5, 10, 25, 50, 100, 250, 500, 1000]
)

# Output sink metrics
s3_writes_total = Counter(
    'consumer_s3_writes_total',
    'Total number of S3 writes',
    ['service', 'bucket']
)

s3_write_errors = Counter(
    'consumer_s3_write_errors_total',
    'Total number of S3 write errors',
    ['service', 'bucket', 'error_type']
)

s3_write_duration = Histogram(
    'consumer_s3_write_duration_seconds',
    'Duration of S3 write operations',
    ['service', 'bucket'],
    buckets=[0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0]
)

dynamodb_writes_total = Counter(
    'consumer_dynamodb_writes_total',
    'Total number of DynamoDB writes',
    ['service', 'table']
)

dynamodb_write_errors = Counter(
    'consumer_dynamodb_write_errors_total',
    'Total number of DynamoDB write errors',
    ['service', 'table', 'error_type']
)

dynamodb_write_duration = Histogram(
    'consumer_dynamodb_write_duration_seconds',
    'Duration of DynamoDB write operations',
    ['service', 'table'],
    buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0]
)

# Health metrics
errors_total = Counter(
    'consumer_errors_total',
    'Total number of errors',
    ['service', 'error_type']
)

kafka_connection_errors = Counter(
    'consumer_kafka_connection_errors_total',
    'Total number of Kafka connection errors',
    ['service']
)

# Resource usage tracking
active_processing = Gauge(
    'consumer_active_processing',
    'Number of messages currently being processed',
    ['service']
)


class MetricsContext:
    """Context manager for tracking metrics during message processing."""

    def __init__(self, topic: str, service: str):
        self.topic = topic
        self.service = service
        self.start_time = None

    def __enter__(self):
        self.start_time = time.time()
        active_processing.labels(service=self.service).inc()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        duration = time.time() - self.start_time
        active_processing.labels(service=self.service).dec()

        if exc_type is None:
            # Success
            messages_processed.labels(topic=self.topic, service=self.service).inc()
            processing_duration.labels(topic=self.topic, service=self.service).observe(duration)
        else:
            # Failure
            error_type = exc_type.__name__ if exc_type else 'Unknown'
            messages_failed.labels(
                topic=self.topic,
                service=self.service,
                error_type=error_type
            ).inc()
            errors_total.labels(service=self.service, error_type=error_type).inc()
            logger.error(f"Message processing failed: {exc_val}")

        return False  # Don't suppress exceptions


def track_processing(topic: str, service: str):
    """Decorator to track message processing metrics."""
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            with MetricsContext(topic, service):
                return func(*args, **kwargs)
        return wrapper
    return decorator


def track_s3_write(service: str, bucket: str):
    """Decorator to track S3 write metrics."""
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                s3_writes_total.labels(service=service, bucket=bucket).inc()
                duration = time.time() - start_time
                s3_write_duration.labels(service=service, bucket=bucket).observe(duration)
                return result
            except Exception as e:
                error_type = type(e).__name__
                s3_write_errors.labels(
                    service=service,
                    bucket=bucket,
                    error_type=error_type
                ).inc()
                raise
        return wrapper
    return decorator


def track_dynamodb_write(service: str, table: str):
    """Decorator to track DynamoDB write metrics."""
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                dynamodb_writes_total.labels(service=service, table=table).inc()
                duration = time.time() - start_time
                dynamodb_write_duration.labels(service=service, table=table).observe(duration)
                return result
            except Exception as e:
                error_type = type(e).__name__
                dynamodb_write_errors.labels(
                    service=service,
                    table=table,
                    error_type=error_type
                ).inc()
                raise
        return wrapper
    return decorator


def update_consumer_lag(topic: str, partition: int, service: str,
                       consumer_group: str, lag: int):
    """Update consumer lag gauge."""
    consumer_lag.labels(
        topic=topic,
        partition=partition,
        service=service,
        consumer_group=consumer_group
    ).set(lag)


def start_metrics_server(port: int = 8080):
    """Start Prometheus metrics HTTP server."""
    try:
        start_http_server(port)
        logger.info(f"Prometheus metrics server started on port {port}")
    except Exception as e:
        logger.error(f"Failed to start metrics server: {e}")
        raise


def set_app_info(service: str, version: str, environment: str = "production"):
    """Set application info metric."""
    app_info.info({
        'service': service,
        'version': version,
        'environment': environment
    })
