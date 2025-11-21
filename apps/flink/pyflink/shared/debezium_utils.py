"""Utilities for handling Debezium CDC events"""
import base64
import struct
from decimal import Decimal


def parse_debezium_decimal(encoded_value, scale=2):
    """
    Parse Debezium's base64-encoded decimal values.

    Debezium encodes DECIMAL/NUMERIC fields as base64 strings.
    This function decodes them back to Python Decimal.

    Args:
        encoded_value: Base64-encoded decimal string
        scale: Number of decimal places (default: 2)

    Returns:
        Decimal: Parsed decimal value

    Example:
        >>> parse_debezium_decimal("BQk=", scale=2)
        Decimal('12.99')
    """
    if encoded_value is None:
        return Decimal('0')

    if isinstance(encoded_value, (int, float)):
        return Decimal(str(encoded_value))

    try:
        # Decode base64
        decoded = base64.b64decode(encoded_value)

        # Convert bytes to integer (big-endian)
        int_value = int.from_bytes(decoded, byteorder='big', signed=True)

        # Apply scale
        decimal_value = Decimal(int_value) / Decimal(10 ** scale)
        return decimal_value
    except Exception as e:
        print(f"Error parsing decimal '{encoded_value}': {e}")
        return Decimal('0')


def extract_operation_type(record):
    """
    Extract Debezium operation type from CDC event.

    Args:
        record: Debezium CDC record (after ExtractNewRecordState transform)

    Returns:
        str: Operation type ('c', 'u', 'd', 'r') or 'unknown'
            c = create (INSERT)
            u = update (UPDATE)
            d = delete (DELETE)
            r = read (initial snapshot)
    """
    if '__op' in record:
        return record['__op']
    return 'unknown'


def is_delete_event(record):
    """Check if record is a DELETE event"""
    return extract_operation_type(record) == 'd'


def get_source_table(record):
    """Extract source table name from Debezium event"""
    if '__source_table' in record:
        return record['__source_table']
    return 'unknown'


def get_event_timestamp(record):
    """
    Extract event timestamp from Debezium event.

    Args:
        record: Debezium CDC record

    Returns:
        int: Event timestamp in milliseconds, or None
    """
    if '__source_ts_ms' in record:
        return record['__source_ts_ms']
    return None
