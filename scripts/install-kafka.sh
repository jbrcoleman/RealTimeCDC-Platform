#!/bin/bash
set -e

# Kafka Cluster Installation Script using Helm
# This script installs Strimzi operator via Helm and deploys the Kafka cluster

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

# Create namespace if it doesn't exist
echo ""
echo "🔧 Setting up namespace..."
if kubectl get namespace kafka &> /dev/null; then
    print_status "Namespace 'kafka' already exists"
else
    kubectl create namespace kafka
    print_status "Created namespace 'kafka'"
fi

# Add Strimzi Helm repository
echo ""
echo "📦 Adding Strimzi Helm repository..."
helm repo add strimzi https://strimzi.io/charts/ 2>/dev/null || true
helm repo update
print_status "Strimzi Helm repository added and updated"

# Check if Strimzi operator is already installed
echo ""
echo "🔍 Checking for existing Strimzi installation..."
if helm list -n kafka | grep -q strimzi-operator; then
    print_warning "Strimzi operator is already installed"
    read -p "Do you want to upgrade it? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Upgrading Strimzi operator..."
        helm upgrade strimzi-operator strimzi/strimzi-kafka-operator \
            --namespace kafka \
            --values k8s/kafka/helm-values.yaml \
            --wait \
            --timeout 10m
        print_status "Strimzi operator upgraded"
    else
        print_status "Skipping operator installation"
    fi
else
    # Install Strimzi operator via Helm
    echo ""
    echo "🚀 Installing Strimzi Kafka operator..."
    helm install strimzi-operator strimzi/strimzi-kafka-operator \
        --namespace kafka \
        --values k8s/kafka/helm-values.yaml \
        --wait \
        --timeout 10m

    if [ $? -eq 0 ]; then
        print_status "Strimzi operator installed successfully"
    else
        print_error "Failed to install Strimzi operator"
        exit 1
    fi
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
echo "   - Creating 3 Zookeeper pods..."
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
if kubectl get kafka cdc-platform -n kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
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

# Deploy Kafka Connect
echo ""
echo "🔌 Deploying Kafka Connect cluster..."
kubectl apply -f k8s/kafka/kafka-connect.yaml

print_status "Kafka Connect deployment initiated"

echo ""
echo "⏳ Waiting for Kafka Connect to be ready..."
sleep 30  # Give it time to start creating

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

# Show final status
echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "📊 Cluster Status:"
echo ""
echo "Operator:"
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
echo "   kubectl exec -it cdc-platform-kafka-0 -n kafka -- \\"
echo "     bin/kafka-topics.sh --bootstrap-server localhost:9092 --list"
echo ""
echo "4. Check Kafka Connect:"
echo "   kubectl get pods -n kafka -l strimzi.io/cluster=cdc-platform-connect"
echo ""
echo "5. View Kafka logs:"
echo "   kubectl logs cdc-platform-kafka-0 -n kafka -c kafka"
echo ""
echo "6. Next: Deploy Debezium connectors"
echo "   See: k8s/debezium/"
echo ""
echo "=========================================="
echo "📖 Documentation:"
echo "=========================================="
echo ""
echo "Kafka README: k8s/kafka/README.md"
echo "Strimzi Docs: https://strimzi.io/docs/"
echo "Kafka Docs: https://kafka.apache.org/documentation/"
echo ""
