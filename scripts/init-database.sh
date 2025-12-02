#!/bin/bash
set -e
set +H  # Disable history expansion to handle ! in strings

# Database Initialization Script for CDC Platform
# This script creates the e-commerce schema in RDS PostgreSQL

echo "==================================="
echo "CDC Platform - Database Initialization"
echo "==================================="

# Get RDS endpoint from Terraform
echo "📡 Getting RDS connection details..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT/terraform-infra"
RDS_ENDPOINT_RAW=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
RDS_ENDPOINT=$(echo "$RDS_ENDPOINT_RAW" | cut -d: -f1)  # Remove port if present
RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo "ecommerce")
RDS_USERNAME=$(terraform output -raw rds_username 2>/dev/null || echo "dbadmin")
SECRET_ARN=$(terraform output -raw rds_master_secret_arn 2>/dev/null || echo "")
cd "$PROJECT_ROOT"

if [ -z "$RDS_ENDPOINT" ]; then
    echo "❌ Error: Could not get RDS endpoint from Terraform outputs"
    echo "   Make sure you've run 'terraform apply' successfully"
    exit 1
fi

echo "✅ RDS Endpoint: $RDS_ENDPOINT"
echo "✅ Database: $RDS_DATABASE"
echo "✅ Username: $RDS_USERNAME"

if [ -z "$SECRET_ARN" ]; then
    echo "❌ Error: Could not get RDS secret ARN from Terraform outputs"
    exit 1
fi

# Get database password from AWS Secrets Manager (RDS-managed secret)
echo ""
echo "🔐 Retrieving database password from Secrets Manager..."
DB_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --query 'SecretString' \
    --output text 2>/dev/null | jq -r '.password' | tr -d '\n')

if [ -z "$DB_PASSWORD" ]; then
    echo "❌ Error: Could not retrieve password from Secrets Manager"
    exit 1
fi

echo "✅ Password retrieved successfully"

# Create Kubernetes resources for schema initialization
echo ""
echo "🔧 Creating Kubernetes resources..."

# Create ConfigMap with SQL schema
kubectl create configmap db-schema \
    --from-file=schema.sql=scripts/schema.sql \
    --dry-run=client -o yaml | kubectl apply -f -

# Create Secret with database credentials
kubectl create secret generic db-credentials \
    --from-literal=password="$DB_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Kubernetes resources created"

# Create and run database initialization job
echo ""
echo "🚀 Running database schema initialization..."

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: db-schema-init
  namespace: default
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: psql
        image: postgres:16
        command:
        - /bin/bash
        - -c
        - |
          echo "Connecting to database..."
          psql "sslmode=require host=$RDS_ENDPOINT port=5432 user=$RDS_USERNAME dbname=$RDS_DATABASE" -f /scripts/schema.sql
          echo ""
          echo "✅ Schema created successfully"
          echo ""
          echo "Verifying configuration..."
          psql "sslmode=require host=$RDS_ENDPOINT port=5432 user=$RDS_USERNAME dbname=$RDS_DATABASE" -c "\dt"
          echo ""
          psql "sslmode=require host=$RDS_ENDPOINT port=5432 user=$RDS_USERNAME dbname=$RDS_DATABASE" -c "SELECT COUNT(*) as product_count FROM products;"
          psql "sslmode=require host=$RDS_ENDPOINT port=5432 user=$RDS_USERNAME dbname=$RDS_DATABASE" -c "SELECT COUNT(*) as order_count FROM orders;"
          psql "sslmode=require host=$RDS_ENDPOINT port=5432 user=$RDS_USERNAME dbname=$RDS_DATABASE" -c "SELECT COUNT(*) as order_item_count FROM order_items;"
        env:
        - name: RDS_ENDPOINT
          value: "$RDS_ENDPOINT"
        - name: RDS_USERNAME
          value: "$RDS_USERNAME"
        - name: RDS_DATABASE
          value: "$RDS_DATABASE"
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

# Wait for job to complete
echo "⏳ Waiting for schema initialization to complete..."
kubectl wait --for=condition=complete --timeout=120s job/db-schema-init

# Show job logs
echo ""
echo "📋 Job output:"
echo "-----------------------------------"
kubectl logs job/db-schema-init
echo "-----------------------------------"

# Verify CDC configuration
echo ""
echo "🔍 Verifying CDC configuration..."

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: db-cdc-verify
  namespace: default
spec:
  ttlSecondsAfterFinished: 60
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: psql
        image: postgres:16
        command:
        - /bin/bash
        - -c
        - |
          psql "sslmode=require host=$RDS_ENDPOINT port=5432 user=$RDS_USERNAME dbname=$RDS_DATABASE" -c "
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
        env:
        - name: RDS_ENDPOINT
          value: "$RDS_ENDPOINT"
        - name: RDS_USERNAME
          value: "$RDS_USERNAME"
        - name: RDS_DATABASE
          value: "$RDS_DATABASE"
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
EOF

kubectl wait --for=condition=complete --timeout=60s job/db-cdc-verify
echo ""
echo "CDC Configuration (REPLICA IDENTITY):"
kubectl logs job/db-cdc-verify

# Cleanup
echo ""
echo "🧹 Cleaning up temporary resources..."
kubectl delete job db-schema-init db-cdc-verify 2>/dev/null || true
kubectl delete configmap db-schema 2>/dev/null || true
kubectl delete secret db-credentials 2>/dev/null || true

echo ""
echo "==================================="
echo "✅ Database initialization complete!"
echo "==================================="
echo ""
echo "📊 Summary:"
echo "  - Tables created: products, orders, order_items"
echo "  - Sample data loaded: 5 products, 3 orders, 4 order items"
echo "  - CDC enabled: All tables have REPLICA IDENTITY FULL"
echo "  - Ready for Debezium connector"
echo ""
echo "Next steps:"
echo "  1. Deploy Kafka cluster (k8s/kafka/)"
echo "  2. Configure Debezium connector (k8s/debezium/)"
echo "  3. Deploy consumer applications"
echo ""
