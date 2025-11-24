# Terraform Infrastructure Workspace

This workspace deploys the foundational infrastructure for the CDC Platform:

## Components

- **VPC**: Network infrastructure with public and private subnets
- **EKS Cluster**: Kubernetes control plane with initial node group for Karpenter
- **RDS PostgreSQL**: Database with CDC-enabled logical replication
- **S3 Buckets**: Data lake, DLQ, and Kafka Connect storage
- **IAM Roles**: Service accounts and permissions
- **Karpenter Controller**: Autoscaling infrastructure (controller only, not NodePools)

## Usage

### Initialize

```bash
terraform init
```

### Plan

```bash
terraform plan -out=tfplan
```

### Apply

```bash
terraform apply tfplan
```

This takes approximately 15-20 minutes to complete.

### Outputs

All outputs are consumed by the `terraform-apps` workspace via remote state.

Key outputs:
- `cluster_name`
- `cluster_endpoint`
- `oidc_provider_arn`
- `vpc_id`
- `private_subnet_ids`
- `rds_endpoint`
- `karpenter_node_role_name`

## State Management

By default, state is stored locally in `terraform.tfstate`.

For production, configure S3 backend in `versions.tf`:

```hcl
backend "s3" {
  bucket         = "my-terraform-state"
  key            = "cdc-platform/infra/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

## Notes

- The Karpenter controller is installed, but NodePools are managed in `terraform-apps`
- Worker nodes will not appear until `terraform-apps` is applied
- RDS password is automatically managed by AWS and stored in Secrets Manager
