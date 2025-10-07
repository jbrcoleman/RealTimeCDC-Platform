# Data source to get all available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_iam_openid_connect_provider" "eks" {
  url = module.eks.cluster_oidc_issuer_url
}