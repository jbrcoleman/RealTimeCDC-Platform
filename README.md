# RealTimeCDC-Platform
Real time change data capture platform
# RealTimeCDC-Platform

A production-ready, real-time Change Data Capture (CDC) platform built on AWS EKS, demonstrating modern data streaming architecture with Kafka, Debezium, and GitOps practices.

## 🎯 Project Overview

This platform captures database changes in real-time from PostgreSQL and streams them to multiple destinations for different use cases:
- **Data Lake (S3)**: Historical analytics and compliance
- **DynamoDB**: Fast materialized views for application reads
- **Stream Processing (Flink)**: Real-time transformations and aggregations
- **Consumer Microservices**: Event-driven Python applications

### Architecture

```
┌─────────────┐
│ PostgreSQL  │  (Source: E-commerce Database)
│   RDS       │
└──────┬──────┘
       │ Logical Replication
       ↓
┌──────────────────────────────────────────────┐
│         EKS Cluster (Kubernetes)             │
│                                              │
│  ┌──────────┐    ┌───────────┐             │
│  │ Debezium │───→│   Kafka   │             │
│  │  (CDC)   │    │ (Strimzi) │             │
│  └──────────┘    └─────┬─────┘             │
│                        │                     │
│         ┌──────────────┼──────────────┐     │
│         ↓              ↓              ↓     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │   Flink  │  │ Consumer │  │ Consumer │ │
│  │  Jobs    │  │ Service  │  │ Service  │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘ │
└───────┼─────────────┼─────────────┼────────┘
        ↓             ↓             ↓
   ┌────────┐    ┌─────────┐   ┌──────────┐
   │   S3   │    │ DynamoDB│   │    S3    │
   │  Lake  │    │  Tables │   │   DLQ    │
   └────────┘    └─────────┘   └──────────┘
```

## 🚀 Technologies Used

### Infrastructure
- **AWS EKS**: Kubernetes orchestration with Karpenter autoscaling
- **Terraform**: Infrastructure as Code for AWS resources
- **ArgoCD**: GitOps continuous delivery for Kubernetes

### Data Streaming
- **Apache Kafka (Strimzi)**: Distributed event streaming platform
- **Debezium**: Change data capture connector for PostgreSQL
- **Apache Flink**: Stream processing framework
- **Schema Registry**: Avro schema management

### Storage & Databases
- **Amazon RDS (PostgreSQL 16)**: Source transactional database
- **Amazon S3**: Data lake and dead letter queue storage
- **Amazon DynamoDB**: Materialized views for fast lookups

### Application Runtime
- **Python 3.11+**: Consumer microservices
- **FastAPI**: RESTful APIs for consumers
- **Boto3**: AWS SDK for Python

### Observability
- **Prometheus**: Metrics collection
- **Grafana**: Dashboards and visualization
- **CloudWatch**: AWS native monitoring

## 📁 Repository Structure

```
RealTimeCDC-Platform/
├── terraform/                      # Infrastructure as Code
│   ├── eks.tf                     # EKS cluster with Karpenter
│   ├── rds.tf                     # PostgreSQL with CDC enabled
│   ├── s3.tf                      # Data lake and storage buckets
│   ├── iam.tf                     # IRSA roles for Kubernetes
│   ├── vpc.tf                     # Networking configuration
│   ├── karpenter.tf               # Node autoscaling
│   └── outputs.tf                 # Terraform outputs
│
├── k8s/                           # Kubernetes manifests
│   ├── namespaces/
│   │   └── namespaces.yaml       # All namespace definitions
│   ├── service-accounts/
│   │   └── service-accounts.yaml # IRSA-enabled service accounts
│   ├── karpenter/
│   │   └── karpenter.yaml        # Node pools and classes
│   ├── kafka/                     # Kafka cluster configs (to be added)
│   ├── debezium/                  # CDC connector configs (to be added)
│   ├── flink/                     # Stream processing jobs (to be added)
│   └── consumers/                 # Consumer microservices (to be added)
│
├── argocd/                        # GitOps configuration
│   ├── bootstrap/
│   │   └── root-app.yaml         # App of Apps pattern
│   ├── projects/
│   │   └── cdc-platform.yaml     # ArgoCD project with RBAC
│   └── apps/
│       ├── kafka.yaml            # Kafka application
│       ├── debezium.yaml         # Debezium application
│       ├── consumers.yaml        # Consumer applications
│       ├── flink.yaml            # Flink applications
│       └── monitoring.yaml       # Observability stack
│
├── apps/                          # Application source code (to be added)
│   └── python/
│       ├── inventory-service/    # Real-time inventory tracker
│       ├── analytics-service/    # Analytics aggregations
│       └── search-indexer/       # Search index updater
│
├── scripts/                       # Automation scripts
│   ├── schema.sql                # Database schema definition
│   ├── init-database.sh          # Initialize RDS with schema
│   ├── install-kafka.sh          # Install Kafka cluster via Helm
│   ├── apply-service-accounts.sh # Deploy K8s service accounts
│   └── setup-argocd.sh           # Install and configure ArgoCD
│
├── DEPLOYMENT.md                  # Detailed deployment guide
└── README.md                      # This file
```

## 🛠️ Prerequisites

### Required Tools
- **AWS CLI** (v2.x): AWS authentication and resource management
- **Terraform** (>= 1.5): Infrastructure provisioning
- **kubectl** (>= 1.28): Kubernetes CLI
- **Helm** (>= 3.12): Kubernetes package manager
- **ArgoCD CLI** (optional): GitOps management
- **Docker**: Container image builds
- **Git**: Version control

### AWS Requirements
- AWS account with appropriate IAM permissions
- Configured AWS credentials (`aws configure`)
- Available VPC and subnet capacity
- Service quota for EKS clusters

### Knowledge Prerequisites
- Kubernetes fundamentals
- Basic understanding of CDC concepts
- Terraform syntax
- GitOps principles

## 🚦 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/YOUR_ORG/RealTimeCDC-Platform.git
cd RealTimeCDC-Platform
```

### 2. Deploy Infrastructure
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

**What gets created:**
- ✅ VPC with public/private subnets across 3 AZs
- ✅ EKS cluster (v1.33) with Karpenter autoscaling
- ✅ RDS PostgreSQL (v16.3) with logical replication enabled
- ✅ 3 S3 buckets (data lake, DLQ, Kafka Connect storage)
- ✅ 6 IAM roles with IRSA for pod-level permissions
- ✅ Security groups and networking
- ✅ CloudWatch log groups

### 3. Configure kubectl
```bash
# Get kubeconfig command from Terraform output
terraform output configure_kubectl

# Run it (example output):
aws eks --region us-east-1 update-kubeconfig --name cdc-platform

# Verify access
kubectl get nodes
```

### 4. Deploy Karpenter NodePool
```bash
cd ..  # Back to project root

# Apply Karpenter NodePool configuration to enable worker node provisioning
kubectl apply -f k8s/karpenter/karpenter.yaml

# Wait for Karpenter to provision worker nodes (1-2 minutes)
kubectl get nodes -w
```

**Important**: Terraform deploys Karpenter itself, but doesn't apply the NodePool configuration. Without this step, only controller nodes exist (with taints), preventing regular workloads from scheduling.

### 5. Deploy Service Accounts
```bash
chmod +x scripts/apply-service-accounts.sh
./scripts/apply-service-accounts.sh
```

### 6. Initialize Database Schema
```bash
chmod +x scripts/init-database.sh
./scripts/init-database.sh
```

**What gets created:**
- ✅ E-commerce tables: `products`, `orders`, `order_items`
- ✅ Sample data: 5 products, 3 orders, 4 order items
- ✅ CDC enabled: All tables configured with `REPLICA IDENTITY FULL`
- ✅ Indexes for query performance
- ✅ Foreign key relationships

**Alternative: Manual Schema Creation**
```bash
# Get RDS endpoint
cd terraform
terraform output rds_endpoint

# Connect using psql
kubectl run psql-client --rm -it --restart=Never \
  --image=postgres:16 --namespace=default \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce

# Run the schema file
\i scripts/schema.sql
```

### 7. Install ArgoCD
```bash
chmod +x scripts/setup-argocd.sh
./scripts/setup-argocd.sh
```

### 8. Update Repository URLs
Update all files in `argocd/` directory:
```bash
# Find files to update
grep -r "YOUR_ORG" argocd/

# Replace YOUR_ORG with your GitHub username/org
# Files to update:
# - argocd/bootstrap/root-app.yaml
# - argocd/projects/cdc-platform.yaml
# - argocd/apps/*.yaml
```

### 9. Deploy Platform via ArgoCD
```bash
# Apply ArgoCD project
kubectl apply -f argocd/projects/cdc-platform.yaml

# Deploy root application (App of Apps)
kubectl apply -f argocd/bootstrap/root-app.yaml

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:80

# GitHub Codespaces: Go to PORTS tab and click on port 8080 to open in browser
# Local: Open http://localhost:8080

# Login: admin / <password from setup script>
```

## 📊 IAM Roles & Service Accounts (IRSA)

The platform uses IAM Roles for Service Accounts (IRSA) for secure, pod-level AWS permissions without static credentials.

### Available Roles

| Service Account | Namespace | AWS Permissions | Use Case |
|----------------|-----------|-----------------|----------|
| `kafka-connect` | kafka | S3 read/write, Secrets Manager read | Kafka Connect S3 sink connector |
| `debezium` | kafka | Secrets Manager read | Read RDS credentials |
| `inventory-service` | cdc-consumers | S3 read, DynamoDB write, Secrets read | Inventory consumer |
| `analytics-service` | cdc-consumers | S3 read, DynamoDB write, Secrets read | Analytics consumer |
| `search-indexer` | cdc-consumers | S3 read, DynamoDB write, Secrets read | Search indexer |
| `flink-jobmanager` | flink | S3 read/write, CloudWatch metrics | Flink job manager |
| `flink-taskmanager` | flink | S3 read/write, CloudWatch metrics | Flink task manager |
| `schema-registry` | kafka | S3 read/write (schemas) | Avro schema storage |
| `external-secrets` | external-secrets | Secrets Manager read | Sync AWS secrets to K8s |

### How IRSA Works
1. Terraform creates IAM role with trust policy for specific K8s service account
2. Service account is annotated with IAM role ARN
3. EKS Pod Identity webhook injects temporary credentials
4. Pods automatically get AWS access without static keys

## 🗄️ Database Schema

The platform uses a sample e-commerce schema with three main tables designed for Change Data Capture.

### Tables

#### Products Table
```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### Orders Table
```sql
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### Order Items Table
```sql
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### CDC Configuration

All tables are configured with:
- **REPLICA IDENTITY FULL**: Required for Debezium to capture full row state
- **Primary keys**: For row identification
- **Foreign key relationships**: Between orders, products, and order_items
- **Timestamps**: For audit tracking
- **Indexes**: For query performance

### RDS PostgreSQL Settings
- **WAL level**: `logical` (enables change data capture)
- **Max replication slots**: 10
- **Max WAL senders**: 25
- **RDS logical replication**: Enabled via parameter group

### Schema Files
- `scripts/schema.sql`: Complete schema definition with sample data
- `scripts/init-database.sh`: Automated initialization script

## 🔄 GitOps Workflow

### Deployment Sync Waves
ArgoCD deploys components in order using sync waves:

```
Wave 0: External Secrets Operator
   ↓
Wave 1: Kafka Cluster, Prometheus/Grafana
   ↓
Wave 2: Schema Registry, Flink Operator
   ↓
Wave 3: Debezium Connectors
   ↓
Wave 4: Consumer Services, Flink Jobs
```

### Making Changes

**Infrastructure Changes (Terraform):**
```bash
# 1. Update Terraform files
vim terraform/rds.tf

# 2. Apply changes
cd terraform
terraform plan
terraform apply

# 3. Update K8s service accounts if IAM roles changed
cd ..
./scripts/apply-service-accounts.sh
```

**Application Changes (Consumer Services):**
```bash
# 1. Update application code
vim apps/python/inventory-service/app.py

# 2. Build and push Docker image
cd apps/python/inventory-service
docker build -t <registry>/inventory-service:v1.1.0 .
docker push <registry>/inventory-service:v1.1.0

# 3. Update Kubernetes manifest
cd ../../../k8s/consumers/inventory-service
vim deployment.yaml  # Update image tag

# 4. Commit and push
git add deployment.yaml
git commit -m "Deploy inventory-service v1.1.0"
git push

# 5. ArgoCD auto-syncs (or manual sync)
argocd app sync inventory-service
```

**Kafka/Debezium Configuration:**
```bash
# 1. Update connector config
vim k8s/debezium/postgres-connector.yaml

# 2. Commit and push
git add k8s/debezium/
git commit -m "Increase Debezium batch size"
git push

# 3. ArgoCD detects and applies change
# Watch in UI or: argocd app sync debezium-connectors
```

## 📈 Monitoring & Observability

### Accessing Grafana
```bash
kubectl port-forward svc/prometheus-operator-grafana -n monitoring 3000:80
# Open http://localhost:3000
# Login: admin / admin (change in production!)
```

### Pre-configured Dashboards
- Kafka cluster overview
- Kafka Connect connector status
- Consumer lag monitoring
- Flink job metrics
- Kubernetes cluster health

### Accessing Prometheus
```bash
kubectl port-forward svc/prometheus-operator-kube-prom-prometheus -n monitoring 9090:9090
# Open http://localhost:9090
```

### Key Metrics to Monitor
- **Kafka**: Topic lag, throughput, partition distribution
- **Debezium**: Connector status, snapshot progress, replication lag
- **Consumers**: Processing rate, error rate, DLQ events
- **Flink**: Checkpoint duration, backpressure, task status
- **RDS**: Replication slot lag, WAL generation rate

## 🧪 Testing CDC Pipeline

### 1. Insert Test Data
```bash
# Get RDS endpoint
cd terraform
terraform output rds_endpoint

# Connect to database
kubectl run psql-client --rm -it --restart=Never \
  --image=postgres:16 --namespace=kafka \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce

# Insert sample data
INSERT INTO products (name, description, price, stock_quantity) 
VALUES ('Test Product', 'CDC Test', 99.99, 100);

UPDATE products SET price = 89.99 WHERE name = 'Test Product';

DELETE FROM products WHERE name = 'Test Product';
```

### 2. Verify Kafka Topics
```bash
# List topics
kubectl exec -it cdc-platform-kafka-0 -n kafka -- bash
bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# Expected topics:
# - dbserver1.public.products
# - dbserver1.public.orders
# - dbserver1.public.order_items

# Consume events
bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic dbserver1.public.products \
  --from-beginning
```

### 3. Check S3 Data Lake
```bash
aws s3 ls s3://cdc-platform-data-lake-<account-id>/topics/
```

### 4. Verify Consumer Processing
```bash
kubectl logs -l app=inventory-service -n cdc-consumers
kubectl logs -l app=analytics-service -n cdc-consumers
```

## 🛡️ Security Best Practices

### Implemented
- ✅ VPC with private subnets for data plane
- ✅ EKS cluster endpoint restricted (can enable private)
- ✅ IRSA (no static AWS credentials)
- ✅ Secrets stored in AWS Secrets Manager
- ✅ RDS encryption at rest
- ✅ S3 bucket encryption (AES-256)
- ✅ Security groups with least privilege
- ✅ Network policies (to be added)

### Production Recommendations
- [ ] Enable EKS private endpoint
- [ ] Implement Pod Security Standards
- [ ] Add AWS WAF for API protection
- [ ] Enable VPC Flow Logs
- [ ] Implement secrets rotation
- [ ] Add network policies between namespaces
- [ ] Enable audit logging (CloudTrail, EKS audit logs)
- [ ] Implement certificate management (cert-manager)

## 💰 Cost Optimization

### Current Configuration (Dev)
- **EKS**: ~$73/month (control plane)
- **EC2**: ~$60/month (2x m5.large nodes)
- **RDS**: ~$25/month (db.t3.micro)
- **S3**: ~$5/month (with lifecycle policies)
- **Data Transfer**: Variable

**Estimated Total**: ~$165-200/month

### Cost Savings
- Karpenter uses Spot instances where possible
- S3 lifecycle policies move data to cheaper tiers
- RDS Multi-AZ disabled for dev
- Single NAT gateway in dev

### Production Considerations
- Enable RDS Multi-AZ for high availability
- Use reserved instances for baseline capacity
- Implement proper data retention policies
- Monitor and optimize S3 storage classes

## 🔧 Troubleshooting

### Debezium Not Capturing Changes
```bash
# Check connector status
kubectl get kafkaconnector -n kafka
kubectl describe kafkaconnector postgres-connector -n kafka

# Check connector logs
kubectl logs -l strimzi.io/cluster=kafka-connect -n kafka --tail=100

# Verify RDS logical replication
# Connect to RDS and run:
SHOW wal_level;  -- Should be 'logical'
SELECT * FROM pg_replication_slots;
```

### ArgoCD Application Out of Sync
```bash
# Check application status
argocd app get <app-name>

# View sync errors
argocd app logs <app-name>

# Force sync
argocd app sync <app-name> --force

# Refresh from Git
argocd app refresh <app-name>
```

### Pods Can't Access S3/RDS
```bash
# Verify service account has correct annotation
kubectl describe sa <service-account> -n <namespace>

# Check if pod has AWS credentials injected
kubectl exec -it <pod-name> -n <namespace> -- env | grep AWS

# Test AWS access from pod
kubectl exec -it <pod-name> -n <namespace> -- aws s3 ls
```

### Kafka Consumer Lag
```bash
# Check consumer group lag
kubectl exec -it cdc-platform-kafka-0 -n kafka -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group <consumer-group> \
  --describe

# Scale consumer deployment
kubectl scale deployment/<consumer-name> -n cdc-consumers --replicas=3
```

## 🧹 Cleanup

### Delete Kubernetes Resources
```bash
# Delete ArgoCD root app (cascades to all apps)
kubectl delete application cdc-platform-root -n argocd

# Or delete ArgoCD entirely
kubectl delete namespace argocd
```

### Destroy AWS Infrastructure
```bash
cd terraform
terraform destroy
```

**Warning**: This deletes:
- EKS cluster and all workloads
- RDS database (including data)
- S3 buckets (will fail if not empty)
- All IAM roles and policies

## 📚 Additional Resources

### Documentation
- [Deployment Guide](DEPLOYMENT.md) - Detailed step-by-step deployment
- [Debezium Docs](https://debezium.io/documentation/reference/stable/connectors/postgresql.html)
- [Strimzi Kafka Operator](https://strimzi.io/docs/operators/latest/overview.html)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Karpenter Documentation](https://karpenter.sh/docs/)

### AWS Resources
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

## 🎓 Learning Objectives

This project demonstrates proficiency in:
- ✅ Modern cloud-native architecture patterns
- ✅ Infrastructure as Code with Terraform
- ✅ Kubernetes orchestration and operations
- ✅ GitOps and continuous delivery
- ✅ Real-time data streaming and CDC
- ✅ Event-driven microservices architecture
- ✅ AWS services integration
- ✅ Security best practices (IRSA, encryption, least privilege)
- ✅ Monitoring and observability
- ✅ Production-ready deployment patterns
---

**Status**: 🚧 Active Development

**Last Updated**: October 2025