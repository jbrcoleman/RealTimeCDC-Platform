# RealTimeCDC-Platform

A production-ready, real-time Change Data Capture (CDC) platform built on AWS EKS, demonstrating modern data streaming architecture with Kafka, Debezium, Flink, and GitOps practices.

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
┌────────────────────────────────────────────┐
│         EKS Cluster (Kubernetes)           │
│                                            │
│  ┌──────────┐    ┌───────────┐             │
│  │ Debezium │───→│   Kafka   │             │
│  │  (CDC)   │    │ (Strimzi) │             │
│  └──────────┘    └─────┬─────┘             │
│                        │                   │
│         ┌──────────────┼──────────────┐    │
│         ↓              ↓              ↓    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │   Flink  │  │ Consumer │  │ Consumer │  │
│  │  Jobs    │  │ Service  │  │ Service  │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  │
└───────┼─────────────┼─────────────┼────────┘
        ↓             ↓             ↓
   ┌────────┐    ┌─────────┐   ┌──────────┐
   │   S3   │    │ DynamoDB│   │    S3    │
   │  Lake  │    │  Tables │   │   DLQ    │
   └────────┘    └─────────┘   └──────────┘
```

## 🚀 Technologies Used

### Infrastructure
- **AWS EKS (Kubernetes 1.33)**: Container orchestration with Karpenter autoscaling
- **Terraform**: Infrastructure as Code for AWS resources
- **ArgoCD**: GitOps continuous delivery for Kubernetes
- **Karpenter**: Intelligent node autoscaling with spot instances

### Data Streaming
- **Apache Kafka 4.1.0 (Strimzi 0.48.0)**: Distributed event streaming (KRaft mode)
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

## 📁 Repository Structure

```
RealTimeCDC-Platform/
├── terraform-infra/              # Infrastructure Layer (Terraform)
│   ├── eks.tf                    # EKS cluster configuration
│   ├── rds.tf                    # PostgreSQL with CDC enabled
│   ├── s3.tf                     # S3 buckets (data lake, DLQ)
│   ├── iam.tf                    # IAM roles and policies
│   └── vpc.tf                    # Network configuration
│
├── terraform-apps/               # Application Layer (Terraform)
│   ├── argocd.tf                 # ArgoCD installation
│   ├── alb-controller.tf         # AWS Load Balancer Controller
│   ├── karpenter-nodepools.tf    # Karpenter node pools
│   ├── pod-identities.tf         # Pod Identity associations
│   ├── route53.tf                # DNS records for ingress
│   └── strimzi.tf                # Strimzi operator (managed via script)
│
├── argocd/                       # GitOps Configuration
│   ├── bootstrap/
│   │   └── root-app.yaml         # App of Apps pattern
│   ├── applications/             # Application definitions
│   │   ├── consumers.yaml        # Consumer microservices
│   │   ├── flink-jobs.yaml       # Flink stream processing
│   │   ├── ingress.yaml          # Ingress resources
│   │   └── kafka-cluster.yaml    # Kafka cluster
│   └── app-manifests/            # Kubernetes manifests
│       ├── consumers/            # Consumer deployments
│       ├── flink/                # Flink job/task managers
│       ├── ingress/              # ALB ingress configs
│       └── kafka/                # Kafka cluster configs
│
├── apps/                         # Application Code
│   ├── consumers/                # Python consumer services
│   │   ├── analytics-service/
│   │   ├── inventory-service/
│   │   └── search-indexer/
│   └── flink/                    # Flink jobs (Java/Scala)
│       ├── sales-aggregations/
│       ├── anomaly-detection/
│       ├── customer-segmentation/
│       └── inventory-optimizer/
│
├── scripts/                      # Operational Scripts
│   ├── install-kafka.sh          # Install Kafka operator + cluster
│   ├── install-debezium.sh       # Deploy Debezium connectors
│   ├── init-database.sh          # Initialize source database
│   ├── build-flink-jobs.sh       # Build and push Flink jobs
│   ├── submit-flink-job.sh       # Submit Flink job to cluster
│   ├── cleanup-all.sh            # Comprehensive cleanup
│   ├── cleanup-dynamodb.sh       # Clean DynamoDB tables
│   └── teardown.sh               # Full teardown
│
└── docs/                         # Additional Documentation
    └── *.md                      # Detailed guides
```

## 🏗️ Deployment Architecture

This platform uses a **hybrid approach** combining the best of Terraform, GitOps, and scripts:

### Infrastructure Layer (Terraform)
- **terraform-infra/**: Core AWS infrastructure (EKS, RDS, S3, VPC, IAM)
- Stable, rarely changes
- Deployed once during initial setup

### Application Layer (Terraform + GitOps)
- **terraform-apps/**: Kubernetes operators and controllers (ArgoCD, ALB Controller, Karpenter)
- **argocd/**: Application deployments via GitOps (consumers, Flink jobs, ingress)
- Auto-synced, drift detection enabled

### Kafka Infrastructure (Script-based)
- **scripts/install-kafka.sh**: Deploys Strimzi operator and Kafka cluster
- Helm-based for flexibility and compatibility
- Kafka resources (topics, users) managed by ArgoCD

## 🚀 Quick Start

### Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.5.0
4. **kubectl** >= 1.27
5. **Helm** >= 3.12
6. **Git** for version control

### Step 1: Deploy Infrastructure

```bash
# Clone the repository
git clone https://github.com/your-org/RealTimeCDC-Platform.git
cd RealTimeCDC-Platform

# Deploy core infrastructure (EKS, RDS, S3, VPC)
cd terraform-infra
terraform init
terraform plan
terraform apply

# Save outputs for later use
terraform output > ../infrastructure-outputs.txt
cd ..
```

### Step 2: Deploy Application Layer

```bash
# Deploy Kubernetes applications layer (ArgoCD, ALB Controller, Karpenter)
cd terraform-apps

# Update terraform.tfvars with your values
cat > terraform.tfvars <<EOF
environment     = "dev"
git_repo_url    = "https://github.com/YOUR-ORG/RealTimeCDC-Platform"
git_revision    = "main"
domain_name     = "your-domain.com"
certificate_arn = "arn:aws:acm:region:account:certificate/xxx"
EOF

terraform init
terraform plan
terraform apply

cd ..
```

### Step 3: Install Kafka Infrastructure

```bash
# Install Strimzi operator and Kafka cluster
./scripts/install-kafka.sh

# Verify Kafka cluster is ready
kubectl get kafka -n kafka
kubectl get pods -n kafka
```

### Step 4: Initialize Database

```bash
# Create sample e-commerce database and enable CDC
./scripts/init-database.sh
```

### Step 5: Deploy Debezium Connectors

```bash
# Deploy Debezium CDC connectors
./scripts/install-debezium.sh

# Verify connectors are running
kubectl get kafkaconnector -n kafka
```

### Step 6: Build and Deploy Flink Jobs

```bash
# Build Flink job Docker images
./scripts/build-flink-jobs.sh

# Submit Flink jobs to the cluster
./scripts/submit-flink-job.sh sales-aggregations
./scripts/submit-flink-job.sh anomaly-detection
./scripts/submit-flink-job.sh customer-segmentation
./scripts/submit-flink-job.sh inventory-optimizer
```

### Step 7: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -A

# Access ArgoCD UI
echo "ArgoCD URL: https://argocd.your-domain.com"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Access Flink Dashboard
echo "Flink URL: https://flink.your-domain.com"

# Check Kafka topics
kubectl exec -it cdc-platform-kafka-brokers-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

## 🔄 GitOps Workflow

The platform uses ArgoCD for automated deployments:

1. **Make changes** to application manifests in `argocd/app-manifests/`
2. **Commit and push** to Git
3. **ArgoCD automatically syncs** changes to the cluster
4. **Monitor** via ArgoCD UI at `https://argocd.your-domain.com`

### Manual Sync (if needed)

```bash
# Sync specific application
kubectl patch application consumer-apps -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"main"}}}'

# Sync all applications
kubectl patch application root-app -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"main"}}}'
```

## 🧹 Cleanup

### Option 1: Clean up applications (keep infrastructure)

```bash
# Comprehensive cleanup of apps and Kafka
./scripts/cleanup-all.sh
```

### Option 2: Full teardown (including infrastructure)

```bash
# Clean up everything including EKS cluster
./scripts/cleanup-all.sh

# Destroy application layer
cd terraform-apps
terraform destroy

# Destroy infrastructure layer
cd ../terraform-infra
terraform destroy
```

## 📊 Monitoring & Observability

### Access Dashboards

```bash
# ArgoCD - GitOps Dashboard
https://argocd.your-domain.com

# Flink - Stream Processing Dashboard
https://flink.your-domain.com

# Kafka - Topic and Consumer Metrics
kubectl port-forward -n kafka svc/cdc-platform-kafka-exporter 9308:9308
```

### Check Kafka Consumer Lag

```bash
kubectl exec -it cdc-platform-kafka-brokers-0 -n kafka -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --all-groups
```

### View Debezium Connector Status

```bash
kubectl get kafkaconnector -n kafka -o wide
```

## 🛠️ Troubleshooting

### Kafka Issues

```bash
# Check Strimzi operator logs
kubectl logs -n kafka deployment/strimzi-cluster-operator

# Check Kafka broker logs
kubectl logs -n kafka cdc-platform-kafka-brokers-0

# Verify Kafka cluster status
kubectl get kafka cdc-platform -n kafka -o yaml
```

### ArgoCD Sync Issues

```bash
# Check application status
kubectl get applications -n argocd

# View sync errors
kubectl describe application consumer-apps -n argocd

# Force refresh
kubectl patch application consumer-apps -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"}}}'
```

### Pod Identity Issues

```bash
# Verify pod identity associations
aws eks list-pod-identity-associations --cluster-name cdc-platform

# Check service account annotations
kubectl get sa -n kafka kafka-connect -o yaml
```

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔗 Additional Resources

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Strimzi Operator Guide](https://strimzi.io/docs/operators/latest/deploying.html)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Apache Flink Documentation](https://flink.apache.org/docs/stable/)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Karpenter Best Practices](https://karpenter.sh/docs/getting-started/)

---
