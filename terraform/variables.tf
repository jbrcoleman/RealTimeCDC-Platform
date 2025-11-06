variable "region" {
  description = "AWS region"
  type        = string
  default = "us-east-1"
}

variable "create_eks_kms_key" {
  description = "Whether to create a custom KMS key for EKS cluster encryption. Set to false to use AWS-managed key and save costs."
  type        = bool
  default     = false
}

variable "eks_kms_key_arn" {
  description = "ARN of an existing KMS key to use for EKS cluster encryption. Only used if create_eks_kms_key is false. If not provided, AWS managed key (alias/aws/eks) will be used."
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "The waiting period before the KMS key is deleted after destruction (only used if create_eks_kms_key is true)"
  type        = number
  default     = 7
}