# Kubernetes Service Accounts with IRSA

This directory contains example service account configurations that use IAM Roles for Service Accounts (IRSA) to grant AWS permissions to pods.

## How IRSA Works

1. Terraform creates IAM roles with trust policies that allow specific Kubernetes service accounts to assume them
2. You annotate the Kubernetes service account with the IAM role ARN
3. Pods using that service account automatically get AWS credentials via the EKS Pod Identity webhook

## Service Account Examples

### Kafka Connect Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-connect
  namespace: kafka
  annotations:
    eks.amazonaws.com/role-arn: <KAFKA_CONNECT_ROLE_ARN>
```

**Permissions:**
- Read/Write S3 buckets (data lake, DLQ, Kafka Connect storage)
- Read RDS credentials from Secrets Manager

### Debezium Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: debezium
  namespace: kafka
  annotations:
    eks.amazonaws.com/role-arn: <DEBEZIUM_ROLE_ARN>
```

**Permissions:**
- Read RDS credentials from Secrets Manager

### CDC Consumer Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: inventory-service
  namespace: cdc-consumers
  annotations:
    eks.amazonaws.com/role-arn: <CDC_CONSUMER_ROLE_ARN>
```

**Permissions:**
- Read from S3 data lake
- Write to S3 DLQ
- DynamoDB read/write operations
- Read RDS connection info from Secrets Manager

### Flink Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flink-jobmanager
  namespace: flink
  annotations:
    eks.amazonaws.com/role-arn: <FLINK_ROLE_ARN>
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flink-taskmanager
  namespace: flink
  annotations:
    eks.amazonaws.com/role-arn: <FLINK_ROLE_ARN>
```

**Permissions:**
- Read/Write S3 buckets
- Publish CloudWatch metrics

### Schema Registry Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: schema-registry
  namespace: kafka
  annotations:
    eks.amazonaws.com/role-arn: <SCHEMA_REGISTRY_ROLE_ARN>
```

**Permissions:**
- Read/Write schemas to S3

### External Secrets Operator Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: external-secrets
  annotations:
    eks.amazonaws.com/role-arn: <EXTERNAL_SECRETS_ROLE_ARN>
```

**Permissions:**
- Read all secrets from AWS Secrets Manager

## Getting Role ARNs

After running `terraform apply`, you can get the role ARNs:

```bash
# Get all IAM role ARNs
terraform output kafka_connect_role_arn
terraform output debezium_role_arn
terraform output cdc_consumer_role_arn
terraform output flink_role_arn
terraform output schema_registry_role_arn
terraform output external_secrets_role_arn
```

## Using Service Accounts in Deployments

Reference the service account in your pod specs:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-connect
  namespace: kafka
spec:
  template:
    spec:
      serviceAccountName: kafka-connect
      containers:
      - name: kafka-connect
        image: debezium/connect:latest
        # Container automatically gets AWS credentials
```

## Verifying IRSA Setup

To verify that a pod has AWS credentials:

```bash
# Exec into a pod
kubectl exec -it <pod-name> -n <namespace> -- sh

# Check for AWS credentials (should show temporary credentials)
env | grep AWS

# Test AWS access
aws s3 ls
aws secretsmanager list-secrets
```

## Namespace Creation

Make sure to create the namespaces before applying service accounts:

```bash
kubectl create namespace kafka
kubectl create namespace cdc-consumers
kubectl create namespace flink
kubectl create namespace external-secrets
```