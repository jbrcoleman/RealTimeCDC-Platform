#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ArgoCD Applications Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}

echo -e "${YELLOW}AWS Account ID:${NC} $AWS_ACCOUNT_ID"
echo -e "${YELLOW}AWS Region:${NC} $AWS_REGION"
echo ""

# Check if kubectl is configured
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}Error: kubectl is not configured or cluster is not accessible${NC}"
    exit 1
fi

# Check if ArgoCD is installed
if ! kubectl get namespace argocd > /dev/null 2>&1; then
    echo -e "${RED}Error: ArgoCD namespace not found. Please run ./scripts/setup-argocd.sh first${NC}"
    exit 1
fi

# Create temporary directory for processed manifests
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo -e "${YELLOW}Processing ArgoCD application manifests...${NC}"

# Copy argocd directory to temp and substitute account ID
cp -r argocd/* "$TEMP_DIR/"

# Replace <<ACCOUNT_ID>> placeholder with actual account ID
find "$TEMP_DIR" -type f -name "*.yaml" -exec sed -i "s/<<ACCOUNT_ID>>/$AWS_ACCOUNT_ID/g" {} \;

echo -e "${GREEN}✓ Manifests processed${NC}"
echo ""

# Apply ArgoCD project
echo -e "${YELLOW}Creating ArgoCD project...${NC}"
kubectl apply -f "$TEMP_DIR/projects/cdc-platform.yaml"
echo -e "${GREEN}✓ Project created${NC}"
echo ""

# Apply root application (App of Apps)
echo -e "${YELLOW}Creating root application...${NC}"
kubectl apply -f "$TEMP_DIR/bootstrap/root-app.yaml"
echo -e "${GREEN}✓ Root application created${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ArgoCD Applications Deployed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}View applications:${NC}"
echo "  kubectl get applications -n argocd"
echo ""
echo -e "${YELLOW}Access ArgoCD UI:${NC}"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo ""
echo -e "${YELLOW}Get admin password:${NC}"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
