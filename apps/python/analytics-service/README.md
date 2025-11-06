# Analytics Service

Real-time analytics aggregation service that consumes order and order_items CDC events and generates analytics reports in S3.

## Features

- **Real-time Aggregation**: Processes orders and order items as they happen
- **Multiple Analytics Views**: Daily sales, product sales, customer metrics, order status
- **Time-windowed Flushing**: Writes aggregated data to S3 periodically
- **Top N Reports**: Generates top 100 products and customers
- **Graceful Shutdown**: Flushes final analytics before exit

## Analytics Reports Generated

### 1. Daily Sales Report
```json
{
  "report_type": "daily_sales",
  "generated_at": "2025-01-15T10:30:00",
  "data": {
    "2025-01-15": {
      "total_amount": 15420.50,
      "order_count": 42
    }
  }
}
```

### 2. Product Sales Report
```json
{
  "report_type": "product_sales",
  "generated_at": "2025-01-15T10:30:00",
  "data": {
    "123": {
      "quantity_sold": 25,
      "total_revenue": 32499.75
    }
  }
}
```

### 3. Customer Metrics Report
```json
{
  "report_type": "customer_metrics",
  "generated_at": "2025-01-15T10:30:00",
  "data": {
    "1001": {
      "order_count": 8,
      "total_spent": 5240.92
    }
  }
}
```

### 4. Order Status Distribution
```json
{
  "report_type": "order_status_distribution",
  "generated_at": "2025-01-15T10:30:00",
  "data": {
    "completed": 150,
    "pending": 23,
    "processing": 12
  }
}
```

### 5. Summary Report
```json
{
  "report_type": "summary",
  "generated_at": "2025-01-15T10:30:00",
  "metrics": {
    "total_orders": 185,
    "total_revenue": 45230.50,
    "unique_customers": 87,
    "unique_products_sold": 42,
    "order_status_breakdown": {
      "completed": 150,
      "pending": 23,
      "processing": 12
    }
  }
}
```

## S3 Data Layout

```
s3://bucket/
  analytics/
    daily_sales/
      20250115_103000.json
      20250115_104500.json
    product_sales/
      20250115_103000.json
    customer_metrics/
      20250115_103000.json
    order_status/
      20250115_103000.json
    summary/
      20250115_103000.json
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BOOTSTRAP_SERVERS` | Kafka broker addresses | `cdc-platform-kafka-bootstrap.kafka.svc.cluster.local:9092` |
| `KAFKA_GROUP_ID` | Consumer group ID | `analytics-service-group` |
| `KAFKA_TOPICS` | Comma-separated topic list | `dbserver1.public.orders,dbserver1.public.order_items` |
| `S3_BUCKET` | S3 bucket for analytics | (required) |
| `AWS_REGION` | AWS region | `us-east-1` |
| `FLUSH_INTERVAL` | Seconds between S3 flushes | `300` (5 minutes) |

## AWS Permissions Required

The service account needs these IAM permissions (provided via EKS Pod Identity):

- `s3:PutObject`
- `s3:ListBucket`

## Aggregation Logic

### In-Memory Buffers
Analytics are aggregated in memory and flushed periodically to S3:
- **Time-windowed**: Every N seconds (configurable)
- **On shutdown**: Final flush before process exits
- **Memory efficient**: Only keeps current window in memory

### Event Processing
- **Orders**: Aggregates by date, customer, and status
- **Order Items**: Aggregates by product
- **Updates**: Handles order status changes correctly

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export KAFKA_BOOTSTRAP_SERVERS=localhost:9092
export AWS_REGION=us-east-1
export S3_BUCKET=my-analytics-bucket
export FLUSH_INTERVAL=60

# Run
python app.py
```

## Build Docker Image

```bash
docker build -t analytics-service:latest .
docker run --rm \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:9092 \
  -e S3_BUCKET=analytics-bucket \
  analytics-service:latest
```

## Kubernetes Deployment

See `k8s/consumers/analytics-service/` for deployment manifests.

## Monitoring

Key logs to monitor:
- Flush events (every FLUSH_INTERVAL seconds)
- Message processing count
- S3 write errors
- Order status changes

## Performance Tuning

- **FLUSH_INTERVAL**: Lower for more frequent updates, higher for better aggregation
- **Consumer group instances**: Scale horizontally for parallel processing
- **Memory**: Monitor buffer sizes for high-volume scenarios
