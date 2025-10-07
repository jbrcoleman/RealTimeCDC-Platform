locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
  name = "cdc-platform"
  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}