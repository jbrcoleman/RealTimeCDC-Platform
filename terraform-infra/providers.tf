provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "cdc-platform"
      ManagedBy   = "terraform-infra"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

# Temporarily commented out - Karpenter already deployed
# data "aws_ecrpublic_authorization_token" "token" {
#   provider = aws.virginia
# }

data "aws_kms_key" "eks" {
  count  = var.create_eks_kms_key ? 0 : 1
  key_id = "alias/aws/eks"
}

# Provider alias for us-east-1 (required for ECR Public)
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "cdc-platform"
      ManagedBy   = "terraform-infra"
    }
  }
}
