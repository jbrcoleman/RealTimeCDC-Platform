# Python Consumer Applications

Three microservices that process Change Data Capture (CDC) events from Kafka in real-time.

## Services Overview

### 1. Inventory Service
**Directory**: `inventory-service/`

Real-time inventory tracking consumer that maintains current product stock levels.

**Kafka Topics**:
- `dbserver1.public.products` - Product master data
- `dbserver1.public.order_items` - Order line items

**Storage**: DynamoDB table `inventory-realtime`

**Key Features**:
- Tracks product inventory in real-time
- Atomically decrements stock when orders are placed
- Alerts on low stock (< 10 units)
- Dead letter queue for failed messages
- Graceful shutdown with signal handling

**Use Cases**:
- Product availability checks for e-commerce UI
- Real-time inventory dashboards
- Low stock alerting and replenishment triggers

---

### 2. Analytics Service
**Directory**: `analytics-service/`

Aggregates order and sales data into analytical reports.

**Kafka Topics**:
- `dbserver1.public.orders` - Order headers
- `dbserver1.public.order_items` - Order line items

**Storage**: S3 Data Lake (`cdc-platform-data-lake-*`)

**Key Features**:
- Time-windowed aggregation (5-minute flushes)
- Multiple report types (daily sales, product sales, customer metrics)
- Top N rankings (top 100 products/customers)
- Order status distribution tracking
- Final flush on graceful shutdown

**Reports Generated**:
- Daily sales totals
- Product sales (quantity & revenue)
- Customer spending metrics
- Order status distribution
- Summary dashboards

**Use Cases**:
- Business intelligence and reporting
- Sales analytics and trends
- Customer behavior analysis
- Product performance tracking

---

### 3. Search Indexer
**Directory**: `search-indexer/`

Maintains a searchable product catalog with full-text search capabilities.

**Kafka Topics**:
- `dbserver1.public.products` - Product data

**Storage**: DynamoDB table `product-search-index`

**Key Features**:
- Full-text tokenization of names and descriptions
- DynamoDB Global Secondary Indexes for fast lookups
- Real-time index updates on product changes
- Automatic cleanup on product deletion
- Price-based filtering support

**Search Capabilities**:
- Search by product ID (primary key)
- Search by product name (GSI)
- Search by price (GSI)
- Full-text search by tokens

**Use Cases**:
- Product search API backend
- E-commerce catalog search
- Product recommendation systems
- Price comparison features

---

## Common Architecture

All services share a common design:

```python
┌─────────────────────────────────────┐
│      Kafka Consumer Loop            │
│  (confluent-kafka-python)           │
└──────────┬──────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│    Parse Debezium CDC Event         │
│  - operation (c/u/d/r)              │
│  - before/after payloads            │
│  - table metadata                   │
└──────────┬──────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│    Route by Table Name              │
│  - products → product_handler()     │
│  - orders → order_handler()         │
│  - order_items → item_handler()     │
└──────────┬──────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│    Process & Store                  │
│  - DynamoDB (inventory/search)      │
│  - S3 (analytics)                   │
│  - Dead Letter Queue (failures)     │
└─────────────────────────────────────┘
```

### Common Components

**CDC Event Structure** (Debezium format):
```json
{
  "payload": {
    "before": {...},      // State before change (null for INSERT)
    "after": {...},       // State after change (null for DELETE)
    "op": "c|u|d|r",     // Operation type
    "ts_ms": 1234567890,  // Timestamp
    "source": {
      "table": "products"
    }
  }
}
```

**Operation Types**:
- `c` - Create (INSERT)
- `u` - Update (UPDATE)
- `d` - Delete (DELETE)
- `r` - Read (initial snapshot)

**Error Handling**:
- JSON parsing errors → logged and skipped
- Processing errors → sent to DLQ (if configured)
- AWS service errors → logged with retry via consumer offset

**Graceful Shutdown**:
- SIGTERM/SIGINT signal handlers
- Flush in-memory buffers (analytics)
- Close Kafka consumer cleanly
- Commit final offsets

---

## Technology Stack

| Component | Library | Version |
|-----------|---------|---------|
| **Kafka Client** | confluent-kafka | 2.5.3 |
| **AWS SDK** | boto3 | 1.34.162 |
| **Python** | python | 3.11 |
| **Base Image** | python | 3.11-slim |

### Why Confluent Kafka?

- **Performance**: C-based librdkafka is faster than pure Python clients
- **Reliability**: Battle-tested in production environments
- **Features**: Full Kafka protocol support including transactions
- **Consumer Groups**: Proper partition rebalancing and offset management

---

## Deployment

### Quick Start

Use the automated deployment script:

```bash
./scripts/deploy-consumers.sh
```

This will:
1. Create ECR repositories
2. Build Docker images
3. Push to ECR
4. Update Kubernetes manifests
5. Deploy to cluster

### Manual Deployment

See [CONSUMER_DEPLOYMENT.md](../../CONSUMER_DEPLOYMENT.md) for detailed manual steps.

---

## Configuration

### Environment Variables

All services support these common variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BOOTSTRAP_SERVERS` | Kafka broker addresses | `cdc-platform-kafka-bootstrap.kafka.svc.cluster.local:9092` |
| `KAFKA_GROUP_ID` | Consumer group ID | `{service}-group` |
| `AWS_REGION` | AWS region for SDK | `us-east-1` |

Service-specific variables are documented in each service's README.

### Kafka Consumer Settings

```python
{
    'bootstrap.servers': 'kafka:9092',
    'group.id': 'service-group',
    'auto.offset.reset': 'earliest',       # Start from beginning for new groups
    'enable.auto.commit': True,            # Auto-commit offsets
    'auto.commit.interval.ms': 5000,       # Commit every 5 seconds
    'session.timeout.ms': 30000,           # 30s session timeout
    'heartbeat.interval.ms': 10000         # 10s heartbeat
}
```

**Processing Semantics**: At-least-once delivery
- Offsets committed after processing
- Messages may be reprocessed on failure
- Idempotent operations recommended (PUT vs APPEND)

---

## Development

### Local Setup

Each service can run locally for development:

```bash
cd inventory-service

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export KAFKA_BOOTSTRAP_SERVERS=localhost:9092
export AWS_REGION=us-east-1
export DYNAMODB_TABLE=inventory-realtime-dev

# Run
python app.py
```

### Testing Locally

1. **Run Kafka locally** (Docker Compose):
```bash
docker-compose up -d kafka
```

2. **Use LocalStack for AWS services**:
```bash
docker run -d -p 4566:4566 localstack/localstack
export AWS_ENDPOINT_URL=http://localhost:4566
```

3. **Produce test messages** to Kafka topics

### Docker Build

Each service includes a Dockerfile:

```bash
docker build -t inventory-service:latest .
docker run --rm \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:9092 \
  -e AWS_REGION=us-east-1 \
  inventory-service:latest
```

---

## Monitoring

### Logs

All services log to stdout in structured format:

```
2025-01-15 10:30:00 - inventory-service - INFO - Starting Inventory Service...
2025-01-15 10:30:05 - inventory-service - INFO - Subscribed to topics: ['dbserver1.public.products']
2025-01-15 10:30:15 - inventory-service - INFO - Processed 100 messages
```

**Log Levels**:
- `INFO`: Normal operations, message counts
- `WARNING`: Low stock alerts, missing data
- `ERROR`: Processing failures, AWS errors
- `DEBUG`: Detailed message processing (disabled by default)

### Metrics to Monitor

**Consumer Metrics**:
- Consumer lag (via Kafka consumer groups)
- Messages processed per second
- Processing errors
- DLQ writes

**AWS Metrics**:
- DynamoDB read/write throttling
- S3 put object latency
- Lambda invocations (if added)

**Application Metrics**:
- Processing latency (CDC timestamp to write timestamp)
- Buffer sizes (analytics service)
- Low stock alerts (inventory service)

### Health Checks

Kubernetes liveness/readiness probes:

```yaml
livenessProbe:
  exec:
    command: ["python", "-c", "import sys; sys.exit(0)"]
  initialDelaySeconds: 30
  periodSeconds: 30
```

**Future Enhancement**: Add HTTP health endpoint with:
- Consumer connection status
- Last message timestamp
- AWS service connectivity

---

## Performance Tuning

### Horizontal Scaling

Scale consumer replicas to increase throughput:

```bash
kubectl scale deployment/inventory-service -n cdc-consumers --replicas=3
```

**Notes**:
- Multiple replicas share partitions in consumer group
- Each partition is consumed by only one replica
- Max useful replicas = number of partitions

### Vertical Scaling

Increase resources for higher throughput per pod:

```bash
kubectl set resources deployment/inventory-service -n cdc-consumers \
  --limits=cpu=2000m,memory=2Gi
```

### Kafka Configuration

Optimize for throughput vs latency:

**High Throughput**:
```python
'fetch.min.bytes': 100000,          # Wait for more data
'fetch.wait.max.ms': 500,           # Longer wait time
'max.partition.fetch.bytes': 10485760  # 10MB per partition
```

**Low Latency**:
```python
'fetch.min.bytes': 1,               # Don't wait
'fetch.wait.max.ms': 100,           # Quick polling
'enable.auto.commit': True
```

---

## Security

### AWS Permissions

Services use EKS Pod Identity (no static credentials):

**Inventory Service** (`inventory-service` SA):
- `dynamodb:*` on `inventory-realtime` table
- `s3:PutObject` on DLQ bucket

**Analytics Service** (`analytics-service` SA):
- `s3:PutObject` on data lake bucket

**Search Indexer** (`search-indexer` SA):
- `dynamodb:*` on `product-search-index` table

### Network Security

- Services run in `cdc-consumers` namespace
- Communicate with Kafka in `kafka` namespace
- Egress to AWS services (S3, DynamoDB)
- No ingress required (pull-based consumers)

### Secrets Management

Database credentials and sensitive config should use:
- AWS Secrets Manager
- Kubernetes Secrets
- External Secrets Operator

---

## Troubleshooting

### Common Issues

**1. No messages being consumed**

Check Kafka connectivity:
```bash
kubectl exec -it <pod-name> -n cdc-consumers -- \
  python3 -c "from confluent_kafka.admin import AdminClient; \
  a = AdminClient({'bootstrap.servers': 'cdc-platform-kafka-bootstrap.kafka.svc.cluster.local:9092'}); \
  print(a.list_topics().topics)"
```

**2. DynamoDB throttling**

Tables use on-demand billing and auto-scale. If throttling persists:
- Check for hot partitions
- Review access patterns
- Consider batch writes

**3. Consumer lag increasing**

Scale horizontally:
```bash
kubectl scale deployment/inventory-service -n cdc-consumers --replicas=3
```

**4. Out of memory errors**

Increase memory limits:
```bash
kubectl set resources deployment/analytics-service -n cdc-consumers \
  --limits=memory=2Gi
```

---

## Future Enhancements

### Phase 1: Observability
- [ ] Add Prometheus metrics export
- [ ] Implement HTTP health/readiness endpoints
- [ ] Add distributed tracing (OpenTelemetry)
- [ ] Create Grafana dashboards

### Phase 2: Reliability
- [ ] Implement circuit breakers for AWS services
- [ ] Add retry logic with exponential backoff
- [ ] Schema validation with Schema Registry
- [ ] Exactly-once semantics with Kafka transactions

### Phase 3: Features
- [ ] Add support for Avro/Protobuf deserialization
- [ ] Implement message filtering (ksqlDB-style)
- [ ] Add data quality checks
- [ ] Support for multiple sinks per consumer

### Phase 4: Operations
- [ ] Auto-scaling based on consumer lag
- [ ] Canary deployments
- [ ] Blue-green deployment support
- [ ] Backup and restore for state stores

---

## Contributing

When adding new consumers:

1. Follow the existing structure:
   - `app.py` - Main application
   - `requirements.txt` - Dependencies
   - `Dockerfile` - Container image
   - `README.md` - Service documentation

2. Include:
   - Graceful shutdown handling
   - Error handling and DLQ
   - Logging with structured format
   - Health checks

3. Update:
   - `k8s/consumers/` - Kubernetes manifests
   - `k8s/service-accounts/` - Service account if new
   - `terraform/iam.tf` - IAM role if new permissions needed
   - This README with service overview

---

## Resources

- [Confluent Kafka Python Docs](https://docs.confluent.io/kafka-clients/python/current/overview.html)
- [Debezium CDC Format](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-events)
- [Boto3 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)

---

## License

Part of the RealTimeCDC-Platform project.
