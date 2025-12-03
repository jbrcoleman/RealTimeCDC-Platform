#!/bin/bash
set -e

# Comprehensive Cleanup Script for CDC Platform
# This script safely tears down ALL infrastructure in the correct order

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Script header
echo ""
print_section "CDC Platform - Complete Infrastructure Teardown"
echo ""

# Confirmation
print_warning "This will PERMANENTLY delete ALL resources including:"
echo "  - EKS Cluster and all Kubernetes workloads"
echo "  - RDS PostgreSQL database and ALL DATA"
echo "  - DynamoDB tables and ALL DATA"
echo "  - S3 buckets and ALL contents"
echo "  - VPC, subnets, and networking"
echo "  - IAM roles and policies"
echo "  - EC2 instances (Karpenter nodes)"
echo "  - Load Balancers and other AWS resources"
echo ""
print_error "THIS CANNOT BE UNDONE!"
echo ""
read -p "Type 'DELETE' to confirm complete infrastructure destruction: " -r
echo

if [[ $REPLY != "DELETE" ]]; then
    print_info "Teardown cancelled"
    exit 0
fi

# Get AWS account info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
AWS_REGION=${AWS_REGION:-us-east-1}

if [ -z "$ACCOUNT_ID" ]; then
    print_error "Could not get AWS Account ID. Please configure AWS CLI."
    exit 1
fi

print_info "AWS Account ID: $ACCOUNT_ID"
print_info "AWS Region: $AWS_REGION"

# ============================================
# STEP 1: Clean up ArgoCD Applications
# ============================================
print_section "STEP 1: Cleaning up ArgoCD Applications"

if kubectl get namespace argocd &> /dev/null; then
    print_info "Deleting ArgoCD applications..."

    # Delete child applications first
    kubectl delete applications -n argocd consumer-apps --ignore-not-found=true --timeout=60s 2>/dev/null || true
    kubectl delete applications -n argocd flink-jobs --ignore-not-found=true --timeout=60s 2>/dev/null || true
    kubectl delete applications -n argocd ingress-resources --ignore-not-found=true --timeout=60s 2>/dev/null || true
    kubectl delete applications -n argocd kafka-cluster --ignore-not-found=true --timeout=60s 2>/dev/null || true

    # Delete root app
    kubectl delete applications -n argocd root-app --ignore-not-found=true --timeout=60s 2>/dev/null || true

    # Delete ArgoCD namespace
    kubectl delete namespace argocd --timeout=60s 2>/dev/null || kubectl delete namespace argocd --grace-period=0 --force 2>/dev/null || true

    print_status "ArgoCD applications deleted"
else
    print_warning "ArgoCD namespace not found, skipping"
fi

# ============================================
# STEP 2: Clean up Kafka Resources (CRITICAL ORDER)
# ============================================
print_section "STEP 2: Cleaning up Kafka Resources"

if kubectl get namespace kafka &> /dev/null; then
    # Delete Kafka connectors first
    if kubectl get kafkaconnector -n kafka &> /dev/null 2>&1; then
        print_info "Deleting Kafka connectors..."
        kubectl delete kafkaconnector -n kafka --all --timeout=60s 2>/dev/null || true
    fi

    # Delete Kafka Connect clusters
    if kubectl get kafkaconnect -n kafka &> /dev/null 2>&1; then
        print_info "Deleting Kafka Connect clusters..."
        kubectl delete kafkaconnect -n kafka --all --timeout=60s 2>/dev/null || true
    fi

    # Delete Kafka topics
    if kubectl get kafkatopic -n kafka &> /dev/null 2>&1; then
        print_info "Deleting Kafka topics..."
        kubectl delete kafkatopic -n kafka --all --timeout=60s 2>/dev/null || true
    fi

    # Delete Kafka clusters
    if kubectl get kafka -n kafka &> /dev/null 2>&1; then
        print_info "Deleting Kafka clusters..."
        kubectl delete kafka -n kafka --all --timeout=120s 2>/dev/null || true

        # Wait for Kafka to be fully deleted
        kubectl wait --for=delete kafka/cdc-platform -n kafka --timeout=120s 2>/dev/null || true
    fi

    # Clean up stuck resources with finalizers
    print_info "Removing finalizers from stuck Kafka resources..."
    kubectl patch kafka cdc-platform -n kafka -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl patch kafkaconnect cdc-platform-connect -n kafka -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

    print_status "Kafka resources deleted"
else
    print_warning "Kafka namespace not found, skipping"
fi

# ============================================
# STEP 3: Clean up Application Namespaces
# ============================================
print_section "STEP 3: Cleaning up Application Namespaces"

for ns in cdc-consumers flink external-secrets monitoring; do
    if kubectl get namespace $ns &> /dev/null; then
        print_info "Deleting namespace: $ns"
        kubectl delete namespace $ns --timeout=60s 2>/dev/null || kubectl delete namespace $ns --grace-period=0 --force 2>/dev/null || true
        print_status "Namespace $ns deleted"
    fi
done

# ============================================
# STEP 4: Uninstall Helm Releases
# ============================================
print_section "STEP 4: Uninstalling Helm Releases"

# Uninstall Strimzi Operator
if helm list -n kafka 2>/dev/null | grep -q strimzi-operator; then
    print_info "Uninstalling Strimzi operator..."
    helm uninstall strimzi-operator -n kafka --wait --timeout=300s 2>/dev/null || true
    print_status "Strimzi operator uninstalled"
fi

# Delete Kafka namespace
if kubectl get namespace kafka &> /dev/null; then
    print_info "Deleting kafka namespace..."
    kubectl delete namespace kafka --timeout=120s 2>/dev/null || kubectl delete namespace kafka --grace-period=0 --force 2>/dev/null || true
    print_status "Kafka namespace deleted"
fi

# Uninstall AWS Load Balancer Controller
if helm list -n kube-system 2>/dev/null | grep -q aws-load-balancer-controller; then
    print_info "Uninstalling AWS Load Balancer Controller..."
    helm uninstall aws-load-balancer-controller -n kube-system --wait --timeout=300s 2>/dev/null || true
    print_status "AWS Load Balancer Controller uninstalled"
fi

# ============================================
# STEP 5: Clean up Karpenter Resources (CRITICAL)
# ============================================
print_section "STEP 5: Cleaning up Karpenter Resources"

# CRITICAL: Delete NodePools/NodeClasses BEFORE uninstalling Karpenter
# This triggers Karpenter to gracefully terminate EC2 instances
if kubectl get namespace karpenter &> /dev/null; then
    print_info "Deleting Karpenter NodePools (this will terminate EC2 instances)..."
    kubectl delete nodepools --all -A --timeout=120s 2>/dev/null || true

    print_info "Deleting Karpenter NodeClasses..."
    kubectl delete nodeclasses --all -A --timeout=60s 2>/dev/null || true

    print_info "Deleting EC2NodeClasses (legacy)..."
    kubectl delete ec2nodeclasses --all -A --timeout=60s 2>/dev/null || true

    print_info "Deleting NodeClaims..."
    kubectl delete nodeclaims --all -A --timeout=60s 2>/dev/null || true

    # Wait for nodes to be drained and terminated
    print_info "Waiting for Karpenter nodes to terminate (30s)..."
    sleep 30

    print_status "Karpenter NodePools deleted, EC2 instances terminating"
fi

# Uninstall Karpenter Helm chart
if helm list -n karpenter 2>/dev/null | grep -q karpenter; then
    print_info "Uninstalling Karpenter Helm chart..."
    helm uninstall karpenter -n karpenter 2>/dev/null || true
    print_status "Karpenter uninstalled"
fi

# Delete Karpenter namespace
if kubectl get namespace karpenter &> /dev/null; then
    print_info "Deleting Karpenter namespace..."
    kubectl delete namespace karpenter --timeout=60s 2>/dev/null || kubectl delete namespace karpenter --grace-period=0 --force 2>/dev/null || true
    print_status "Karpenter namespace deleted"
fi

# ============================================
# STEP 6: Clean up Strimzi CRDs
# ============================================
print_section "STEP 6: Cleaning up Strimzi CRDs"

print_info "Deleting Strimzi Custom Resource Definitions..."
kubectl delete crd -l app=strimzi 2>/dev/null || true
kubectl delete clusterrole -l app=strimzi 2>/dev/null || true
kubectl delete clusterrolebinding -l app=strimzi 2>/dev/null || true

print_status "Strimzi CRDs cleaned up"

# ============================================
# STEP 7: Delete DynamoDB Tables
# ============================================
print_section "STEP 7: Deleting DynamoDB Tables"

print_info "Searching for DynamoDB tables with 'cdc-platform-' prefix..."
TABLES=$(aws dynamodb list-tables --region $AWS_REGION --query "TableNames[?starts_with(@, 'cdc-platform-')]" --output text 2>/dev/null)

if [ -n "$TABLES" ]; then
    print_info "Found DynamoDB tables to delete:"
    for table in $TABLES; do
        echo "  - $table"
    done

    for table in $TABLES; do
        print_info "Deleting DynamoDB table: $table"
        aws dynamodb delete-table --table-name $table --region $AWS_REGION 2>/dev/null || true
    done

    print_status "DynamoDB tables deletion initiated"
    sleep 5
else
    print_warning "No DynamoDB tables with 'cdc-platform-' prefix found"
fi

# ============================================
# STEP 8: Empty S3 Buckets
# ============================================
print_section "STEP 8: Emptying S3 Buckets"

print_info "Emptying S3 buckets (required before Terraform can delete them)..."

for bucket in "cdc-platform-data-lake-${ACCOUNT_ID}" "cdc-platform-dlq-${ACCOUNT_ID}" "cdc-platform-kafka-connect-${ACCOUNT_ID}"; do
    if aws s3 ls "s3://${bucket}" &> /dev/null; then
        print_info "Emptying bucket: $bucket"

        # Delete all objects
        aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true

        # Delete all versions if versioning is enabled
        aws s3api delete-objects --bucket "${bucket}" \
            --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
            --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

        # Delete all delete markers
        aws s3api delete-objects --bucket "${bucket}" \
            --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
            --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

        print_status "Bucket $bucket emptied"
    else
        print_warning "Bucket $bucket not found or already deleted"
    fi
done

# ============================================
# STEP 9: Destroy Terraform Apps Layer
# ============================================
print_section "STEP 9: Destroying Terraform Apps Layer"

if [ -d "terraform-apps" ]; then
    cd terraform-apps

    if terraform state list &> /dev/null 2>&1; then
        print_info "Destroying Terraform-managed applications..."
        terraform destroy -auto-approve

        if [ $? -eq 0 ]; then
            print_status "Terraform apps layer destroyed"
        else
            print_warning "Some Terraform app resources may have failed to destroy"
        fi
    else
        print_warning "No Terraform state found in terraform-apps"
    fi

    cd ..
else
    print_warning "terraform-apps directory not found, skipping"
fi

# ============================================
# STEP 10: Destroy Terraform Infrastructure Layer
# ============================================
print_section "STEP 10: Destroying Terraform Infrastructure Layer"

if [ -d "terraform-infra" ]; then
    cd terraform-infra

    if terraform state list &> /dev/null 2>&1; then
        print_info "Destroying AWS infrastructure (EKS, RDS, VPC, etc.)..."
        print_warning "This may take 10-15 minutes..."

        terraform destroy -auto-approve

        if [ $? -eq 0 ]; then
            print_status "AWS infrastructure destroyed successfully"
        else
            print_error "Terraform destroy encountered errors"
            print_warning "You may need to manually delete remaining resources"
        fi
    else
        print_warning "No Terraform state found in terraform-infra"
    fi

    cd ..
else
    print_warning "terraform-infra directory not found, skipping"
fi

# ============================================
# Final Status Check
# ============================================
print_section "Final Status Check"

print_info "Checking for remaining resources..."
echo ""

# Check namespaces
echo "Remaining CDC-related namespaces:"
kubectl get namespaces 2>/dev/null | grep -E "(kafka|cdc|argocd|flink|external|monitoring)" || echo "  ✅ None found"
echo ""

# Check for remaining Karpenter EC2 instances
print_info "Checking for remaining Karpenter EC2 instances..."
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
else
    print_status "No remaining Karpenter EC2 instances found"
fi

# Check for remaining EBS volumes
print_info "Checking for remaining EBS volumes..."
REMAINING_VOLUMES=$(aws ec2 describe-volumes \
    --filters "Name=tag-key,Values=kubernetes.io/cluster/cdc-platform" "Name=status,Values=available" \
    --query "Volumes[].VolumeId" \
    --output text 2>/dev/null)

if [ -n "$REMAINING_VOLUMES" ]; then
    print_warning "Found remaining EBS volumes:"
    echo "$REMAINING_VOLUMES"
    echo ""
    echo "To manually delete them, run:"
    echo "  for vol in $REMAINING_VOLUMES; do aws ec2 delete-volume --volume-id \$vol; done"
else
    print_status "No remaining EBS volumes found"
fi

# Check for remaining Load Balancers
print_info "Checking for remaining Load Balancers..."
REMAINING_LBS=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?contains(LoadBalancerName, 'cdc-platform')].LoadBalancerArn" \
    --output text 2>/dev/null)

if [ -n "$REMAINING_LBS" ]; then
    print_warning "Found remaining Load Balancers:"
    echo "$REMAINING_LBS"
    echo ""
    echo "To manually delete them, check AWS Console"
else
    print_status "No remaining Load Balancers found"
fi

# ============================================
# Summary
# ============================================
print_section "🎉 Teardown Complete!"

echo ""
print_status "Successfully destroyed:"
echo "  ✅ ArgoCD and GitOps configurations"
echo "  ✅ Kafka clusters and Strimzi operator"
echo "  ✅ Application namespaces and workloads"
echo "  ✅ Helm releases"
echo "  ✅ Karpenter NodePools and nodes"
echo "  ✅ Strimzi CRDs"
echo "  ✅ DynamoDB tables"
echo "  ✅ S3 bucket contents"
echo "  ✅ Terraform apps layer"
echo "  ✅ Terraform infrastructure (EKS, RDS, VPC, IAM)"
echo ""

print_info "Next steps:"
echo "  1. Verify in AWS Console that all resources are deleted"
echo "  2. Check AWS Cost Explorer for any remaining costs"
echo "  3. Review CloudWatch logs if needed (will be deleted after retention period)"
echo "  4. Delete local kubeconfig context:"
echo "     kubectl config delete-context <context-name>"
echo "  5. Clean up Terraform state files if desired:"
echo "     rm -rf terraform-infra/.terraform terraform-infra/terraform.tfstate*"
echo "     rm -rf terraform-apps/.terraform terraform-apps/terraform.tfstate*"
echo ""

print_warning "If any resources remain, check the AWS Console and delete them manually"
echo ""
