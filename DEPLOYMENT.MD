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

## Step 3: Initialize Database Schema

### 3.1 Automated Setup (Recommended)

The fastest way to initialize your database is using the automated script:

```bash
# Make script executable
chmod +x scripts/init-database.sh

# Run database initialization
./scripts/init-database.sh
```

**What this script does:**
1. Retrieves RDS connection details from Terraform outputs
2. Gets database password from AWS Secrets Manager
3. Creates Kubernetes Job to execute schema SQL
4. Verifies CDC configuration (REPLICA IDENTITY)
5. Displays summary of created tables and sample data
6. Cleans up temporary resources

**Output:**
```
=================================
CDC Platform - Database Initialization
=================================
📡 Getting RDS connection details...
✅ RDS Endpoint: cdc-platform-postgres.xxx.us-east-1.rds.amazonaws.com
✅ Database: ecommerce
✅ Username: dbadmin

🔐 Retrieving database password from Secrets Manager...
✅ Password retrieved successfully

🔧 Creating Kubernetes resources...
✅ Kubernetes resources created

🚀 Running database schema initialization...
⏳ Waiting for schema initialization to complete...

📋 Job output:
-----------------------------------
CREATE TABLE
CREATE TABLE
CREATE TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
INSERT 0 5
INSERT 0 3
INSERT 0 4
-----------------------------------

✅ Database initialization complete!

📊 Summary:
  - Tables created: products, orders, order_items
  - Sample data loaded: 5 products, 3 orders, 4 order items
  - CDC enabled: All tables have REPLICA IDENTITY FULL
  - Ready for Debezium connector
```

### 3.2 Manual Setup (Alternative)

If you prefer manual control or need to troubleshoot:

#### Get RDS Connection Details

```bash
cd terraform
terraform output rds_endpoint
# Output: cdc-platform-postgres.xxx.us-east-1.rds.amazonaws.com

terraform output rds_database_name
# Output: ecommerce

# Get password from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id cdc-platform-db-master-password \
  --query SecretString \
  --output text
```

#### Create Database Schema Using kubectl

```bash
cd ..  # Back to project root

# Create ConfigMap with SQL schema
kubectl create configmap db-schema \
  --from-file=schema.sql=scripts/schema.sql

# Create Secret with password (replace with actual password)
kubectl create secret generic db-credentials \
  --from-literal=password='<your-password>'

# Create Job to execute schema
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: db-schema-init
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: psql
        image: postgres:16
        command:
        - psql
        - -h
        - <rds-endpoint>
        - -U
        - dbadmin
        - -d
        - ecommerce
        - -f
        - /scripts/schema.sql
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        volumeMounts:
        - name: sql-scripts
          mountPath: /scripts
      volumes:
      - name: sql-scripts
        configMap:
          name: db-schema
EOF

# Wait and view logs
kubectl wait --for=condition=complete --timeout=120s job/db-schema-init
kubectl logs job/db-schema-init
```

#### Using psql Client Pod

If you need interactive access:

```bash
# Run interactive psql session
kubectl run psql-client --rm -it --restart=Never \
  --image=postgres:16 --namespace=default \
  --env="PGPASSWORD=<password>" \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce

# Once connected, run the schema
\i scripts/schema.sql

# Or copy-paste SQL commands directly
```

### 3.3 Verify Schema and CDC Configuration

After initialization, verify everything is set up correctly:

```bash
# Check tables exist
kubectl run psql-verify --rm -it --restart=Never \
  --image=postgres:16 --namespace=default \
  --env="PGPASSWORD=<password>" \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce -c "\dt"

# Verify REPLICA IDENTITY settings (required for CDC)
kubectl run psql-verify --rm -it --restart=Never \
  --image=postgres:16 --namespace=default \
  --env="PGPASSWORD=<password>" \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce -c "
SELECT c.relname AS table_name,
       CASE c.relreplident
           WHEN 'd' THEN 'default'
           WHEN 'n' THEN 'nothing'
           WHEN 'f' THEN 'full'
           WHEN 'i' THEN 'index'
       END AS replica_identity
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN ('products', 'orders', 'order_items')
ORDER BY c.relname;"

# Expected output:
# table_name  | replica_identity
# ------------|------------------
# order_items | full
# orders      | full
# products    | full

# Verify logical replication is enabled
kubectl run psql-verify --rm -it --restart=Never \
  --image=postgres:16 --namespace=default \
  --env="PGPASSWORD=<password>" \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce -c "SHOW wal_level;"

# Expected output: logical

# Check sample data
kubectl run psql-verify --rm -it --restart=Never \
  --image=postgres:16 --namespace=default \
  --env="PGPASSWORD=<password>" \
  -- psql -h <rds-endpoint> -U dbadmin -d ecommerce -c "
SELECT 'products' as table_name, COUNT(*) as row_count FROM products
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items;"

# Expected output:
# table_name  | row_count
# ------------|----------
# products    |         5
# orders      |         3
# order_items |         4
```

### 3.4 Schema Details

The schema includes:

**Products Table** (5 sample records):
- Laptop, Mouse, Keyboard, Monitor, Headphones
- With prices, descriptions, and stock quantities

**Orders Table** (3 sample records):
- Orders with different statuses (completed, pending, processing)
- Associated with customer IDs

**Order Items Table** (4 sample records):
- Line items linking orders to products
- With quantities and prices

**CDC Features:**
- ✅ REPLICA IDENTITY FULL on all tables
- ✅ Primary keys for row identification
- ✅ Foreign key relationships
- ✅ Indexes for performance
- ✅ Timestamps for audit tracking

## Step 4: Install EBS CSI Driver (Required for Kafka)

Before deploying Kafka, the EBS CSI driver must be installed to provision persistent volumes.

### 4.1 Verify Terraform Created IAM Role

The EBS CSI IAM role was created by Terraform in `terraform/iam.tf`:

```bash
cd terraform
terraform output ebs_csi_driver_role_arn
# Output: arn:aws:iam::ACCOUNT_ID:role/cdc-platform-ebs-csi-driver
```

### 4.2 Install EBS CSI Driver Addon

```bash
# Install the addon with the IAM role
aws eks create-addon \
  --cluster-name cdc-platform \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $(terraform output -raw ebs_csi_driver_role_arn) \
  --region us-east-1

# Wait for it to be active
aws eks wait addon-active \
  --cluster-name cdc-platform \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1
```

### 4.3 Verify EBS CSI Driver

```bash
# Check controller pods
kubectl get pods -n kube-system | grep ebs-csi-controller
# Expected: 2 pods with 6/6 Ready

# Check node pods
kubectl get pods -n kube-system | grep ebs-csi-node
# Expected: 1 pod per node with 3/3 Ready

# Verify CSI driver is registered
kubectl get csidriver
# Should show: ebs.csi.aws.com
```

## Step 5: Deploy Kafka Cluster

### 5.1 Automated Installation (Recommended)

```bash
cd ..  # Back to project root
chmod +x scripts/install-kafka.sh
./scripts/install-kafka.sh
```

**What this script does:**
1. Adds Strimzi Helm repository
2. Installs Strimzi operator v0.48.0 via Helm
3. Waits for operator to be ready
4. Deploys Kafka 4.1.0 cluster with KRaft mode (no ZooKeeper)
5. Creates CDC topics
6. Deploys Kafka Connect cluster
7. Verifies installation

### 5.2 Manual Installation

If you prefer manual control:

```bash
# Add Helm repo
helm repo add strimzi https://strimzi.io/charts/
helm repo update

# Install Strimzi operator
helm install strimzi-operator strimzi/strimzi-kafka-operator \
  --namespace kafka \
  --create-namespace \
  --values k8s/kafka/helm-values.yaml \
  --wait \
  --timeout 10m

# Create RBAC rolebindings (if needed)
kubectl create rolebinding strimzi-cluster-operator-entity-operator-delegation \
  --clusterrole=strimzi-entity-operator \
  --serviceaccount=kafka:strimzi-cluster-operator \
  -n kafka 2>/dev/null || true

kubectl create rolebinding strimzi-cluster-operator-watched \
  --clusterrole=strimzi-cluster-operator-watched \
  --serviceaccount=kafka:strimzi-cluster-operator \
  -n kafka 2>/dev/null || true

# Deploy Kafka cluster
kubectl apply -f k8s/kafka/kafka-cluster.yaml

# Wait for Kafka to be ready (may take 5-10 minutes)
kubectl wait --for=condition=ready --timeout=600s kafka/cdc-platform -n kafka

# Deploy topics
kubectl apply -f k8s/kafka/kafka-topics.yaml
```

### 5.3 Verify Kafka Cluster

```bash
# Check Kafka resource
kubectl get kafka -n kafka
# Expected: cdc-platform (no READY column means it's using KRaft)

# Check KafkaNodePool
kubectl get kafkanodepool -n kafka
# Expected: kafka-brokers with 3 replicas, controller+broker roles

# Check broker pods
kubectl get pods -n kafka
# Expected:
# - 3 broker pods: cdc-platform-kafka-brokers-0,1,2 (1/1 Ready)
# - entity-operator pod (2/2 Ready)
# - kafka-exporter pod (1/1 Ready)
# - strimzi-cluster-operator pod (1/1 Ready)

# Check PVCs
kubectl get pvc -n kafka
# Expected: 3 PVCs, all Bound with 20Gi gp2 volumes

# Check topics
kubectl get kafkatopic -n kafka
# Expected: 10 topics including:
# - dbserver1.public.products
# - dbserver1.public.orders
# - dbserver1.public.order-items
# - connect-configs, connect-offsets, connect-status
# - cdc-dlq
```

### 5.4 Test Kafka Connection

```bash
# Exec into a broker pod
kubectl exec -it cdc-platform-kafka-brokers-0 -n kafka -- bash

# List topics
bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# Produce test message
echo "test message" | bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic dbserver1.public.products

# Consume messages
bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic dbserver1.public.products \
  --from-beginning
```

### 5.5 Kafka Architecture Notes

**KRaft Mode (Kafka 4.1.0):**
- No ZooKeeper required
- Brokers act as both controllers and data brokers
- Faster metadata operations
- Simplified architecture

**Key Differences from Older Versions:**
- Uses `KafkaNodePool` resources instead of `spec.kafka.replicas`
- Requires `metadataVersion: 4.1-IV0` annotation
- Storage class must be `gp2` (not `gp3`) in this environment

For detailed troubleshooting, see `k8s/kafka/README.md`.

### 5.6 Deploy Kafka Connect

**IMPORTANT**: If you encountered issues during the initial Kafka deployment, restart the Strimzi operator before deploying Kafka Connect:

```bash
# If operator was stuck in a previous reconciliation, restart it
kubectl delete pod -n kafka -l name=strimzi-cluster-operator
kubectl wait --for=condition=ready --timeout=60s pod -l name=strimzi-cluster-operator -n kafka
```

Deploy Kafka Connect cluster:

```bash
# Deploy Kafka Connect
kubectl apply -f k8s/kafka/kafka-connect.yaml

# Wait for Connect to be ready
kubectl wait --for=condition=ready --timeout=120s pod -l strimzi.io/cluster=cdc-platform-connect -n kafka
```

### 5.7 Verify Kafka Connect

```bash
# Check Kafka Connect resource
kubectl get kafkaconnect -n kafka
# Expected: cdc-platform-connect with READY=True

# Check Connect pod
kubectl get pods -n kafka -l strimzi.io/cluster=cdc-platform-connect
# Expected: cdc-platform-connect-connect-0 (1/1 Ready)

# Check Connect services
kubectl get svc -n kafka | grep connect
# Expected:
# - cdc-platform-connect-connect-api (ClusterIP on 8083)
# - cdc-platform-connect-connect (headless)

# Verify Connect REST API is working
kubectl exec -n kafka cdc-platform-connect-connect-0 -- curl -s localhost:8083/ | head -10
# Should return JSON with version info

# Check available connector plugins
kubectl exec -n kafka cdc-platform-connect-connect-0 -- curl -s localhost:8083/connector-plugins
# Should show available connectors (MirrorSource, etc.)
```

### 5.8 Kafka Connect - Current Limitations

The current Kafka Connect deployment uses the base Apache Kafka Connect 4.1.0 image, which **does not include the Debezium PostgreSQL connector**.

**Next Steps for CDC:**
To enable CDC from PostgreSQL, you'll need to add the Debezium connector. Options include:

1. **Build Custom Image** (Recommended for production):
   ```bash
   # Create Dockerfile
   FROM quay.io/strimzi/kafka:0.48.0-kafka-4.1.0
   USER root
   RUN mkdir -p /opt/kafka/plugins/debezium
   RUN curl -L https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.7.0.Final/debezium-connector-postgres-2.7.0.Final-plugin.tar.gz \
       | tar xz -C /opt/kafka/plugins/debezium
   USER 1001

   # Build and push
   docker build -t <your-registry>/kafka-connect-debezium:4.1.0 .
   docker push <your-registry>/kafka-connect-debezium:4.1.0

   # Update kafka-connect.yaml to use your image
   # Add under spec:
   #   image: <your-registry>/kafka-connect-debezium:4.1.0
   ```

2. **Use Strimzi Build** (For development, requires image registry):
   Add to `kafka-connect.yaml` under `spec`:
   ```yaml
   build:
     output:
       type: docker
       image: <your-registry>/kafka-connect-build:latest
     plugins:
       - name: debezium-postgres-connector
         artifacts:
           - type: tgz
             url: https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.7.0.Final/debezium-connector-postgres-2.7.0.Final-plugin.tar.gz
   ```

3. **Manual Installation** (Quick test, not persistent):
   ```bash
   kubectl exec -n kafka cdc-platform-connect-connect-0 -- bash -c "
   mkdir -p /opt/kafka/plugins/debezium &&
   cd /opt/kafka/plugins/debezium &&
   curl -L https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.7.0.Final/debezium-connector-postgres-2.7.0.Final-plugin.tar.gz | tar xz
   "

   # Restart Connect pod to load plugin
   kubectl delete pod -n kafka cdc-platform-connect-connect-0
   ```

After adding the Debezium connector, verify it's available:
```bash
kubectl exec -n kafka cdc-platform-connect-connect-0 -- \
  curl -s localhost:8083/connector-plugins | grep -i debezium
```

## Step 6: Install ArgoCD

### 4.1 Run Setup Script

```bash
chmod +x scripts/setup-argocd.sh
./scripts/setup-argocd.sh
```

### 4.2 Access ArgoCD UI

```bash
# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser to https://localhost:8080
# Login: admin / <password from script output>
```

### 4.3 Install ArgoCD CLI (Optional but Recommended)

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login via CLI
argocd login localhost:8080 --username admin --password <password> --insecure
```

## Step 5: Configure Git Repository

### 5.1 Update Repository URLs

Update the following files with your GitHub repository URL:

```bash
# Find and replace YOUR_ORG with your GitHub organization/username
grep -r "YOUR_ORG" argocd/
```

Files to update:
- `argocd/bootstrap/root-app.yaml`
- `argocd/projects/cdc-platform.yaml`
- `argocd/apps/*.yaml`

### 5.2 Push to Your Repository

```bash
git add .
git commit -m "Configure ArgoCD for CDC platform"
git push origin main
```

## Step 6: Deploy Platform with ArgoCD

### 6.1 Create ArgoCD Project

```bash
kubectl apply -f argocd/projects/cdc-platform.yaml
```

### 6.2 Deploy Root Application (App of Apps)

```bash
kubectl apply -f argocd/bootstrap/root-app.yaml
```

This triggers ArgoCD to deploy everything in order:
1. **Wave 0**: External Secrets Operator
2. **Wave 1**: Kafka Cluster, Prometheus Operator
3. **Wave 2**: Schema Registry, Flink Operator
4. **Wave 3**: Debezium Connectors
5. **Wave 4**: CDC Consumers, Flink Jobs

### 6.3 Watch Deployment Progress

```bash
# Via CLI
argocd app list
argocd app get cdc-platform-root

# Via UI
# Open https://localhost:8080
# Watch the applications sync in real-time
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

## Step 8: Test CDC Data Flow

### 8.1 Insert Test Data

Connect to the database and test the CDC flow:

```bash
# Get RDS endpoint
cd terraform
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
cd ..

# Get password
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id cdc-platform-db-master-password \
  --query SecretString \
  --output text)

# Run psql client
kubectl run psql-test --rm -it --restart=Never \
  --image=postgres:16 --namespace=default \
  --env="PGPASSWORD=${DB_PASSWORD}" \
  -- psql -h $RDS_ENDPOINT -U dbadmin -d ecommerce
```

Once connected, run these test operations:

```sql
-- Test INSERT
INSERT INTO products (name, description, price, stock_quantity)
VALUES ('Test Product', 'CDC Test', 99.99, 100);

-- Test UPDATE
UPDATE products SET price = 89.99, stock_quantity = 95
WHERE name = 'Test Product';

-- Test DELETE
DELETE FROM products WHERE name = 'Test Product';

-- Query current data
SELECT * FROM products ORDER BY id;
```

### 8.2 Verify Changes in Kafka

Check that the changes were captured and sent to Kafka:

```bash
# Exec into Kafka broker
kubectl exec -it cdc-platform-kafka-0 -n kafka -- bash

# Consume from products topic
bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic dbserver1.public.products \
  --from-beginning

# You should see JSON events for INSERT, UPDATE, and DELETE operations
```

## Step 9: Access Monitoring

### 9.1 Grafana

```bash
# Port forward Grafana
kubectl port-forward svc/prometheus-operator-grafana -n monitoring 3000:80

# Open http://localhost:3000
# Login: admin / admin (change in production!)
```

### 9.2 Prometheus

```bash
# Port forward Prometheus
kubectl port-forward svc/prometheus-operator-kube-prom-prometheus -n monitoring 9090:9090

# Open http://localhost:9090
```

## Step 10: Deploy Consumer Applications

### 10.1 Build and Push Docker Images

```bash
cd apps/python/inventory-service

# Build
docker build -t <your-registry>/inventory-service:v1.0.0 .

# Push
docker push <your-registry>/inventory-service:v1.0.0
```

### 10.2 Update Kubernetes Manifests

```bash
cd ../../../k8s/consumers/inventory-service

# Update image in deployment.yaml
# Then commit and push
git add deployment.yaml
git commit -m "Deploy inventory-service v1.0.0"
git push
```

### 10.3 Watch ArgoCD Auto-Deploy

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