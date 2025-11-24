# Read infrastructure outputs
data "terraform_remote_state" "infra" {
  backend = "local"

  config = {
    path = "../terraform-infra/terraform.tfstate"
  }
}

# For S3 backend (production), use this instead:
# data "terraform_remote_state" "infra" {
#   backend = "s3"
#   config = {
#     bucket = "my-terraform-state"
#     key    = "cdc-platform/infra/terraform.tfstate"
#     region = "us-east-1"
#   }
# }

# Create local variables from infra outputs
locals {
  name                                = data.terraform_remote_state.infra.outputs.cluster_name
  cluster_name                        = data.terraform_remote_state.infra.outputs.cluster_name
  cluster_endpoint                    = data.terraform_remote_state.infra.outputs.cluster_endpoint
  cluster_certificate_authority_data  = data.terraform_remote_state.infra.outputs.cluster_certificate_authority_data
  cluster_oidc_issuer_url            = data.terraform_remote_state.infra.outputs.cluster_oidc_issuer_url
  oidc_provider_arn                  = data.terraform_remote_state.infra.outputs.oidc_provider_arn
  vpc_id                             = data.terraform_remote_state.infra.outputs.vpc_id
  private_subnet_ids                 = data.terraform_remote_state.infra.outputs.private_subnet_ids
  karpenter_node_role_name           = data.terraform_remote_state.infra.outputs.karpenter_node_role_name
  region                             = data.terraform_remote_state.infra.outputs.region
  account_id                         = data.terraform_remote_state.infra.outputs.account_id

  # S3 buckets
  data_lake_bucket_arn               = data.terraform_remote_state.infra.outputs.data_lake_bucket_arn
  dlq_bucket_arn                     = data.terraform_remote_state.infra.outputs.dlq_bucket_arn
  kafka_connect_storage_bucket_arn   = data.terraform_remote_state.infra.outputs.kafka_connect_storage_bucket_arn

  # Secrets
  db_connection_secret_arn           = data.terraform_remote_state.infra.outputs.db_connection_secret_arn
  rds_master_secret_arn              = data.terraform_remote_state.infra.outputs.rds_master_secret_arn

  # Tags
  tags = {
    Environment = var.environment
    Project     = "cdc-platform"
    Terraform   = "true"
    ManagedBy   = "terraform-apps"
  }
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}
