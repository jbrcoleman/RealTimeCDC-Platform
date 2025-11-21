#!/bin/bash
set -e

# Build and push all Flink job Docker images to ECR
#
# Usage:
#   ./scripts/build-flink-jobs.sh [job-name]
#
# If job-name is provided, only that job is built.
# Otherwise, all jobs are built.

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Job names
JOBS=(
  "sales-aggregations"
  "customer-segmentation"
  "anomaly-detection"
  "inventory-optimizer"
)

# Function to build and push a single job
build_job() {
  local JOB_NAME=$1
  local IMAGE_NAME="flink-${JOB_NAME}"
  local FULL_IMAGE="${ECR_REGISTRY}/${IMAGE_NAME}"

  echo "======================================"
  echo "Building: ${IMAGE_NAME}"
  echo "======================================"

  # Create ECR repository if it doesn't exist
  aws ecr describe-repositories --repository-names "${IMAGE_NAME}" --region "${AWS_REGION}" 2>/dev/null || \
    aws ecr create-repository --repository-name "${IMAGE_NAME}" --region "${AWS_REGION}"

  # Build Docker image
  docker build \
    -t "${IMAGE_NAME}:latest" \
    -f "apps/flink/pyflink/jobs/${JOB_NAME}/Dockerfile" \
    .

  # Tag for ECR
  docker tag "${IMAGE_NAME}:latest" "${FULL_IMAGE}:latest"
  docker tag "${IMAGE_NAME}:latest" "${FULL_IMAGE}:$(date +%Y%m%d-%H%M%S)"

  # Login to ECR
  aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ECR_REGISTRY}"

  # Push to ECR
  docker push "${FULL_IMAGE}:latest"
  docker push "${FULL_IMAGE}:$(date +%Y%m%d-%H%M%S)"

  echo "✅ Built and pushed: ${FULL_IMAGE}:latest"
  echo ""
}

# Main execution
if [ $# -eq 1 ]; then
  # Build single job
  JOB_NAME=$1
  if [[ ! " ${JOBS[@]} " =~ " ${JOB_NAME} " ]]; then
    echo "Error: Unknown job '${JOB_NAME}'"
    echo "Available jobs: ${JOBS[*]}"
    exit 1
  fi
  build_job "${JOB_NAME}"
else
  # Build all jobs
  echo "Building all Flink jobs..."
  echo ""
  for JOB in "${JOBS[@]}"; do
    build_job "${JOB}"
  done
  echo "======================================"
  echo "✅ All Flink jobs built successfully!"
  echo "======================================"
fi
