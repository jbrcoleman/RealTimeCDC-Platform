# CDC Consumer Services

This directory contains Kubernetes manifests for deploying three CDC consumer applications that process real-time database changes from Kafka.

## Consumer Services

### 1. Inventory Service
**Purpose**: Real-time inventory tracking

- **Topics**: `dbserver1.public.products`, `dbserver1.public.order_items`
- **Storage**: DynamoDB (`inventory-realtime` table)
- **Features**:
  - Tracks product stock levels in real-time
  - Atomically decrements inventory on order creation
  - Alerts on low stock (< 10 units)
  - Dead letter queue for failed messages

### 2. Analytics Service
**Purpose**: Aggregates order and sales data

- **Topics**: `dbserver1.public.orders`, `dbserver1.public.order_items`
- **Storage**: S3 Data Lake (`cdc-platform-data-lake-*`)
- **Features**:
  - Daily sales aggregation
  - Top 100 products by revenue
  - Top 100 customers by spend
  - Order status distribution
  - Flushes analytics every 5 minutes

### 3. Search Indexer
**Purpose**: Maintains searchable product catalog

- **Topics**: `dbserver1.public.products`
- **Storage**: DynamoDB (`product-search-index` table)
- **Features**:
  - Full-text search tokenization
  - Name and price indexes (GSI)
  - Real-time index updates on product changes
  - Automatic cleanup on product deletion

## Prerequisites

### 1. ECR Repositories
Create ECR repositories for each service:

```bash
aws ecr create-repository --repository-name inventory-service --region us-east-1
aws ecr create-repository --repository-name analytics-service --region us-east-1
aws ecr create-repository --repository-name search-indexer --region us-east-1
```

### 2. Build and Push Docker Images

**Inventory Service**:
```bash
cd apps/python/inventory-service
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

docker build -t inventory-service:latest .
docker tag inventory-service:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/inventory-service:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/inventory-service:latest
```

**Analytics Service**:
```bash
cd apps/python/analytics-service
docker build -t analytics-service:latest .
docker tag analytics-service:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/analytics-service:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/analytics-service:latest
```

**Search Indexer**:
```bash
cd apps/python/search-indexer
docker build -t search-indexer:latest .
docker tag search-indexer:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/search-indexer:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/search-indexer:latest
```

### 3. Update Deployment Manifests

Replace `ACCOUNT_ID` in all deployment files with your AWS account ID:

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" k8s/consumers/*-deployment.yaml
```

## Deployment

### Deploy All Consumer Services

```bash
kubectl apply -f k8s/consumers/
```

This deploys:
- 3 Deployments (one per service)
- 3 Services (for potential metrics endpoints)
- Uses existing service accounts with Pod Identity

### Verify Deployment

```bash
# Check pod status
kubectl get pods -n cdc-consumers

# Expected output:
# NAME                                READY   STATUS    RESTARTS   AGE
# inventory-service-xxx               1/1     Running   0          1m
# analytics-service-xxx               1/1     Running   0          1m
# search-indexer-xxx                  1/1     Running   0          1m

# Check logs
kubectl logs -l app=inventory-service -n cdc-consumers --tail=50
kubectl logs -l app=analytics-service -n cdc-consumers --tail=50
kubectl logs -l app=search-indexer -n cdc-consumers --tail=50
```

## Service Accounts and Permissions

Each consumer uses a dedicated Kubernetes service account with EKS Pod Identity:

| Service | Service Account | AWS Permissions |
|---------|----------------|-----------------|
| inventory-service | `inventory-service` | DynamoDB (read/write), S3 (DLQ write) |
| analytics-service | `analytics-service` | S3 (data lake write) |
| search-indexer | `search-indexer` | DynamoDB (read/write) |

These are configured in `k8s/service-accounts/service-accounts.yaml` and linked via Terraform Pod Identity associations.

## Configuration

### Environment Variables

All services support these common variables:
- `KAFKA_BOOTSTRAP_SERVERS`: Kafka cluster address
- `KAFKA_GROUP_ID`: Consumer group ID (unique per service)
- `AWS_REGION`: AWS region for SDK

Service-specific variables are documented in each app's README.

### Resource Limits

Current settings (per pod):
- **Requests**: 256Mi memory, 200m CPU
- **Limits**: 512Mi memory, 500m CPU

Adjust based on your message volume:

```bash
kubectl set resources deployment/inventory-service -n cdc-consumers \
  --requests=cpu=500m,memory=512Mi \
  --limits=cpu=1000m,memory=1Gi
```

## Scaling

### Horizontal Scaling

Scale consumer replicas to increase throughput:

```bash
# Scale to 3 replicas
kubectl scale deployment/inventory-service -n cdc-consumers --replicas=3

# Auto-scaling based on CPU
kubectl autoscale deployment/inventory-service -n cdc-consumers \
  --cpu-percent=70 --min=1 --max=5
```

**Note**: Multiple replicas in the same consumer group distribute partition processing.

### Vertical Scaling

Increase resources for higher throughput per pod:

```bash
kubectl set resources deployment/analytics-service -n cdc-consumers \
  --limits=cpu=2000m,memory=2Gi
```

## Monitoring

### Check Consumer Lag

```bash
# Exec into Kafka pod
kubectl exec -it cdc-platform-kafka-brokers-0 -n kafka -- bash

# Check consumer group lag
bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group inventory-service-group --describe

bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group analytics-service-group --describe

bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group search-indexer-group --describe
```

### View DynamoDB Tables

```bash
# Inventory table
aws dynamodb scan --table-name inventory-realtime --max-items 5

# Search index table
aws dynamodb scan --table-name product-search-index --max-items 5
```

### View Analytics in S3

```bash
# List analytics reports
aws s3 ls s3://cdc-platform-data-lake-<account-id>/analytics/ --recursive

# Download summary report
aws s3 cp s3://cdc-platform-data-lake-<account-id>/analytics/summary/ . --recursive
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod -l app=inventory-service -n cdc-consumers

# Common issues:
# - Image pull errors (check ECR permissions)
# - Service account not found (apply service-accounts.yaml)
# - Kafka not reachable (check kafka namespace)
```

### Consumer Lag Increasing

```bash
# Scale up replicas
kubectl scale deployment/inventory-service -n cdc-consumers --replicas=3

# Check resource utilization
kubectl top pods -n cdc-consumers
```

### DynamoDB Throttling

```bash
# Check CloudWatch metrics or logs
kubectl logs -l app=inventory-service -n cdc-consumers | grep -i throttl

# Solution: Switch to on-demand billing or increase provisioned capacity
```

### No Data in S3/DynamoDB

```bash
# Verify Kafka topics have data
kubectl exec -it cdc-platform-kafka-brokers-0 -n kafka -- \
  bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic dbserver1.public.products --from-beginning --max-messages 1

# Check Pod Identity
kubectl exec -it <pod-name> -n cdc-consumers -- env | grep AWS
kubectl exec -it <pod-name> -n cdc-consumers -- aws s3 ls
```

## Testing

### Generate Test Data

```bash
# Connect to RDS
cd terraform
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)

kubectl run psql-client --rm -it --restart=Never --image=postgres:16 --namespace=kafka \
  -- psql -h $RDS_ENDPOINT -U dbadmin -d ecommerce

# Insert test product
INSERT INTO products (name, description, price, stock_quantity)
VALUES ('Test Product', 'CDC Test', 99.99, 100);

# Create test order
INSERT INTO orders (customer_id, total_amount, status)
VALUES (9999, 199.98, 'pending')
RETURNING id;

# Insert order item (replace <order_id>)
INSERT INTO order_items (order_id, product_id, quantity, price)
SELECT <order_id>, id, 2, price FROM products WHERE name = 'Test Product';
```

### Verify Processing

```bash
# Check inventory service
aws dynamodb get-item --table-name inventory-realtime \
  --key '{"product_id": {"N": "<product_id>"}}'

# Check analytics (wait 5+ minutes for flush)
aws s3 ls s3://cdc-platform-data-lake-<account-id>/analytics/summary/ | tail -1

# Check search index
aws dynamodb scan --table-name product-search-index \
  --filter-expression "contains(name_lower, :name)" \
  --expression-attribute-values '{":name":{"S":"test"}}'
```

## Cleanup

```bash
# Delete consumer deployments
kubectl delete -f k8s/consumers/

# Delete DynamoDB tables (optional)
aws dynamodb delete-table --table-name inventory-realtime
aws dynamodb delete-table --table-name product-search-index

# Clean S3 analytics data (optional)
aws s3 rm s3://cdc-platform-data-lake-<account-id>/analytics/ --recursive
```

## Future Enhancements

- [ ] Add Prometheus metrics export
- [ ] Implement circuit breakers for AWS services
- [ ] Add consumer metrics dashboards (Grafana)
- [ ] Implement exactly-once semantics with Kafka transactions
- [ ] Add schema validation with Schema Registry
- [ ] Implement backpressure handling
- [ ] Add distributed tracing (OpenTelemetry)
