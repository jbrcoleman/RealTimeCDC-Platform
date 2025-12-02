#!/bin/bash
set -e

# Debezium Connector Installation Script
# This script deploys the Debezium PostgreSQL CDC connector to Kafka Connect

echo "=========================================="
echo "CDC Platform - Debezium Connector Installation"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check prerequisites
echo ""
echo "📋 Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi
print_status "kubectl is installed"

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi
print_status "Connected to Kubernetes cluster"

# Check if Kafka namespace exists
if ! kubectl get namespace kafka &> /dev/null; then
    print_error "Kafka namespace not found. Please run install-kafka.sh first."
    exit 1
fi
print_status "Kafka namespace exists"

# Check if Kafka Connect is ready
echo ""
echo "🔍 Checking Kafka Connect status..."
if ! kubectl get kafkaconnect cdc-platform-connect -n kafka &> /dev/null; then
    print_error "Kafka Connect cluster not found. Please run install-kafka.sh first."
    exit 1
fi

if ! kubectl get kafkaconnect cdc-platform-connect -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
    print_error "Kafka Connect is not ready. Please wait for Kafka Connect to be ready."
    echo "Check status with: kubectl get kafkaconnect -n kafka"
    exit 1
fi
print_status "Kafka Connect is ready"

# Get RDS connection details from Terraform
echo ""
echo "📡 Getting RDS connection details..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT/terraform-infra"

RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo "ecommerce")
RDS_USERNAME=$(terraform output -raw rds_username 2>/dev/null || echo "dbadmin")
SECRET_ARN=$(terraform output -raw rds_master_secret_arn 2>/dev/null || echo "")

cd "$PROJECT_ROOT"

if [ -z "$RDS_ENDPOINT" ]; then
    print_error "Could not get RDS endpoint from Terraform outputs"
    echo "   Make sure you've run 'terraform apply' successfully"
    exit 1
fi

echo "   Endpoint: $RDS_ENDPOINT"
echo "   Database: $RDS_DATABASE"
echo "   Username: $RDS_USERNAME"
print_status "RDS connection details retrieved"

# Retrieve database password from Secrets Manager
echo ""
echo "🔐 Retrieving database password from Secrets Manager..."

if [ -z "$SECRET_ARN" ]; then
    print_error "Could not get RDS secret ARN from Terraform outputs"
    exit 1
fi

# Extract secret name from ARN (handle the ! character)
SECRET_NAME=$(echo "$SECRET_ARN" | sed 's/.*secret:\(.*\)-.*/\1/')

# Get password from secret (remove trailing newline to avoid SCRAM auth errors)
DB_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query 'SecretString' \
    --output text 2>/dev/null | jq -r '.password' | tr -d '\n')

if [ -z "$DB_PASSWORD" ]; then
    print_error "Could not retrieve password from Secrets Manager"
    exit 1
fi

print_status "Password retrieved successfully"

# Create Kubernetes secret with database credentials
echo ""
echo "🔧 Creating database credentials secret..."
kubectl create secret generic db-credentials \
    --from-literal=password="$DB_PASSWORD" \
    --namespace kafka \
    --dry-run=client -o yaml | kubectl apply -f -

print_status "Secret created in kafka namespace"

# Create ConfigMap with RDS endpoint for environment variable substitution
echo ""
echo "🔧 Creating RDS endpoint ConfigMap..."
kubectl create configmap rds-config \
    --from-literal=RDS_ENDPOINT="$RDS_ENDPOINT" \
    --namespace kafka \
    --dry-run=client -o yaml | kubectl apply -f -

print_status "ConfigMap created"

# Update KafkaConnect to include ConfigMap as environment variable
echo ""
echo "🔧 Checking KafkaConnect configuration..."

# Check if externalConfiguration already exists
if kubectl get kafkaconnect cdc-platform-connect -n kafka -o jsonpath='{.spec.externalConfiguration}' | grep -q "env"; then
    print_warning "KafkaConnect already has environment configuration"
else
    print_warning "You may need to manually add RDS_ENDPOINT environment variable to KafkaConnect"
    echo "   See: k8s/kafka/kafka-connect.yaml"
fi

# Deploy Debezium connector with environment variable substitution
echo ""
echo "🚀 Deploying Debezium PostgreSQL connector..."

# Replace environment variable in connector config before applying
sed "s/\${env:RDS_ENDPOINT}/$RDS_ENDPOINT/g" k8s/debezium/postgres-connector.yaml | kubectl apply -f -

print_status "Debezium connector deployment initiated"

# Wait for connector to be ready
echo ""
echo "⏳ Waiting for Debezium connector to be ready (this may take 1-2 minutes)..."
echo "   - Validating connector configuration..."
echo "   - Testing database connection..."
echo "   - Creating replication slot and publication..."
echo "   - Performing initial snapshot..."

# Wait for KafkaConnector resource to be created
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if kubectl get kafkaconnector postgres-connector -n kafka &> /dev/null; then
        print_status "Connector resource created"
        break
    fi
    attempt=$((attempt + 1))
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    print_error "Timeout waiting for connector resource to be created"
    exit 1
fi

# Wait for connector to be ready
kubectl wait --for=condition=ready --timeout=300s \
    kafkaconnector/postgres-connector -n kafka 2>/dev/null || {
    print_warning "Connector is still initializing. Check status with:"
    echo "  kubectl get kafkaconnector -n kafka"
    echo "  kubectl logs -n kafka -l strimzi.io/cluster=cdc-platform-connect"
}

# Check if connector is actually ready
if kubectl get kafkaconnector postgres-connector -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
    print_status "Debezium connector is ready!"

    # Show connector info
    echo ""
    echo "📊 Connector Information:"
    kubectl get kafkaconnector postgres-connector -n kafka
    
    # Show connector status
    echo ""
    echo "🔍 Connector Status:"
    kubectl get kafkaconnector postgres-connector -n kafka -o jsonpath='{.status.connectorStatus}' | jq .
    
    # Show created topics
    echo ""
    echo "📝 CDC Topics Created:"
    kubectl get kafkatopic -n kafka | grep dbserver1 || echo "   Topics are being created..."
else
    print_warning "Connector is still starting up or encountered an error"
    echo ""
    echo "Current status:"
    kubectl get kafkaconnector postgres-connector -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")]}' | jq .
    echo ""
    echo "Check logs:"
    echo "  kubectl logs -n kafka -l strimzi.io/cluster=cdc-platform-connect --tail=50"
fi

# Show final summary
echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "📊 Deployment Status:"
echo ""
echo "Connector:"
kubectl get kafkaconnector -n kafka
echo ""
echo "Topics:"
kubectl get kafkatopic -n kafka | grep -E "(NAME|dbserver1)" | head -10
echo ""

echo "=========================================="
echo "📚 Next Steps:"
echo "=========================================="
echo ""
echo "1. Verify connector is running:"
echo "   kubectl get kafkaconnector postgres-connector -n kafka"
echo ""
echo "2. Check connector logs:"
echo "   kubectl logs -n kafka -l strimzi.io/cluster=cdc-platform-connect --tail=50"
echo ""
echo "3. Test CDC by reading from a topic:"
echo "   kubectl exec -n kafka cdc-platform-kafka-brokers-1 -- \\"
echo "     bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 \\"
echo "     --topic dbserver1.public.products --from-beginning --max-messages 5"
echo ""
echo "4. Verify snapshot completion:"
echo "   kubectl logs -n kafka -l strimzi.io/cluster=cdc-platform-connect | grep -i snapshot"
echo ""
echo "5. Test live CDC by updating database records:"
echo "   # The connector will capture INSERT, UPDATE, DELETE events in real-time"
echo ""
echo "6. Next: Deploy consumer applications"
echo "   See: k8s/cdc-consumers/"
echo ""
echo "=========================================="
echo "📖 Documentation:"
echo "=========================================="
echo ""
echo "Debezium Docs: https://debezium.io/documentation/reference/stable/connectors/postgresql.html"
echo "Kafka Connect Docs: https://kafka.apache.org/documentation/#connect"
echo ""
