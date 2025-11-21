#!/bin/bash
set -e

# Submit a Flink job to the cluster
#
# Usage:
#   ./scripts/submit-flink-job.sh <job-name>
#
# Example:
#   ./scripts/submit-flink-job.sh sales-aggregations

if [ $# -ne 1 ]; then
  echo "Usage: $0 <job-name>"
  echo "Available jobs:"
  echo "  - sales-aggregations"
  echo "  - customer-segmentation"
  echo "  - anomaly-detection"
  echo "  - inventory-optimizer"
  exit 1
fi

JOB_NAME=$1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "======================================"
echo "Submitting Flink Job: ${JOB_NAME}"
echo "======================================"

# Update job manifest with AWS account ID
sed "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" "k8s/flink/job-${JOB_NAME}.yaml" | kubectl apply -f -

# Wait for job to start
echo "Waiting for job to start..."
sleep 5

# Show job status
JOB_POD=$(kubectl get pods -n flink -l job=${JOB_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$JOB_POD" ]; then
  echo ""
  echo "Job pod: ${JOB_POD}"
  echo ""
  echo "View logs:"
  echo "  kubectl logs -f ${JOB_POD} -n flink"
  echo ""
  echo "Check status:"
  echo "  kubectl get job flink-${JOB_NAME} -n flink"
else
  echo "Job submitted. Check Flink Web UI for status."
fi

echo ""
echo "✅ Job submitted successfully!"
