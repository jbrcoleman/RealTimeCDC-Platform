"""Kafka configuration for Flink jobs"""
import os


def get_kafka_properties():
    """
    Get Kafka connection properties for Flink Kafka connector.

    Returns:
        dict: Kafka properties including bootstrap servers and consumer config
    """
    kafka_bootstrap = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092')

    properties = {
        'bootstrap.servers': kafka_bootstrap,
        'group.id': 'flink-consumer-group',
        'auto.offset.reset': 'earliest',  # Start from beginning for new consumer groups
        'enable.auto.commit': 'false',  # Flink manages offsets
    }

    return properties


def get_kafka_topic_prefix():
    """Get the Debezium topic prefix"""
    return os.getenv('KAFKA_TOPIC_PREFIX', 'dbserver1.public')
