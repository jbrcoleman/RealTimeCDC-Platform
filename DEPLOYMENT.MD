# RealTimeCDC-Platform Deployment Guide

## Overview

This guide walks through deploying the entire CDC platform using Terraform for infrastructure and ArgoCD for Kubernetes resources.

## Architecture

```
Terraform (AWS)              ArgoCD (Kubernetes)
├── EKS Cluster       →      ├── Kafka Cluster
├── RDS PostgreSQL    →      ├── Debezium Connectors
├── S3 Buckets        →      ├── CDC Consumers
└── IAM Roles         →      ├── Flink Jobs
                             └── Monitoring Stack
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5
- kubectl >= 1.28
- Helm >= 3.12
- Git
- Docker (for building consumer images)

## Step 1: Deploy Infrastructure with Terraform

### 1.1 Initialize Terraform

```bash
cd terraform
terraform init
```

### 1.2 Review and Apply

```bash
# Review the plan
terraform plan

# Apply infrastructure
terraform apply
```

This creates:
- ✅ VPC with public/private subnets
- ✅ EKS cluster with Karpenter
- ✅ RDS PostgreSQL with logical replication enabled
- ✅ S3 buckets (data lake, DLQ, Kafka Connect storage)
- ✅ IAM roles for service accounts (IRSA)

### 1.3 Configure kubectl

```bash
# Get the kubeconfig command from terraform output
terraform output configure_kubectl

# Run it (example):
aws eks --region us-east-1 update-kubeconfig --name cdc-platform
```

### 1.4 Verify Cluster Access

```bash
kubectl get nodes
kubectl get pods -A
```

## Step 2: Apply Kubernetes Service Accounts

```bash
cd ..  # Back to project root

# Make script executable
chmod +x scripts/apply-service-accounts.sh

# Apply service accounts with IAM role annotations
./scripts/apply-service-accounts.sh
```

This creates:
- ✅ All namespaces
- ✅ Service accounts with IRSA annotations
- ✅ Proper labels for organization

## Step 3: Install ArgoCD

### 3.1 Run Setup Script

```bash
chmod +x scripts/setup-argocd.sh
./scripts/setup-argocd.sh
```

### 3.2 Access ArgoCD UI

```bash
# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser to https://localhost:8080
# Login: admin / <password from script output>
```

### 3.3 Install ArgoCD CLI (Optional but Recommended)

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login via CLI
argocd login localhost:8080 --username admin --password <password> --insecure
```

## Step 4: Configure Git Repository

### 4.1 Update Repository URLs

Update the following files with your GitHub repository URL:

```bash
# Find and replace YOUR_ORG with your GitHub organization/username
grep -r "YOUR_ORG" argocd/
```

Files to update:
- `argocd/bootstrap/root-app.yaml`
- `argocd/projects/cdc-platform.yaml`
- `argocd/apps/*.yaml`

### 4.2 Push to Your Repository

```bash
git add .
git commit -m "Configure ArgoCD for CDC platform"
git push origin main
```

## Step 5: Deploy Platform with ArgoCD

### 5.1 Create ArgoCD Project

```bash
kubectl apply -f argocd/projects/cdc-platform.yaml
```

### 5.2 Deploy Root Application (App of Apps)

```bash
kubectl apply -f argocd/bootstrap/root-app.yaml
```

This triggers ArgoCD to deploy everything in order:
1. **Wave 0**: External Secrets Operator
2. **Wave 1**: Kafka Cluster, Prometheus Operator
3. **Wave 2**: Schema Registry, Flink Operator
4. **Wave 3**: Debezium Connectors
5. **Wave 4**: CDC Consumers, Flink Jobs

### 5.3 Watch Deployment Progress

```bash
# Via CLI
argocd app list
argocd app get cdc-platform-root

# Via UI
# Open https://localhost:8080
# Watch the applications sync in real-time
```

## Step 6: Initialize Database Schema

### 6.1 Get RDS Connection Details

```bash
cd terraform
terraform output rds_endpoint
terraform output rds_database_name

# Get password from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id cdc-platform-db-master-password \
  --query SecretString \
  --output text
```

### 6.2 Connect and Create Schema

```bash
# Port forward to a pod that can access RDS
kubectl run psql-client --rm -it --restart=Never \
  --image=postgres:16 \
  --namespace=kafka \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce

# Or connect directly if you have psql installed
psql -h <rds-endpoint> -U dbadmin -d ecommerce
```

### 6.3 Create E-commerce Tables

```sql
-- Create products table
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create orders table
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create order_items table
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Set replica identity to FULL for CDC (required for Debezium)
ALTER TABLE products REPLICA IDENTITY FULL;
ALTER TABLE orders REPLICA IDENTITY FULL;
ALTER TABLE order_items REPLICA IDENTITY FULL;

-- Insert sample data
INSERT INTO products (name, description, price, stock_quantity) VALUES
    ('Laptop', 'High-performance laptop', 1299.99, 50),
    ('Mouse', 'Wireless mouse', 29.99, 200),
    ('Keyboard', 'Mechanical keyboard', 89.99, 150);
```

## Step 7: Verify CDC Pipeline

### 7.1 Check Kafka Cluster

```bash
kubectl get kafka -n kafka
kubectl get kafkatopic -n kafka
```

### 7.2 Check Debezium Connector

```bash
kubectl get kafkaconnector -n kafka
kubectl describe kafkaconnector postgres-connector -n kafka
```

### 7.3 Verify Topics Created

```bash
# Exec into Kafka pod
kubectl exec -it cdc-platform-kafka-0 -n kafka -- bash

# List topics
bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# Should see topics like:
# - dbserver1.public.products
# - dbserver1.public.orders
# - dbserver1.public.order_items
```

### 7.4 Test CDC Flow

```sql
-- In psql, update a product
UPDATE products SET price = 1199.99 WHERE id = 1;

-- Insert a new order
INSERT INTO orders (customer_id, total_amount, status) 
VALUES (123, 1229.98, 'pending');
```

```bash
# Check Kafka topic for changes
kubectl exec -it cdc-platform-kafka-0 -n kafka -- bash
bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic dbserver1.public.products \
  --from-beginning
```

## Step 8: Access Monitoring

### 8.1 Grafana

```bash
# Port forward Grafana
kubectl port-forward svc/prometheus-operator-grafana -n monitoring 3000:80

# Open http://localhost:3000
# Login: admin / admin (change in production!)
```

### 8.2 Prometheus

```bash
# Port forward Prometheus
kubectl port-forward svc/prometheus-operator-kube-prom-prometheus -n monitoring 9090:9090

# Open http://localhost:9090
```

## Step 9: Deploy Consumer Applications

### 9.1 Build and Push Docker Images

```bash
cd apps/python/inventory-service

# Build
docker build -t <your-registry>/inventory-service:v1.0.0 .

# Push
docker push <your-registry>/inventory-service:v1.0.0
```

### 9.2 Update Kubernetes Manifests

```bash
cd ../../../k8s/consumers/inventory-service

# Update image in deployment.yaml
# Then commit and push
git add deployment.yaml
git commit -m "Deploy inventory-service v1.0.0"
git push
```

### 9.3 Watch ArgoCD Auto-Deploy

ArgoCD will automatically:
1. Detect the Git change
2. Sync the new image
3. Deploy updated pods
4. Verify health

## Troubleshooting

### ArgoCD Application Not Syncing

```bash
# Check application status
argocd app get <app-name>

# View sync errors
argocd app logs <app-name>

# Manual sync
argocd app sync <app-name>
```

### Debezium Connector Issues

```bash
# Check connector status
kubectl describe kafkaconnector postgres-connector -n kafka

# Check connector logs
kubectl logs -l strimzi.io/cluster=kafka-connect -n kafka
```

### RDS Connection Issues

```bash
# Verify security group allows EKS node connections
# Check RDS security group in AWS Console

# Test connection from a pod
kubectl run psql-test --rm -it --restart=Never \
  --image=postgres:16 \
  --namespace=kafka \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce
```

### S3 Access Issues

```bash
# Verify IRSA is working
kubectl describe sa kafka-connect -n kafka

# Check if pod has credentials
kubectl exec -it <kafka-connect-pod> -n kafka -- env | grep AWS
```

## Clean Up

### Destroy Everything

```bash
# Delete ArgoCD applications first
argocd app delete cdc-platform-root --cascade

# Or via kubectl
kubectl delete -f argocd/bootstrap/root-app.yaml

# Wait for all resources to be deleted
kubectl get all -A

# Destroy AWS infrastructure
cd terraform
terraform destroy
```

## Next Steps

1. **Set up CI/CD pipelines** - GitHub Actions for automated builds
2. **Configure alerting** - Set up Prometheus alerts and Slack notifications
3. **Implement data retention** - Configure S3 lifecycle policies
4. **Add more consumers** - Build additional microservices
5. **Production hardening** - Review security, enable backups, set up DR

## Support

- Review ArgoCD logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server`
- Check Terraform state: `terraform show`
- View all resources: `kubectl get all -A`

Happy CDC streaming! 🚀