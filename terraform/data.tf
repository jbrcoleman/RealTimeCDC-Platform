# Data source to get all available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}