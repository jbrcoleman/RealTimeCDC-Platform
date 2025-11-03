#!/bin/bash
set -e

# Cleanup Script for CDC Platform
# This script safely tears down the entire CDC platform infrastructure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo "=========================================="
echo "CDC Platform - Complete Cleanup"
echo "=========================================="
echo ""

# Confirmation
print_warning "This will delete ALL resources including:"
echo "  - Kafka clusters and all data"
echo "  - RDS PostgreSQL database and all data"
echo "  - S3 buckets and contents"
echo "  - EKS cluster and all workloads"
echo "  - All IAM roles and policies"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Step 1: Clean up Kafka resources (CRITICAL: must be first)
echo ""
echo "🔨 Step 1: Cleaning up Kafka resources..."
if kubectl get namespace kafka &> /dev/null; then
    # Delete Kafka connectors
    if kubectl get kafkaconnector -n kafka &> /dev/null 2>&1; then
        echo "Deleting Kafka connectors..."
        kubectl delete kafkaconnector -n kafka --all --timeout=60s || true
        print_status "Kafka connectors deleted"
    fi

    # Delete Kafka Connect clusters
    if kubectl get kafkaconnect -n kafka &> /dev/null 2>&1; then
        echo "Deleting Kafka Connect clusters..."
        kubectl delete kafkaconnect -n kafka --all --timeout=60s || true
        print_status "Kafka Connect clusters deleted"
    fi

    # Delete Kafka clusters
    if kubectl get kafka -n kafka &> /dev/null 2>&1; then
        echo "Deleting Kafka clusters..."
        kubectl delete kafka -n kafka --all --timeout=120s || true

        # Wait for Kafka to be fully deleted
        echo "Waiting for Kafka cluster to be fully deleted..."
        kubectl wait --for=delete kafka/cdc-platform -n kafka --timeout=120s 2>/dev/null || true
        print_status "Kafka clusters deleted"
    fi

    # Uninstall Strimzi operator
    if helm list -n kafka | grep -q strimzi-operator; then
        echo "Uninstalling Strimzi operator..."
        helm uninstall strimzi-operator -n kafka || true
        print_status "Strimzi operator uninstalled"
    fi

    # Clean up any stuck resources
    echo "Cleaning up stuck Kafka resources..."
    kubectl patch kafka cdc-platform -n kafka -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl patch kafkaconnect cdc-platform-connect -n kafka -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

    # Delete Kafka namespace
    echo "Deleting Kafka namespace..."
    kubectl delete namespace kafka --timeout=60s || kubectl delete namespace kafka --grace-period=0 --force 2>/dev/null || true
    print_status "Kafka namespace deleted"
else
    print_warning "Kafka namespace not found, skipping"
fi

# Step 2: Clean up ArgoCD
echo ""
echo "🔨 Step 2: Cleaning up ArgoCD..."
if kubectl get namespace argocd &> /dev/null; then
    kubectl delete namespace argocd --timeout=60s || kubectl delete namespace argocd --grace-period=0 --force 2>/dev/null || true
    print_status "ArgoCD namespace deleted"
else
    print_warning "ArgoCD namespace not found, skipping"
fi

# Step 3: Clean up application namespaces
echo ""
echo "🔨 Step 3: Cleaning up application namespaces..."
for ns in cdc-consumers flink external-secrets monitoring; do
    if kubectl get namespace $ns &> /dev/null; then
        echo "Deleting namespace: $ns"
        kubectl delete namespace $ns --timeout=60s || kubectl delete namespace $ns --grace-period=0 --force 2>/dev/null || true
        print_status "Namespace $ns deleted"
    fi
done

# Step 4: Clean up Karpenter resources
echo ""
echo "🔨 Step 4: Cleaning up Karpenter..."
if helm list -n karpenter | grep -q karpenter; then
    helm uninstall karpenter -n karpenter || true
    print_status "Karpenter uninstalled"
fi

# Step 5: Empty S3 buckets (required before terraform destroy)
echo ""
echo "🔨 Step 5: Emptying S3 buckets..."
if command -v terraform &> /dev/null && [ -d "terraform" ]; then
    cd terraform
    ACCOUNT_ID=$(terraform output -raw configure_kubectl 2>/dev/null | grep -oP 'account_id=\K[0-9]+' || aws sts get-caller-identity --query Account --output text)

    if [ -n "$ACCOUNT_ID" ]; then
        for bucket in "cdc-platform-data-lake-${ACCOUNT_ID}" "cdc-platform-dlq-${ACCOUNT_ID}" "cdc-platform-kafka-connect-${ACCOUNT_ID}"; do
            if aws s3 ls "s3://${bucket}" &> /dev/null; then
                echo "Emptying bucket: $bucket"
                aws s3 rm "s3://${bucket}" --recursive || true
                print_status "Bucket $bucket emptied"
            fi
        done
    fi
    cd ..
fi

# Step 6: Destroy AWS infrastructure with Terraform
echo ""
echo "🔨 Step 6: Destroying AWS infrastructure with Terraform..."
if [ -d "terraform" ]; then
    cd terraform

    # Check if terraform state exists
    if terraform state list &> /dev/null; then
        echo "Running terraform destroy..."
        terraform destroy -auto-approve

        if [ $? -eq 0 ]; then
            print_status "AWS infrastructure destroyed successfully"
        else
            print_error "Terraform destroy encountered errors"
            echo "You may need to manually delete remaining resources"
        fi
    else
        print_warning "No Terraform state found, skipping"
    fi

    cd ..
else
    print_warning "Terraform directory not found, skipping"
fi

# Final cleanup check
echo ""
echo "🔍 Checking for remaining resources..."
echo ""
echo "Remaining namespaces:"
kubectl get namespaces | grep -E "(kafka|cdc|argocd|flink|external|monitoring)" || echo "  None found"
echo ""

# Summary
echo ""
echo "=========================================="
print_status "Cleanup complete!"
echo "=========================================="
echo ""
echo "📋 What was cleaned up:"
echo "  ✅ Kafka clusters and Strimzi operator"
echo "  ✅ ArgoCD and GitOps configurations"
echo "  ✅ Application namespaces"
echo "  ✅ S3 bucket contents"
echo "  ✅ AWS infrastructure (EKS, RDS, VPC, etc.)"
echo ""
echo "💡 Next steps:"
echo "  - Verify in AWS Console that all resources are deleted"
echo "  - Check for any remaining costs in AWS Cost Explorer"
echo "  - Review CloudWatch logs if needed (will be deleted after retention period)"
echo ""
