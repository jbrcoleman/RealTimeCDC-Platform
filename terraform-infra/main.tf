locals {
  name               = var.cluster_name
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)
  karpenter_namespace = "karpenter"

  tags = {
    Environment = var.environment
    Project     = "cdc-platform"
    Terraform   = "true"
  }
}
