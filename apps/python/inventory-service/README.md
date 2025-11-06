# Inventory Service

Real-time inventory tracking consumer that processes CDC events from Kafka and maintains current inventory levels in DynamoDB.

## Features

- **Real-time Inventory Tracking**: Consumes product and order_items CDC events
- **DynamoDB Storage**: Fast materialized view for inventory lookups
- **Atomic Updates**: Uses DynamoDB atomic operations for concurrent safety
- **Low Stock Alerts**: Logs warnings when inventory drops below threshold
- **Dead Letter Queue**: Failed messages are sent to S3 DLQ for replay
- **Graceful Shutdown**: Handles SIGTERM/SIGINT properly
- **Auto-commit**: Commits offsets automatically for at-least-once processing

## CDC Event Processing

### Products Table Events
- **CREATE/UPDATE**: Upserts product information and stock quantity to DynamoDB
- **DELETE**: Removes product from inventory table

### Order Items Table Events
- **CREATE**: Atomically decrements product stock quantity
- Alerts if stock falls below 10 units

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BOOTSTRAP_SERVERS` | Kafka broker addresses | `cdc-platform-kafka-bootstrap.kafka.svc.cluster.local:9092` |
| `KAFKA_GROUP_ID` | Consumer group ID | `inventory-service-group` |
| `KAFKA_TOPICS` | Comma-separated topic list | `dbserver1.public.products,dbserver1.public.order_items` |
| `DYNAMODB_TABLE` | DynamoDB table name | `inventory-realtime` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `DLQ_S3_BUCKET` | S3 bucket for dead letter queue | (empty) |

## AWS Permissions Required

The service account needs these IAM permissions (provided via EKS Pod Identity):

- `dynamodb:CreateTable`
- `dynamodb:DescribeTable`
- `dynamodb:PutItem`
- `dynamodb:UpdateItem`
- `dynamodb:DeleteItem`
- `s3:PutObject` (for DLQ)

## DynamoDB Schema

```
Table: inventory-realtime
Primary Key: product_id (Number)

Item Structure:
{
  "product_id": 123,
  "name": "Laptop",
  "description": "High-performance laptop",
  "price": "1299.99",
  "stock_quantity": 45,
  "last_updated": "2025-01-15T10:30:00",
  "cdc_timestamp": 1736936400000
}
```

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export KAFKA_BOOTSTRAP_SERVERS=localhost:9092
export AWS_REGION=us-east-1
export DYNAMODB_TABLE=inventory-realtime-dev

# Run
python app.py
```

## Build Docker Image

```bash
# Build
docker build -t inventory-service:latest .

# Run
docker run --rm \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:9092 \
  -e AWS_REGION=us-east-1 \
  inventory-service:latest
```

## Kubernetes Deployment

See `k8s/consumers/inventory-service/` for deployment manifests.

## Monitoring

The service logs key metrics:
- Messages processed count (every 100 messages)
- Low stock alerts
- DLQ writes
- Processing errors

Integrate with Prometheus for metrics collection.
