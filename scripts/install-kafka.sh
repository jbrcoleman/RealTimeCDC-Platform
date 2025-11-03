#!/bin/bash
set -e

# Kafka Cluster Installation Script using Helm
# Simple and reliable approach using official Strimzi Helm chart

echo "=========================================="
echo "CDC Platform - Kafka Cluster Installation"
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

if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed. Please install Helm first."
    echo "  Visit: https://helm.sh/docs/intro/install/"
    exit 1
fi
print_status "Helm is installed"

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

# Clean up any previous installations
echo ""
echo "🧹 Cleaning up any previous installations..."

# Uninstall Helm release if it exists
if helm list -n kafka 2>/dev/null | grep -q strimzi-operator; then
    print_warning "Found existing Helm release, uninstalling..."
    helm uninstall strimzi-operator -n kafka --wait || true
    sleep 3
fi

# Delete namespace-scoped resources first
if kubectl get namespace kafka &> /dev/null; then
    print_warning "Cleaning up kafka namespace resources..."
    # Delete all rolebindings in kafka namespace
    kubectl delete rolebindings -n kafka --all 2>/dev/null || true
    # Delete namespace
    kubectl delete namespace kafka --timeout=60s || true
    sleep 5
fi

# Clean up cluster-scoped resources
print_warning "Cleaning up cluster-scoped Strimzi resources..."
kubectl delete clusterrole -l app=strimzi 2>/dev/null || true
kubectl delete clusterrolebinding -l app=strimzi 2>/dev/null || true
kubectl delete crd -l app=strimzi 2>/dev/null || true

# Wait for cleanup to complete
sleep 3

print_status "Cleanup complete"

# Add Strimzi Helm repository
echo ""
echo "📦 Adding Strimzi Helm repository..."
helm repo add strimzi https://strimzi.io/charts/ 2>/dev/null || true
helm repo update
print_status "Strimzi Helm repository added and updated"

# Install Strimzi operator via Helm
echo ""
echo "🚀 Installing Strimzi Kafka operator (version 0.48.0)..."
helm install strimzi-operator strimzi/strimzi-kafka-operator \
    --namespace kafka \
    --create-namespace \
    --version 0.48.0 \
    --wait \
    --timeout 5m

if [ $? -eq 0 ]; then
    print_status "Strimzi operator installed successfully"
else
    print_error "Failed to install Strimzi operator"
    exit 1
fi

# Wait for operator to be ready
echo ""
echo "⏳ Waiting for Strimzi operator to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/strimzi-cluster-operator -n kafka

print_status "Strimzi operator is ready"

# Deploy Kafka cluster
echo ""
echo "🔨 Deploying Kafka cluster..."
kubectl apply -f k8s/kafka/kafka-cluster.yaml

print_status "Kafka cluster deployment initiated"

# Wait for Kafka cluster to be ready
echo ""
echo "⏳ Waiting for Kafka cluster to be ready (this may take 5-10 minutes)..."
echo "   - Creating 3 Kafka broker pods..."
echo "   - Provisioning persistent volumes..."

# Wait for Kafka resource to exist
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if kubectl get kafka cdc-platform -n kafka &> /dev/null; then
        print_status "Kafka resource created"
        break
    fi
    attempt=$((attempt + 1))
    sleep 5
done

# Wait for Kafka to be ready
kubectl wait --for=condition=ready --timeout=600s \
    kafka/cdc-platform -n kafka 2>/dev/null || {
    print_warning "Kafka cluster is still initializing. You can check status with:"
    echo "  kubectl get kafka -n kafka"
    echo "  kubectl get pods -n kafka"
}

# Check if Kafka is actually ready
if kubectl get kafka cdc-platform -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    print_status "Kafka cluster is ready"

    # Show cluster info
    echo ""
    echo "📊 Kafka Cluster Information:"
    kubectl get kafka cdc-platform -n kafka
    echo ""
    kubectl get pods -n kafka -l strimzi.io/cluster=cdc-platform
else
    print_warning "Kafka cluster is still starting up"
    echo ""
    echo "Current status:"
    kubectl get pods -n kafka
fi

# Deploy Kafka topics
echo ""
echo "📝 Creating Kafka topics..."
kubectl apply -f k8s/kafka/kafka-topics.yaml

print_status "Kafka topics created"

# Create placeholder db-credentials secret for Kafka Connect
# This will be updated with real credentials by install-debezium.sh
echo ""
echo "🔐 Creating placeholder database credentials secret..."
kubectl create secret generic db-credentials \
    --from-literal=password=placeholder \
    -n kafka \
    --dry-run=client -o yaml | kubectl apply -f -

print_status "Database credentials secret created (will be updated by Debezium installation)"

# Create ECR repository for Kafka Connect image build
echo ""
echo "📦 Creating ECR repository for Kafka Connect..."
AWS_REGION=$(aws configure get region || echo "us-east-1")
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if aws ecr describe-repositories --repository-names cdc-platform-connect --region $AWS_REGION &>/dev/null; then
    print_status "ECR repository already exists"
else
    aws ecr create-repository \
        --repository-name cdc-platform-connect \
        --region $AWS_REGION \
        --image-scanning-configuration scanOnPush=true >/dev/null
    print_status "ECR repository created: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/cdc-platform-connect"
fi

# Create ECR credentials secret for image push during Kafka Connect build
echo ""
echo "🔑 Creating ECR credentials secret for image push..."
ECR_PASSWORD=$(aws ecr get-login-password --region $AWS_REGION)
kubectl create secret docker-registry ecr-credentials \
    --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
    --docker-username=AWS \
    --docker-password="$ECR_PASSWORD" \
    --namespace=kafka \
    --dry-run=client -o yaml | kubectl apply -f -

print_status "ECR credentials secret created"

# Deploy service accounts with IAM role associations
echo ""
echo "👤 Creating service accounts..."
kubectl apply -f k8s/service-accounts/service-accounts.yaml

print_status "Service accounts created"

# Deploy Kafka Connect
echo ""
echo "🔌 Deploying Kafka Connect cluster..."
kubectl apply -f k8s/kafka/kafka-connect.yaml

print_status "Kafka Connect deployment initiated"

echo ""
echo "⏳ Waiting for Kafka Connect to be ready (this may take 5-10 minutes)..."
echo "   - Building custom Docker image with Debezium connectors..."
echo "   - Pushing image to ECR..."
echo "   - Starting Kafka Connect pod..."

# Wait for KafkaConnect resource
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if kubectl get kafkaconnect cdc-platform-connect -n kafka &> /dev/null; then
        print_status "Kafka Connect resource created"
        break
    fi
    attempt=$((attempt + 1))
    sleep 5
done

# Wait for Kafka Connect to be ready
kubectl wait --for=condition=ready --timeout=600s \
    kafkaconnect/cdc-platform-connect -n kafka 2>/dev/null || {
    print_warning "Kafka Connect is still building. You can check status with:"
    echo "  kubectl get kafkaconnect -n kafka"
    echo "  kubectl get pods -n kafka | grep connect"
    echo "  kubectl logs -n kafka cdc-platform-connect-connect-build"
}

# Check if Kafka Connect is actually ready
if kubectl get kafkaconnect cdc-platform-connect -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    print_status "Kafka Connect is ready"
else
    print_warning "Kafka Connect is still starting up"
    echo ""
    echo "Current status:"
    kubectl get kafkaconnect -n kafka
fi

# Show final status
echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "📊 Cluster Status:"
echo ""
echo "Helm Release:"
helm list -n kafka
echo ""
echo "Kafka Cluster:"
kubectl get kafka -n kafka
echo ""
echo "Kafka Connect:"
kubectl get kafkaconnect -n kafka
echo ""
echo "Topics:"
kubectl get kafkatopic -n kafka | head -10
echo ""
echo "Pods:"
kubectl get pods -n kafka
echo ""
echo "=========================================="
echo "📚 Next Steps:"
echo "=========================================="
echo ""
echo "1. Verify Kafka cluster:"
echo "   kubectl get kafka cdc-platform -n kafka"
echo ""
echo "2. Check broker pods:"
echo "   kubectl get pods -n kafka -l strimzi.io/cluster=cdc-platform"
echo ""
echo "3. Test Kafka connection:"
echo "   kubectl exec -it cdc-platform-kafka-brokers-0 -n kafka -- \\"
echo "     bin/kafka-topics.sh --bootstrap-server localhost:9092 --list"
echo ""
echo "4. Check Kafka Connect:"
echo "   kubectl get pods -n kafka -l strimzi.io/cluster=cdc-platform-connect"
echo ""
echo "5. View Kafka logs:"
echo "   kubectl logs cdc-platform-kafka-brokers-0 -n kafka -c kafka"
echo ""
echo "6. Next: Deploy Debezium connectors"
echo "   ./scripts/install-debezium.sh"
echo ""
