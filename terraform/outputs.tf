output "availability_zones" {
  description = "First 3 availability zones"
  value       = local.azs
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "s3_data_lake_bucket" {
  description = "S3 data lake bucket name"
  value       = aws_s3_bucket.cdc_data_lake.id
}

output "s3_data_lake_arn" {
  description = "S3 data lake bucket ARN"
  value       = aws_s3_bucket.cdc_data_lake.arn
}

output "s3_dlq_bucket" {
  description = "S3 DLQ bucket name"
  value       = aws_s3_bucket.cdc_dlq.id
}

output "s3_kafka_connect_bucket" {
  description = "S3 Kafka Connect bucket name"
  value       = aws_s3_bucket.kafka_connect_storage.id
}

output "kafka_connect_role_arn" {
  description = "IAM role ARN for Kafka Connect service account"
  value       = module.kafka_connect_pod_identity.iam_role_arn
}

output "debezium_role_arn" {
  description = "IAM role ARN for Debezium service account"
  value       = module.debezium_pod_identity.iam_role_arn
}

output "cdc_consumer_role_arn" {
  description = "IAM role ARN for CDC consumer applications"
  value       = module.cdc_consumer_pod_identity.iam_role_arn
}

output "flink_role_arn" {
  description = "IAM role ARN for Flink service account"
  value       = module.flink_pod_identity.iam_role_arn
}

output "schema_registry_role_arn" {
  description = "IAM role ARN for Schema Registry service account"
  value       = module.schema_registry_pod_identity.iam_role_arn
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = module.external_secrets_pod_identity.iam_role_arn
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (without port)"
  value       = aws_db_instance.postgres.address
}

output "rds_endpoint_full" {
  description = "RDS PostgreSQL endpoint with port"
  value       = aws_db_instance.postgres.endpoint
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

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.postgres.port
}

output "rds_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.postgres.identifier
}

output "rds_master_user_secret_arn" {
  description = "ARN of the RDS-managed master user secret in Secrets Manager"
  value       = length(aws_db_instance.postgres.master_user_secret) > 0 ? aws_db_instance.postgres.master_user_secret[0].secret_arn : null
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI Driver service account"
  value       = module.ebs_csi_driver_pod_identity.iam_role_arn
}