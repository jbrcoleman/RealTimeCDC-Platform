#!/bin/bash
# Quick teardown script for CDC Platform infrastructure
# This script handles the proper order of resource deletion

set -e

echo "=========================================="
echo "CDC Platform Infrastructure Teardown"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Confirmation prompt
echo -e "${YELLOW}WARNING: This will destroy all infrastructure resources!${NC}"
echo "Resources to be deleted:"
echo "  - EKS Cluster and nodes"
echo "  - RDS PostgreSQL database"
echo "  - VPC and networking"
echo "  - S3 buckets and data"
echo "  - IAM roles and policies"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${RED}Teardown cancelled${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Starting teardown...${NC}"
echo ""

# Step 1: Delete Helm releases first (prevents issues with LoadBalancers)
echo "Step 1: Checking for Helm releases..."
if command -v helm &> /dev/null && command -v kubectl &> /dev/null; then
    echo "Deleting Karpenter Helm release..."
    helm uninstall karpenter -n karpenter 2>/dev/null || echo "Karpenter not found or already deleted"

    # Give time for cleanup
    sleep 10
fi

# Step 2: Delete any Karpenter NodeClaims and NodePools
echo ""
echo "Step 2: Cleaning up Karpenter resources..."
if command -v kubectl &> /dev/null; then
    kubectl delete nodepools --all --ignore-not-found=true 2>/dev/null || true
    kubectl delete nodeclaims --all --ignore-not-found=true 2>/dev/null || true
    kubectl delete ec2nodeclasses --all --ignore-not-found=true 2>/dev/null || true
    sleep 5
fi

# Step 3: Empty S3 buckets (required before Terraform can delete them)
echo ""
echo "Step 3: Emptying S3 buckets..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_PREFIX="cdc-platform"

for bucket in "${BUCKET_PREFIX}-data-lake-${ACCOUNT_ID}" "${BUCKET_PREFIX}-dlq-${ACCOUNT_ID}" "${BUCKET_PREFIX}-kafka-connect-${ACCOUNT_ID}"; do
    if aws s3 ls "s3://${bucket}" 2>/dev/null; then
        echo "Emptying bucket: ${bucket}"
        aws s3 rm "s3://${bucket}" --recursive || true

        # Delete all versions if versioning is enabled
        aws s3api delete-objects --bucket "${bucket}" \
            --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
            --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true

        # Delete all delete markers
        aws s3api delete-objects --bucket "${bucket}" \
            --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
            --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true
    else
        echo "Bucket ${bucket} not found or already deleted"
    fi
done

# Step 4: Run Terraform destroy
echo ""
echo "Step 4: Running Terraform destroy..."
echo -e "${YELLOW}This may take 10-15 minutes...${NC}"
echo ""

terraform destroy -auto-approve

# Check if successful
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "Teardown completed successfully!"
    echo "==========================================${NC}"
    echo ""
    echo "All infrastructure has been destroyed."
    echo "You may want to:"
    echo "  - Check AWS Console to verify all resources are deleted"
    echo "  - Remove any local state files if no longer needed"
    echo "  - Delete the kubeconfig context: kubectl config delete-context <context-name>"
else
    echo ""
    echo -e "${RED}=========================================="
    echo "Teardown encountered errors!"
    echo "==========================================${NC}"
    echo ""
    echo "You may need to:"
    echo "  1. Check for manually created resources (LoadBalancers, EBS volumes, etc.)"
    echo "  2. Review the Terraform state: terraform state list"
    echo "  3. Manually delete problematic resources in AWS Console"
    echo "  4. Re-run: terraform destroy"
    exit 1
fi
