#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CDC Consumer Services Deployment Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo -e "${YELLOW}AWS Account ID:${NC} $AWS_ACCOUNT_ID"
echo -e "${YELLOW}AWS Region:${NC} $AWS_REGION"
echo -e "${YELLOW}ECR Registry:${NC} $ECR_REGISTRY"
echo ""

# Function to create ECR repository if it doesn't exist
create_ecr_repo() {
    local repo_name=$1
    echo -e "${YELLOW}Checking ECR repository: ${repo_name}${NC}"

    if aws ecr describe-repositories --repository-names $repo_name --region $AWS_REGION >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Repository ${repo_name} already exists${NC}"
    else
        echo -e "${YELLOW}Creating ECR repository: ${repo_name}${NC}"
        aws ecr create-repository --repository-name $repo_name --region $AWS_REGION
        echo -e "${GREEN}✓ Repository ${repo_name} created${NC}"
    fi
}

# Function to build and push Docker image
build_and_push() {
    local service_name=$1
    local service_dir=$2

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Building and pushing: ${service_name}${NC}"
    echo -e "${GREEN}========================================${NC}"

    # Create ECR repository
    create_ecr_repo $service_name

    # Build Docker image
    echo -e "${YELLOW}Building Docker image...${NC}"
    cd $service_dir
    docker build -t ${service_name}:latest .

    # Tag image
    echo -e "${YELLOW}Tagging image...${NC}"
    docker tag ${service_name}:latest ${ECR_REGISTRY}/${service_name}:latest

    # Push to ECR
    echo -e "${YELLOW}Pushing to ECR...${NC}"
    docker push ${ECR_REGISTRY}/${service_name}:latest

    echo -e "${GREEN}✓ ${service_name} pushed successfully${NC}"
    cd - > /dev/null
}

# Login to ECR
echo -e "${YELLOW}Logging into ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
echo -e "${GREEN}✓ ECR login successful${NC}"

# Build and push all services
build_and_push "inventory-service" "./apps/python/inventory-service"
build_and_push "analytics-service" "./apps/python/analytics-service"
build_and_push "search-indexer" "./apps/python/search-indexer"

# Update Kubernetes manifests with account ID
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Updating Kubernetes Manifests${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "${YELLOW}Updating deployment manifests with AWS Account ID...${NC}"

# Create temporary files with account ID replaced
for file in k8s/consumers/*-deployment.yaml; do
    if [ -f "$file" ]; then
        sed "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" $file > ${file}.tmp
        mv ${file}.tmp $file
        echo -e "${GREEN}✓ Updated $(basename $file)${NC}"
    fi
done

# Deploy to Kubernetes
echo ""
echo -e "${YELLOW}Do you want to deploy to Kubernetes now? (y/n)${NC}"
read -r response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${YELLOW}Deploying to Kubernetes...${NC}"

    # Check if namespace exists
    if ! kubectl get namespace cdc-consumers >/dev/null 2>&1; then
        echo -e "${YELLOW}Creating namespace cdc-consumers...${NC}"
        kubectl create namespace cdc-consumers
    fi

    # Apply manifests
    kubectl apply -f k8s/consumers/

    echo ""
    echo -e "${GREEN}✓ Deployment complete!${NC}"
    echo ""
    echo -e "${YELLOW}Checking pod status...${NC}"
    kubectl get pods -n cdc-consumers

    echo ""
    echo -e "${YELLOW}To view logs:${NC}"
    echo "  kubectl logs -l app=inventory-service -n cdc-consumers --tail=50"
    echo "  kubectl logs -l app=analytics-service -n cdc-consumers --tail=50"
    echo "  kubectl logs -l app=search-indexer -n cdc-consumers --tail=50"
else
    echo -e "${YELLOW}Skipping Kubernetes deployment${NC}"
    echo ""
    echo -e "${YELLOW}To deploy manually, run:${NC}"
    echo "  kubectl apply -f k8s/consumers/"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Script Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
