# Data source to get all available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Removed - OIDC provider is created by the EKS module
# and exposed via module.eks.oidc_provider_arn

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Data source for ECR Public authorization token (for Karpenter Helm chart)
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

# Data source to get AWS managed KMS key for EKS
data "aws_kms_key" "eks" {
  count  = var.create_eks_kms_key ? 0 : 1
  key_id = "alias/aws/eks"
}