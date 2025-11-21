#!/bin/bash
set -e

# Deploy Flink cluster to Kubernetes
#
# This script:
# 1. Creates Flink namespace
# 2. Deploys JobManager and TaskManager
# 3. Waits for cluster to be ready

echo "======================================"
echo "Deploying Flink Cluster"
echo "======================================"

# Get AWS account ID for ConfigMap
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}

# Update ConfigMap with AWS account ID
echo "Updating Flink configuration with AWS account ID..."
kubectl create namespace flink --dry-run=client -o yaml | kubectl apply -f -

# Apply Flink manifests
echo "Applying Flink cluster manifests..."
kubectl apply -f k8s/flink/serviceaccount.yaml

# Update ConfigMap with actual bucket name using sed replacement
echo "Updating S3 bucket name in Flink configuration..."
sed "s/BUCKET_NAME/cdc-platform-flink-checkpoints-${AWS_ACCOUNT_ID}/g" k8s/flink/flink-configuration.yaml | kubectl apply -f -

kubectl apply -f k8s/flink/flink-cluster.yaml

# Wait for JobManager to be ready
echo "Waiting for Flink JobManager to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/flink-jobmanager -n flink

# Wait for TaskManagers to be ready
echo "Waiting for Flink TaskManagers to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/flink-taskmanager -n flink

# Get Flink Web UI URL
echo ""
echo "======================================"
echo "✅ Flink Cluster Deployed!"
echo "======================================"
echo ""
echo "Access Flink Web UI:"
FLINK_UI=$(kubectl get svc flink-jobmanager-rest -n flink -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -n "$FLINK_UI" ]; then
  echo "  http://${FLINK_UI}:8081"
else
  echo "  Waiting for LoadBalancer... (this may take a few minutes)"
  echo "  Run: kubectl get svc flink-jobmanager-rest -n flink"
fi
echo ""
echo "Port-forward (alternative):"
echo "  kubectl port-forward svc/flink-jobmanager -n flink 8081:8081"
echo "  Then open: http://localhost:8081"
echo ""
