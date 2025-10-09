#!/bin/bash
set -e

echo "=== Applying Kubernetes Service Accounts with IAM Role Annotations ==="

# Check if terraform outputs are available
if ! terraform -chdir=terraform output > /dev/null 2>&1; then
    echo "Error: Terraform outputs not found. Please run 'terraform apply' first."
    exit 1
fi

# Get IAM Role ARNs from Terraform outputs
echo "Fetching IAM Role ARNs from Terraform..."
KAFKA_CONNECT_ROLE_ARN=$(terraform -chdir=terraform output -raw kafka_connect_role_arn)
DEBEZIUM_ROLE_ARN=$(terraform -chdir=terraform output -raw debezium_role_arn)
CDC_CONSUMER_ROLE_ARN=$(terraform -chdir=terraform output -raw cdc_consumer_role_arn)
FLINK_ROLE_ARN=$(terraform -chdir=terraform output -raw flink_role_arn)
SCHEMA_REGISTRY_ROLE_ARN=$(terraform -chdir=terraform output -raw schema_registry_role_arn)
EXTERNAL_SECRETS_ROLE_ARN=$(terraform -chdir=terraform output -raw external_secrets_role_arn)

echo "✓ Successfully retrieved all IAM Role ARNs"
echo ""

# Create namespaces first
echo "Creating namespaces..."
kubectl apply -f k8s/namespaces/namespaces.yaml
echo "✓ Namespaces created"
echo ""

# Apply service accounts with substituted role ARNs
echo "Creating service accounts with IAM role annotations..."
export KAFKA_CONNECT_ROLE_ARN
export DEBEZIUM_ROLE_ARN
export CDC_CONSUMER_ROLE_ARN
export FLINK_ROLE_ARN
export SCHEMA_REGISTRY_ROLE_ARN
export EXTERNAL_SECRETS_ROLE_ARN

envsubst < k8s/service-accounts/service-accounts.yaml | kubectl apply -f -
echo "✓ Service accounts created"
echo ""

# Verify service accounts
echo "Verifying service accounts..."
echo ""
echo "Kafka namespace:"
kubectl get sa -n kafka
echo ""
echo "CDC Consumers namespace:"
kubectl get sa -n cdc-consumers
echo ""
echo "Flink namespace:"
kubectl get sa -n flink
echo ""
echo "External Secrets namespace:"
kubectl get sa -n external-secrets
echo ""

echo "=== Service accounts successfully created with IRSA! ==="