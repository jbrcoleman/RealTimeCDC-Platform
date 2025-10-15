# Kafka Cluster Configuration

This directory contains the Kafka cluster configuration using Strimzi operator for the CDC platform.

## Components

### 1. Strimzi Operator (Helm Chart)
- **Version**: Strimzi Kafka operator v0.48.0
- Creates necessary CRDs (Kafka, KafkaConnect, KafkaTopic, KafkaConnector, KafkaNodePool)
- Manages Kafka cluster lifecycle
- Namespace-scoped installation in `kafka` namespace
- Installed via Helm for better lifecycle management

### 2. Kafka Cluster (`kafka-cluster.yaml`)
- **Architecture**: KRaft mode (no ZooKeeper) - Kafka 4.1.0
- **Kafka Brokers**: 3 replicas for high availability (combined controller+broker roles)
- **Storage**: 20Gi persistent volumes (gp2 via EBS CSI) per broker
- **Listeners**: Internal plaintext (9092) and TLS (9093)
- **Multi-AZ**: Rack awareness enabled for zone distribution

**Key Configuration:**
```yaml
Kafka Version: 4.1.0
Metadata Version: 4.1-IV0 (KRaft)
Node Pool: kafka-brokers (3 replicas, controller+broker roles)
Replication Factor: 3
Min In-Sync Replicas: 2
Log Retention: 7 days
Compression: Snappy
Auto-create Topics: Enabled
Storage Class: gp2 (EBS)
```

**Resources per Broker (via KafkaNodePool):**
- Memory: 2Gi (1Gi heap)
- CPU: 500m request, 1000m limit
- Storage: 20Gi EBS gp2 volume

### 3. Kafka Topics (`kafka-topics.yaml`)
Pre-created topics for CDC pipeline:

#### CDC Data Topics
- `dbserver1.public.products` - Product change events
- `dbserver1.public.orders` - Order change events
- `dbserver1.public.order-items` - Order item change events

**Settings:**
- Partitions: 3
- Replication: 3
- Retention: 7 days
- Compression: Snappy

#### Compacted Topics (Latest State)
- `dbserver1.public.products.compacted`
- `dbserver1.public.orders.compacted`

**Settings:**
- Cleanup policy: compact (keeps only latest value per key)
- Useful for state rebuilding

#### Internal Topics
- `dbserver1` - Schema changes
- `connect-configs` - Connector configurations
- `connect-offsets` - Source connector offsets
- `connect-status` - Connector/task statuses
- `cdc-dlq` - Dead letter queue for failed events

### 4. Kafka Connect (`kafka-connect.yaml`)
- **Replicas**: 2 for high availability
- **Image**: Debezium Connect 2.7 with PostgreSQL connector
- **Service Account**: Uses IRSA for AWS access (S3, Secrets Manager)

**Built-in Connectors:**
- Debezium PostgreSQL Connector 2.7.0
- Kafka Connect S3 Sink Connector 10.5.13

**Resources per Pod:**
- Memory: 2Gi (1Gi heap)
- CPU: 500m request, 1000m limit

## Prerequisites

Before deploying Kafka, ensure the following are installed:

### 1. EBS CSI Driver (REQUIRED)
The Kafka cluster requires EBS volumes for persistent storage. The EBS CSI driver with proper IAM permissions must be installed.

**Already configured in Terraform** (`terraform/iam.tf`):
- IAM role: `cdc-platform-ebs-csi-driver`
- Service account: `kube-system:ebs-csi-controller-sa`
- Policy: Full EBS volume management permissions

**Install the addon:**
```bash
# Get the IAM role ARN from Terraform
cd terraform
terraform output ebs_csi_driver_role_arn

# Install EBS CSI driver addon
aws eks create-addon \
  --cluster-name cdc-platform \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $(terraform output -raw ebs_csi_driver_role_arn) \
  --region us-east-1

# Wait for it to be ready
aws eks wait addon-active \
  --cluster-name cdc-platform \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1
```

**Verify:**
```bash
# Check EBS CSI pods are running
kubectl get pods -n kube-system | grep ebs-csi

# Expected: 2 controller pods (6/6) and multiple node pods (3/3)
```

### 2. Strimzi Operator RBAC
The operator needs additional rolebindings that may not be created automatically:

```bash
# Create missing rolebindings (if needed)
kubectl create rolebinding strimzi-cluster-operator-entity-operator-delegation \
  --clusterrole=strimzi-entity-operator \
  --serviceaccount=kafka:strimzi-cluster-operator \
  -n kafka 2>/dev/null || true

kubectl create rolebinding strimzi-cluster-operator-watched \
  --clusterrole=strimzi-cluster-operator-watched \
  --serviceaccount=kafka:strimzi-cluster-operator \
  -n kafka 2>/dev/null || true
```

## Deployment

### Option 1: Automated Script (Recommended)
```bash
# Run the automated installation script
chmod +x scripts/install-kafka.sh
./scripts/install-kafka.sh
```

This script will:
1. Install Strimzi operator via Helm
2. Deploy Kafka cluster with KRaft mode
3. Create topics
4. Deploy Kafka Connect
5. Verify installation

### Option 2: Manual Helm Installation
```bash
# Add Strimzi Helm repository
helm repo add strimzi https://strimzi.io/charts/
helm repo update

# Install Strimzi operator
helm install strimzi-operator strimzi/strimzi-kafka-operator \
  --namespace kafka \
  --create-namespace \
  --values k8s/kafka/helm-values.yaml \
  --wait \
  --timeout 10m

# Wait for operator to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/strimzi-cluster-operator -n kafka

# Deploy Kafka cluster
kubectl apply -f k8s/kafka/kafka-cluster.yaml

# Wait for Kafka to be ready
kubectl wait --for=condition=ready --timeout=600s \
  kafka/cdc-platform -n kafka

# Deploy topics and Kafka Connect
kubectl apply -f k8s/kafka/kafka-topics.yaml
kubectl apply -f k8s/kafka/kafka-connect.yaml
```

### Option 3: Via ArgoCD
```bash
# ArgoCD will automatically deploy when you apply the root app
kubectl apply -f argocd/apps/kafka.yaml

# Or sync manually
argocd app sync kafka-cluster
```

**Note**: The raw Kubernetes manifests (`strimzi-operator.yaml`) are provided for reference but Helm installation is recommended for better reliability.

## Verification

### Check Operator Status
```bash
kubectl get pods -n kafka -l name=strimzi-cluster-operator
```

### Check Kafka Cluster
```bash
# Check Kafka resource
kubectl get kafka -n kafka

# Check KafkaNodePool
kubectl get kafkanodepool -n kafka

# Check broker pods (KRaft mode - no ZooKeeper)
kubectl get pods -n kafka -l strimzi.io/cluster=cdc-platform

# Expected: 3 Kafka broker pods (combined controller+broker)
# cdc-platform-kafka-brokers-0, cdc-platform-kafka-brokers-1, cdc-platform-kafka-brokers-2
# Plus: entity-operator pod and kafka-exporter pod
```

### Check Topics
```bash
# Via kubectl
kubectl get kafkatopic -n kafka

# Via Kafka CLI (exec into broker)
kubectl exec -it cdc-platform-kafka-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Check Kafka Connect
```bash
# Check KafkaConnect resource
kubectl get kafkaconnect -n kafka

# Check connect pods
kubectl get pods -n kafka -l strimzi.io/cluster=cdc-platform-connect

# Check connector plugins
kubectl exec -it <connect-pod> -n kafka -- \
  curl -s localhost:8083/connector-plugins | jq
```

## Monitoring

Kafka cluster exposes Prometheus metrics:

```bash
# Port-forward to Kafka broker
kubectl port-forward cdc-platform-kafka-0 9404:9404 -n kafka

# Access metrics
curl http://localhost:9404/metrics
```

**Key Metrics:**
- `kafka_server_replicamanager_*` - Replication metrics
- `kafka_server_brokertopicmetrics_*` - Topic throughput
- `kafka_log_log_size` - Topic size
- `kafka_connect_connector_*` - Connector metrics

## Testing

### Producer Test
```bash
# Exec into Kafka broker
kubectl exec -it cdc-platform-kafka-0 -n kafka -- bash

# Create test topic
bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic test --partitions 3 --replication-factor 3

# Produce messages
bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic test
```

### Consumer Test
```bash
# Consume messages
bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic test \
  --from-beginning
```

### Connect REST API Test
```bash
# Port-forward to Connect
kubectl port-forward svc/cdc-platform-connect-api -n kafka 8083:8083

# Check cluster info
curl http://localhost:8083/ | jq

# List connector plugins
curl http://localhost:8083/connector-plugins | jq

# Check connectors
curl http://localhost:8083/connectors | jq
```

## Scaling

### Scale Kafka Brokers
```bash
# Edit Kafka resource
kubectl edit kafka cdc-platform -n kafka

# Change spec.kafka.replicas to desired count
# Strimzi will handle rolling update
```

### Scale Kafka Connect
```bash
# Edit KafkaConnect resource
kubectl edit kafkaconnect cdc-platform-connect -n kafka

# Change spec.replicas to desired count
```

## Troubleshooting

### Common Issues

#### 1. PVCs Stuck in Pending
If PVCs remain in Pending state, the EBS CSI driver is likely not installed or not working:

```bash
# Check PVC status
kubectl get pvc -n kafka

# Check PVC events
kubectl describe pvc data-cdc-platform-kafka-brokers-0 -n kafka

# Common error: "storageclass.storage.k8s.io 'gp2' not found" or
# "Waiting for a volume to be created by external provisioner 'ebs.csi.aws.com'"

# Solution: Install EBS CSI driver (see Prerequisites section)
```

#### 2. Kafka Version Incompatibility
Strimzi 0.48.0 only supports Kafka 4.0.0 and 4.1.0:

```bash
# Check Kafka status for errors
kubectl get kafka cdc-platform -n kafka -o yaml | grep -A 10 "conditions:"

# Error: "Unsupported Kafka.spec.kafka.version: 3.x.x"
# Solution: Update kafka-cluster.yaml to use version: 4.1.0
```

#### 3. Missing KafkaNodePool
Strimzi 0.46.0+ requires KafkaNodePool resources (ZooKeeper is deprecated):

```bash
# Check if KafkaNodePool exists
kubectl get kafkanodepool -n kafka

# Error in Kafka status: "No KafkaNodePools found for Kafka cluster"
# Solution: Ensure kafka-cluster.yaml includes KafkaNodePool resource
```

#### 4. RBAC Permissions Issues
Operator may lack permissions to watch/manage resources:

```bash
# Check operator logs for 403 Forbidden errors
kubectl logs deployment/strimzi-cluster-operator -n kafka | grep -i "403\|forbidden"

# Solution: Create missing rolebindings (see Prerequisites section)
```

### Broker Not Starting
```bash
# Check broker logs
kubectl logs cdc-platform-kafka-brokers-0 -n kafka -c kafka

# Check storage
kubectl get pvc -n kafka

# Check events
kubectl get events -n kafka --sort-by='.lastTimestamp'
```

### Topics Not Created
```bash
# Check topic operator
kubectl logs -n kafka -l strimzi.io/name=cdc-platform-entity-operator -c topic-operator

# Describe topic resource
kubectl describe kafkatopic <topic-name> -n kafka
```

### Connect Not Starting
```bash
# Check connect logs
kubectl logs -n kafka -l strimzi.io/cluster=cdc-platform-connect

# Check service account (IRSA)
kubectl describe sa kafka-connect -n kafka

# Check if plugins loaded
kubectl logs <connect-pod> -n kafka | grep -i plugin
```

### Connection Issues
```bash
# Test from inside cluster
kubectl run kafka-test --rm -it --restart=Never \
  --image=confluentinc/cp-kafka:7.5.0 \
  --namespace=kafka \
  -- bash

# Inside pod, test connection
kafka-broker-api-versions --bootstrap-server cdc-platform-kafka-bootstrap:9092
```

## Configuration Updates

### Update Kafka Configuration
```bash
# Edit kafka-cluster.yaml
# Update spec.kafka.config section
# Apply changes
kubectl apply -f k8s/kafka/kafka-cluster.yaml

# Strimzi will perform rolling update
```

### Add New Topic
```bash
# Create new KafkaTopic resource
cat <<EOF | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: new-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: cdc-platform
spec:
  partitions: 3
  replicas: 3
  config:
    retention.ms: 604800000
    compression.type: snappy
EOF
```

## Security Considerations

1. **Network Policies**: TODO - Add network policies to restrict traffic
2. **TLS**: TLS listener available on port 9093
3. **Authentication**: TODO - Add SASL authentication
4. **Authorization**: TODO - Add Kafka ACLs
5. **IRSA**: Kafka Connect uses IAM roles for AWS access

## Resources

- [Strimzi Documentation](https://strimzi.io/docs/)
- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [Debezium Documentation](https://debezium.io/documentation/)
