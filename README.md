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

### Monitoring & Observability
- **Prometheus**: Metrics collection and time-series database
- **Grafana**: Visualization dashboards with pre-configured templates
- **Alertmanager**: Alert routing and notification management
- **CloudWatch Exporter**: AWS service metrics integration
- **Prometheus Operator**: Automated Prometheus instance management

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
│   ├── monitoring.tf             # Prometheus & Grafana stack
│   ├── pod-identities.tf         # Pod Identity associations
│   ├── route53.tf                # DNS records (ArgoCD, Flink, Grafana, Prometheus)
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
├── k8s/                          # Kubernetes Configuration
│   ├── monitoring/               # Monitoring stack values
│   │   ├── prometheus-stack-values.yaml
│   │   └── cloudwatch-exporter-values.yaml
│   └── [other configs...]
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
- **terraform-apps/**: Kubernetes operators and controllers
  - ArgoCD for GitOps
  - AWS Load Balancer Controller (shared ALB for all ingresses)
  - Karpenter for node autoscaling
  - Prometheus & Grafana monitoring stack
  - CloudWatch Exporter for AWS metrics
- **argocd/**: Application deployments via GitOps (consumers, Flink jobs, ingress)
- Auto-synced, drift detection enabled
- All web UIs accessible via shared Application Load Balancer with SSL/TLS

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

# Authenticate with AWS ECR Public (required for Karpenter chart)
aws ecr-public get-login-password --region us-east-1 | \
  helm registry login --username AWS --password-stdin public.ecr.aws

terraform apply

# Save outputs for later use
terraform output > ../infrastructure-outputs.txt
cd ..

# Login to EKS Cluster
aws eks --region us-east-1 update-kubeconfig --name cdc-platform
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

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Access Dashboards
echo "
🎯 Platform Access URLs:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Grafana (Monitoring):  https://grafana.your-domain.com
   Username: admin
   Password: Prometheus1234

📈 Prometheus (Metrics):  https://prometheus.your-domain.com
   (For debugging queries and targets)

🚀 ArgoCD (GitOps):       https://argocd.your-domain.com
   Username: admin
   Password: [Use command above]

🌊 Flink (Stream Jobs):   https://flink.your-domain.com
   (Job Manager Dashboard)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"

# Verify Kafka topics are created
kubectl exec -it cdc-platform-kafka-brokers-0 -n kafka -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# Check consumer services are processing messages
kubectl logs -n consumers deployment/analytics-service --tail=20
kubectl logs -n consumers deployment/inventory-service --tail=20
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

The platform includes comprehensive monitoring and observability with the **kube-prometheus-stack**, providing metrics collection, visualization, and alerting for all components.

### Monitoring Stack

- **Prometheus**: Metrics collection and time-series database
- **Grafana**: Visualization dashboards and analytics
- **Alertmanager**: Alert routing and notifications
- **Node Exporter**: Node-level metrics
- **Kube State Metrics**: Kubernetes cluster state metrics
- **CloudWatch Exporter**: AWS service metrics (RDS, DynamoDB, S3, EBS)

### Access Dashboards

```bash
# Grafana - Main Visualization Dashboard
https://grafana.your-domain.com
Username: admin
Password: Prometheus1234

# Prometheus - Metrics Query Interface (for debugging)
https://prometheus.your-domain.com

# ArgoCD - GitOps Dashboard
https://argocd.your-domain.com

# Flink - Stream Processing Dashboard
https://flink.your-domain.com
```

### Pre-configured Dashboards

Grafana includes pre-installed dashboards for:

1. **Kubernetes Cluster Overview** (ID: 7249)
   - Cluster resource utilization
   - Node metrics and health
   - Pod status and distribution

2. **Node Exporter Dashboard** (ID: 1860)
   - CPU, memory, disk, network metrics
   - System-level performance monitoring

3. **Kafka Cluster Monitoring** (ID: 7589, 13770)
   - Broker health and performance
   - Topic throughput and lag
   - Consumer group metrics
   - Partition distribution

4. **Apache Flink Dashboard** (ID: 10369)
   - Job status and performance
   - Task manager metrics
   - Checkpointing and state
   - Backpressure monitoring

### Metrics Collection

**Application Metrics:**
- Kafka brokers, topics, consumer groups
- Flink jobs, task managers, checkpoints
- Debezium connector status
- Consumer service metrics

**Infrastructure Metrics:**
- EKS cluster and node metrics
- Pod resource usage (CPU, memory)
- Network traffic and latency
- Storage utilization

**AWS Service Metrics (via CloudWatch Exporter):**
- **RDS**: Database connections, CPU, storage, latency, throughput
- **DynamoDB**: Read/write capacity, errors, request latency
- **S3**: Bucket size, object count
- **EBS**: Volume I/O operations and throughput

### Monitoring Commands

**Check Kafka Consumer Lag:**
```bash
kubectl exec -it cdc-platform-kafka-brokers-0 -n kafka -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --all-groups
```

**View Debezium Connector Status:**
```bash
kubectl get kafkaconnector -n kafka -o wide
```

**Check Prometheus Targets:**
```bash
# Access Prometheus UI → Status → Targets
# Or via kubectl port-forward:
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Then visit http://localhost:9090/targets
```

**View Active Alerts:**
```bash
# Access Alertmanager UI:
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Then visit http://localhost:9093
```

### Custom Metrics

Consumer services expose custom metrics at `/metrics` endpoint:
- Message processing rate
- Error counts and types
- Processing latency
- DynamoDB/S3 operation metrics

Access via port-forward:
```bash
kubectl port-forward -n consumers svc/analytics-service 8080:8080
curl http://localhost:8080/metrics
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
