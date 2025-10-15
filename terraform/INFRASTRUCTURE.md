# CDC Platform Infrastructure Guide

## Overview
This Terraform configuration creates a complete Real-Time CDC platform on AWS with:
- EKS cluster with Karpenter autoscaling
- PostgreSQL database (RDS) configured for CDC
- S3 buckets for data lake, DLQ, and Kafka Connect
- IAM roles for Kubernetes workloads (IRSA)

## Cost Estimate (Monthly)
**Approximate costs for us-east-1 (learning environment):**
- EKS Cluster: ~$73/month (cluster control plane)
- EC2 Nodes (2x m5.large): ~$140/month
- RDS db.t3.micro: ~$15/month
- NAT Gateway: ~$32/month
- S3 Storage: Minimal (pay per use)
- Data Transfer: Variable

**Total: ~$260-280/month** (running 24/7)

### Cost Savings Tips:
1. **Stop when not in use**: Scale node group to 0, stop RDS instance
2. **Use smaller instances**: Change to t3.medium nodes
3. **Single AZ**: Remove multi-AZ for dev (not recommended for prod)
4. **Spot instances**: Use Karpenter with spot for workloads

## Quick Start

### 1. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (takes ~15-20 minutes)
terraform apply
```

### 2. Configure kubectl
```bash
aws eks --region us-east-1 update-kubeconfig --name cdc-platform
```

### 3. Verify Deployment
```bash
# Check cluster
kubectl get nodes

# Check Karpenter
kubectl get pods -n karpenter

# Check addons
kubectl get pods -n kube-system
```

## Resources Created

### Networking (VPC)
- **CIDR**: 10.1.0.0/16
- **Subnets**: 3 public + 3 private (across 3 AZs)
- **NAT Gateway**: Single (shared across all private subnets)
- **Internet Gateway**: For public subnet internet access

### EKS Cluster
- **Version**: 1.33
- **Nodes**: 2x m5.large (Bottlerocket OS)
- **Addons**: CoreDNS, kube-proxy, VPC CNI, Pod Identity Agent
- **Encryption**: KMS key for secrets encryption

### Karpenter (Autoscaler)
- **Version**: 1.0.2
- **Purpose**: Dynamic node provisioning for workloads
- **Features**: Spot instance support, bin-packing, fast scaling

### RDS PostgreSQL
- **Instance**: db.t3.micro
- **Version**: 16.3
- **Storage**: 20GB (auto-scales to 100GB)
- **Backups**: 7-day retention
- **CDC Enabled**: Logical replication configured

### S3 Buckets
1. **Data Lake**: `cdc-platform-data-lake-<account-id>`
2. **DLQ**: `cdc-platform-dlq-<account-id>`
3. **Kafka Connect**: `cdc-platform-kafka-connect-<account-id>`

All buckets have:
- Versioning enabled
- Server-side encryption (AES256)
- Public access blocked
- Lifecycle policies (90 days retention)

### IAM Roles (IRSA)
Service accounts with pod identity for:
- Debezium (source connector)
- Kafka Connect
- Schema Registry
- CDC Consumer
- Flink (stream processing)
- External Secrets Operator

## Accessing Resources

### RDS Database
```bash
# Get endpoint from Terraform output
terraform output

# Connect (from within VPC/EKS)
psql -h <rds-endpoint> -U dbadmin -d ecommerce
# Password is in the terraform.tfstate (for learning only!)
```

### S3 Buckets
```bash
# List buckets
aws s3 ls | grep cdc-platform

# Access from pods (uses IRSA roles)
```

## Teardown

### Quick Teardown (Automated)
```bash
# Run the teardown script
./teardown.sh
```

This script will:
1. Delete Helm releases (prevents orphaned LoadBalancers)
2. Clean up Karpenter resources
3. Empty S3 buckets
4. Run `terraform destroy`

### Manual Teardown
```bash
# 1. Delete Helm releases
helm uninstall karpenter -n karpenter

# 2. Empty S3 buckets
aws s3 rm s3://cdc-platform-data-lake-<account-id> --recursive
aws s3 rm s3://cdc-platform-dlq-<account-id> --recursive
aws s3 rm s3://cdc-platform-kafka-connect-<account-id> --recursive

# 3. Destroy infrastructure
terraform destroy
```

## Common Issues

### 1. Terraform Init Fails
```
Error: no available releases match the given constraints
```
**Fix**: Module version conflicts. Ensure all modules use compatible AWS provider versions.

### 2. Destroy Fails (S3 buckets)
```
Error: BucketNotEmpty
```
**Fix**: Empty buckets before destroying (handled by teardown.sh)

### 3. Destroy Fails (ENIs in use)
```
Error: Network interface is currently in use
```
**Fix**: Delete all pods/LoadBalancers in EKS first, wait 5 minutes, retry destroy

### 4. Can't Connect to RDS
**Fix**: RDS is in private subnets. Connect from:
- EKS pods (recommended)
- Bastion host in VPC
- VPN/Direct Connect

## Security Notes

⚠️ **This is a LEARNING environment** - Not production-ready!

**Current limitations:**
- Database password in terraform state (use AWS Secrets Manager in prod)
- Single NAT Gateway (no HA)
- Skip final snapshot on RDS (data loss on destroy)
- No WAF, GuardDuty, or Security Hub
- Minimal network ACLs
- Public EKS endpoint (use private in prod)

**For Production:**
1. Use remote state (S3 + DynamoDB)
2. Enable encryption at rest everywhere
3. Use AWS Secrets Manager for credentials
4. Enable CloudTrail, Config, GuardDuty
5. Implement network segmentation (multiple security groups)
6. Use private EKS endpoint
7. Enable RDS Multi-AZ
8. Use multiple NAT Gateways
9. Implement backup and disaster recovery
10. Add monitoring (CloudWatch, Prometheus)

## Next Steps

After infrastructure is deployed:
1. Deploy Kafka/Strimzi to EKS (see k8s/ directory)
2. Configure Debezium for CDC
3. Set up Schema Registry
4. Deploy Flink for stream processing
5. Configure data pipelines

## Outputs

Key outputs available after apply:
```bash
terraform output
```

- `configure_kubectl`: Command to configure kubectl
- Database endpoint and credentials
- S3 bucket names
- IAM role ARNs for workloads
- VPC and subnet IDs

## Support

For issues:
1. Check CloudWatch Logs
2. Review Terraform state: `terraform state list`
3. Check AWS Console for manual resources
4. Review this documentation

## Cost Monitoring

```bash
# Check current AWS spending
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=SERVICE
```

Set up billing alerts in AWS Console!
