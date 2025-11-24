#!/bin/bash
set -e

# Comprehensive Cleanup Script for CDC Platform
# Cleans up resources in the correct order: Apps → Kafka → Terraform

echo "=========================================="
echo "CDC Platform - Comprehensive Cleanup"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Confirmation
echo ""
print_warning "This will delete ALL resources including:"
echo "  - All Kubernetes applications (ArgoCD, Kafka, Consumers, Flink)"
echo "  - Helm releases (Strimzi, ArgoCD, AWS LB Controller)"
echo "  - Terraform-managed infrastructure (EKS cluster will remain)"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_info "Cleanup cancelled"
    exit 0
fi

# ============================================
# STEP 1: Clean up ArgoCD Applications
# ============================================
echo ""
echo "=========================================="
echo "STEP 1: Cleaning up ArgoCD Applications"
echo "=========================================="

if kubectl get namespace argocd &> /dev/null; then
    print_info "Deleting ArgoCD applications..."

    # Delete child applications first
    kubectl delete applications -n argocd consumer-apps --ignore-not-found=true --timeout=60s || true
    kubectl delete applications -n argocd flink-jobs --ignore-not-found=true --timeout=60s || true
    kubectl delete applications -n argocd ingress-resources --ignore-not-found=true --timeout=60s || true
    kubectl delete applications -n argocd kafka-cluster --ignore-not-found=true --timeout=60s || true

    # Delete root app
    kubectl delete applications -n argocd root-app --ignore-not-found=true --timeout=60s || true

    print_status "ArgoCD applications deleted"
else
    print_info "ArgoCD namespace not found, skipping..."
fi

# ============================================
# STEP 2: Clean up Kafka Resources
# ============================================
echo ""
echo "=========================================="
echo "STEP 2: Cleaning up Kafka Resources"
echo "=========================================="

if kubectl get namespace kafka &> /dev/null; then
    print_info "Deleting Kafka Connect connectors..."
    kubectl delete kafkaconnector -n kafka --all --timeout=60s || true

    print_info "Deleting Kafka Connect cluster..."
    kubectl delete kafkaconnect -n kafka --all --timeout=60s || true

    print_info "Deleting Kafka topics..."
    kubectl delete kafkatopic -n kafka --all --timeout=60s || true

    print_info "Deleting Kafka cluster..."
    kubectl delete kafka -n kafka --all --timeout=120s || true

    print_info "Waiting for Kafka resources to terminate..."
    sleep 10

    print_status "Kafka resources deleted"
else
    print_info "Kafka namespace not found, skipping..."
fi

# ============================================
# STEP 3: Uninstall Helm Releases
# ============================================
echo ""
echo "=========================================="
echo "STEP 3: Uninstalling Helm Releases"
echo "=========================================="

# Uninstall Strimzi Operator
if helm list -n kafka 2>/dev/null | grep -q strimzi-operator; then
    print_info "Uninstalling Strimzi operator..."
    helm uninstall strimzi-operator -n kafka --wait --timeout=300s || true
    print_status "Strimzi operator uninstalled"
fi

# Delete Kafka namespace
if kubectl get namespace kafka &> /dev/null; then
    print_info "Deleting kafka namespace..."
    kubectl delete namespace kafka --timeout=120s || true
    print_status "Kafka namespace deleted"
fi

# ============================================
# STEP 4: Clean up Terraform Apps Layer
# ============================================
echo ""
echo "=========================================="
echo "STEP 4: Cleaning up Terraform Apps Layer"
echo "=========================================="

if [ -d "terraform-apps" ]; then
    cd terraform-apps

    print_info "Destroying Terraform-managed applications..."
    terraform destroy -auto-approve || {
        print_warning "Some Terraform resources may have failed to destroy"
        print_info "You may need to manually clean up remaining resources"
    }

    print_status "Terraform apps layer cleaned up"
    cd ..
else
    print_warning "terraform-apps directory not found, skipping..."
fi

# ============================================
# STEP 5: Clean up DynamoDB tables (optional)
# ============================================
echo ""
echo "=========================================="
echo "STEP 5: DynamoDB Cleanup (Optional)"
echo "=========================================="

read -p "Do you want to clean up DynamoDB tables? (yes/no): " -r
echo
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    if [ -f "scripts/cleanup-dynamodb.sh" ]; then
        print_info "Running DynamoDB cleanup..."
        ./scripts/cleanup-dynamodb.sh
        print_status "DynamoDB cleanup complete"
    else
        print_warning "DynamoDB cleanup script not found"
    fi
else
    print_info "Skipping DynamoDB cleanup"
fi

# ============================================
# STEP 6: Clean up Strimzi CRDs
# ============================================
echo ""
echo "=========================================="
echo "STEP 6: Cleaning up Strimzi CRDs"
echo "=========================================="

print_info "Deleting Strimzi Custom Resource Definitions..."
kubectl delete crd -l app=strimzi 2>/dev/null || true
kubectl delete clusterrole -l app=strimzi 2>/dev/null || true
kubectl delete clusterrolebinding -l app=strimzi 2>/dev/null || true

print_status "Strimzi CRDs cleaned up"

# ============================================
# Final Status
# ============================================
echo ""
echo "=========================================="
echo "✅ Cleanup Complete!"
echo "=========================================="
echo ""
print_info "Summary:"
echo "  ✓ ArgoCD applications removed"
echo "  ✓ Kafka resources removed"
echo "  ✓ Helm releases uninstalled"
echo "  ✓ Terraform apps destroyed"
echo "  ✓ Strimzi CRDs removed"
echo ""
print_info "EKS Infrastructure remains intact (managed by terraform-infra/)"
echo ""
print_warning "To completely destroy the EKS cluster, run:"
echo "  cd terraform-infra && terraform destroy"
echo ""
