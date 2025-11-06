#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AWS Configuration Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}

echo -e "${YELLOW}AWS Account ID:${NC} $AWS_ACCOUNT_ID"
echo -e "${YELLOW}AWS Region:${NC} $AWS_REGION"
echo ""

# Create namespace if it doesn't exist
kubectl create namespace cdc-consumers --dry-run=client -o yaml | kubectl apply -f -

# Create ConfigMap with AWS-specific values
echo -e "${YELLOW}Creating aws-config ConfigMap...${NC}"
kubectl create configmap aws-config \
  --from-literal=account_id="$AWS_ACCOUNT_ID" \
  --from-literal=region="$AWS_REGION" \
  --from-literal=ecr_registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" \
  --from-literal=data_lake_bucket="cdc-platform-data-lake-${AWS_ACCOUNT_ID}" \
  --from-literal=dlq_bucket="cdc-platform-dlq-${AWS_ACCOUNT_ID}" \
  --namespace=cdc-consumers \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ ConfigMap created${NC}"
echo ""

# Create ECR pull secret for ArgoCD Image Updater
echo -e "${YELLOW}Creating ECR credentials secret for Image Updater...${NC}"

# Get ECR token
ECR_TOKEN=$(aws ecr get-login-password --region $AWS_REGION)

# Create docker config JSON
DOCKER_CONFIG_JSON=$(cat <<EOF
{
  "auths": {
    "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com": {
      "username": "AWS",
      "password": "${ECR_TOKEN}"
    }
  }
}
EOF
)

# Create secret in argocd namespace for Image Updater
kubectl create secret generic ecr-credentials \
  --from-literal=username=AWS \
  --from-literal=password="${ECR_TOKEN}" \
  --namespace=argocd \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ ECR credentials secret created${NC}"
echo ""

# Also create image pull secret in cdc-consumers namespace for pods
kubectl create secret docker-registry ecr-credentials \
  --docker-server="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --namespace=cdc-consumers \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Image pull secret created${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} ECR tokens expire after 12 hours"
echo -e "${YELLOW}To refresh:${NC} Re-run this script"
echo ""
echo -e "${YELLOW}For production:${NC} Use IAM roles for service accounts (IRSA) instead"
echo ""
