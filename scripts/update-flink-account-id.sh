#!/bin/bash
set -e

# Update all Flink YAML files with AWS Account ID
# Usage: ./scripts/update-flink-account-id.sh

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}

echo "======================================"
echo "Updating Flink YAML files"
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
echo "AWS Region: ${AWS_REGION}"
echo "======================================"

# Update service accounts
echo "Updating k8s/flink/serviceaccount.yaml..."
sed -i.bak "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" k8s/flink/serviceaccount.yaml

# Update flink configuration (S3 bucket names)
echo "Updating k8s/flink/flink-configuration.yaml..."
sed -i.bak "s/BUCKET_NAME/cdc-platform-flink-checkpoints-${AWS_ACCOUNT_ID}/g" k8s/flink/flink-configuration.yaml

# Update all job manifests
echo "Updating job manifests..."
for job_file in k8s/flink/job-*.yaml; do
  echo "  - $(basename $job_file)"
  sed -i.bak "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" "$job_file"
done

# Clean up backup files
rm -f k8s/flink/*.bak

echo ""
echo "======================================"
echo "✅ All files updated successfully!"
echo "======================================"
echo ""
echo "Updated files:"
echo "  - k8s/flink/serviceaccount.yaml"
echo "  - k8s/flink/flink-configuration.yaml"
echo "  - k8s/flink/job-sales-aggregations.yaml"
echo "  - k8s/flink/job-customer-segmentation.yaml"
echo "  - k8s/flink/job-anomaly-detection.yaml"
echo "  - k8s/flink/job-inventory-optimizer.yaml"
echo ""
echo "Next steps:"
echo "  1. Create S3 bucket: aws s3 mb s3://cdc-platform-flink-checkpoints-${AWS_ACCOUNT_ID}"
echo "  2. Build images: ./scripts/build-flink-jobs.sh"
echo "  3. Deploy cluster: ./scripts/deploy-flink-cluster.sh"
echo "  4. Submit jobs: ./scripts/submit-flink-job.sh <job-name>"
