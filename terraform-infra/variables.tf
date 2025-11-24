variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "cdc-platform"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "cdcdb"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "cdcadmin"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "create_eks_kms_key" {
  description = "Whether to create a custom KMS key for EKS cluster encryption"
  type        = bool
  default     = false
}

variable "eks_kms_key_arn" {
  description = "ARN of an existing KMS key to use for EKS cluster encryption"
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "The waiting period before the KMS key is deleted after destruction"
  type        = number
  default     = 7
}
