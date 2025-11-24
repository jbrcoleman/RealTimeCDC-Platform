# EKS Cluster Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "EKS OIDC provider URL"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_address" {
  description = "RDS address (hostname)"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS port"
  value       = aws_db_instance.postgres.port
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.postgres.db_name
}

output "rds_username" {
  description = "RDS master username"
  value       = aws_db_instance.postgres.username
  sensitive   = true
}

# S3 Outputs
output "data_lake_bucket_name" {
  description = "S3 data lake bucket name"
  value       = aws_s3_bucket.cdc_data_lake.id
}

output "data_lake_bucket_arn" {
  description = "S3 data lake bucket ARN"
  value       = aws_s3_bucket.cdc_data_lake.arn
}

output "dlq_bucket_arn" {
  description = "S3 DLQ bucket ARN"
  value       = aws_s3_bucket.cdc_dlq.arn
}

output "kafka_connect_storage_bucket_arn" {
  description = "S3 Kafka Connect storage bucket ARN"
  value       = aws_s3_bucket.kafka_connect_storage.arn
}

# Secrets Manager Outputs
output "db_connection_secret_arn" {
  description = "Secrets Manager DB connection secret ARN"
  value       = aws_secretsmanager_secret.db_connection.arn
}

output "rds_master_secret_arn" {
  description = "RDS master user secret ARN"
  value       = length(aws_db_instance.postgres.master_user_secret) > 0 ? aws_db_instance.postgres.master_user_secret[0].secret_arn : ""
}

# Karpenter Outputs
output "karpenter_node_role_arn" {
  description = "Karpenter node IAM role ARN"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_node_role_name" {
  description = "Karpenter node IAM role name"
  value       = module.karpenter.node_iam_role_name
}

# Security Group Outputs
output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "EKS node security group ID"
  value       = module.eks.node_security_group_id
}

# Region & Account
output "region" {
  description = "AWS region"
  value       = var.region
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
