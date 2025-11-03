#!/bin/bash
set -e

echo "=== Applying Kubernetes Service Accounts with Pod Identity ==="

# Check if terraform outputs are available
if ! terraform -chdir=terraform output > /dev/null 2>&1; then
    echo "Error: Terraform outputs not found. Please run 'terraform apply' first."
    exit 1
fi

echo "Note: IAM roles are now managed via EKS Pod Identity associations in Terraform."
echo "Service accounts no longer need IRSA annotations."
echo ""

# Create namespaces first
echo "Creating namespaces..."
kubectl apply -f k8s/namespaces/namespaces.yaml
echo "✓ Namespaces created"
echo ""

# Apply service accounts directly (no substitution needed for Pod Identity)
echo "Creating service accounts..."
kubectl apply -f k8s/service-accounts/service-accounts.yaml
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

# Show Pod Identity associations
echo "Verifying Pod Identity associations (managed by Terraform)..."
echo ""
CLUSTER_NAME=$(terraform -chdir=terraform output -raw configure_kubectl | grep -o 'name [^ ]*' | cut -d' ' -f2)
REGION=$(terraform -chdir=terraform output -raw configure_kubectl | grep -o 'region [^ ]*' | cut -d' ' -f2)

echo "Pod Identity Associations for cluster: $CLUSTER_NAME"
aws eks list-pod-identity-associations --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'associations[*].{Namespace:namespace,ServiceAccount:serviceAccount}' --output table 2>/dev/null || echo "Note: Run terraform apply to create Pod Identity associations"
echo ""

echo "=== Service accounts successfully created with Pod Identity! ==="