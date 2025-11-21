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
echo "  - DynamoDB tables and all data"
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

# CRITICAL: Delete NodePools/NodeClasses BEFORE uninstalling Karpenter
# This triggers Karpenter to gracefully terminate EC2 instances
if kubectl get namespace karpenter &> /dev/null; then
    echo "Deleting Karpenter NodePools (this will terminate EC2 instances)..."
    kubectl delete nodepools --all -A --timeout=120s 2>/dev/null || true

    echo "Deleting Karpenter NodeClasses..."
    kubectl delete nodeclasses --all -A --timeout=60s 2>/dev/null || true

    echo "Deleting EC2NodeClasses (legacy)..."
    kubectl delete ec2nodeclasses --all -A --timeout=60s 2>/dev/null || true

    # Wait for nodes to be drained and terminated
    echo "Waiting for Karpenter nodes to terminate..."
    sleep 30

    print_status "Karpenter NodePools deleted, EC2 instances terminating"
fi

# Now uninstall Karpenter Helm chart
if helm list -n karpenter | grep -q karpenter; then
    echo "Uninstalling Karpenter Helm chart..."
    helm uninstall karpenter -n karpenter || true
    print_status "Karpenter uninstalled"
fi

# Delete Karpenter namespace
if kubectl get namespace karpenter &> /dev/null; then
    echo "Deleting Karpenter namespace..."
    kubectl delete namespace karpenter --timeout=60s || kubectl delete namespace karpenter --grace-period=0 --force 2>/dev/null || true
    print_status "Karpenter namespace deleted"
fi

# Step 5: Delete DynamoDB tables created by applications
echo ""
echo "🔨 Step 5: Deleting DynamoDB tables..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
AWS_REGION=${AWS_REGION:-us-east-1}

if [ -n "$ACCOUNT_ID" ]; then
    # List all tables with cdc-platform prefix
    TABLES=$(aws dynamodb list-tables --region $AWS_REGION --query "TableNames[?starts_with(@, 'cdc-platform-')]" --output text 2>/dev/null)

    if [ -n "$TABLES" ]; then
        for table in $TABLES; do
            echo "Deleting DynamoDB table: $table"
            aws dynamodb delete-table --table-name $table --region $AWS_REGION 2>/dev/null || true
            print_status "Table $table deleted"
        done

        # Wait a moment for deletions to propagate
        sleep 5
    else
        print_warning "No DynamoDB tables with cdc-platform prefix found"
    fi
else
    print_error "Could not get AWS Account ID, skipping DynamoDB cleanup"
fi

# Step 6: Empty S3 buckets (required before terraform destroy)
echo ""
echo "🔨 Step 6: Emptying S3 buckets..."
if command -v terraform &> /dev/null && [ -d "terraform" ]; then
    cd terraform
    ACCOUNT_ID=$(terraform output -raw configure_kubectl 2>/dev/null | grep -oP 'account_id=\K[0-9]+' || aws sts get-caller-identity --query Account --output text)

    if [ -n "$ACCOUNT_ID" ]; then
        for bucket in "cdc-platform-data-lake-${ACCOUNT_ID}" "cdc-platform-dlq-${ACCOUNT_ID}" "cdc-platform-kafka-connect-${ACCOUNT_ID}"; do
            if aws s3 ls "s3://${bucket}" &> /dev/null; then
                echo "Emptying bucket: $bucket"

                # Delete all objects
                aws s3 rm "s3://${bucket}" --recursive || true

                # Delete all versions if versioning is enabled
                aws s3api delete-objects --bucket "${bucket}" \
                    --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
                    --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

                # Delete all delete markers
                aws s3api delete-objects --bucket "${bucket}" \
                    --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
                    --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

                print_status "Bucket $bucket emptied (including versions)"
            fi
        done
    fi
    cd ..
fi

# Step 7: Destroy AWS infrastructure with Terraform
echo ""
echo "🔨 Step 7: Destroying AWS infrastructure with Terraform..."
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

# Check for remaining Karpenter-created EC2 instances
echo "Checking for remaining Karpenter EC2 instances..."
REMAINING_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:karpenter.sh/nodepool,Values=*" "Name=instance-state-name,Values=running,pending" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text 2>/dev/null)

if [ -n "$REMAINING_INSTANCES" ]; then
    print_warning "Found remaining Karpenter-managed EC2 instances:"
    echo "$REMAINING_INSTANCES"
    echo ""
    echo "To manually terminate them, run:"
    echo "  aws ec2 terminate-instances --instance-ids $REMAINING_INSTANCES"
    echo ""
else
    print_status "No remaining Karpenter EC2 instances found"
fi

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
echo "  ✅ Karpenter NodePools and EC2 instances"
echo "  ✅ DynamoDB tables (application-created)"
echo "  ✅ S3 bucket contents"
echo "  ✅ AWS infrastructure (EKS, RDS, VPC, etc.)"
echo ""
echo "💡 Next steps:"
echo "  - Verify in AWS Console that all resources are deleted"
echo "  - Check for any remaining costs in AWS Cost Explorer"
echo "  - Review CloudWatch logs if needed (will be deleted after retention period)"
echo ""
