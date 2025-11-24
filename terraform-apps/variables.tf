variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "git_repo_url" {
  description = "Git repository URL for ArgoCD applications"
  type        = string
  default     = "https://github.com/YOUR_ORG/cdc-platform"
}

variable "git_revision" {
  description = "Git branch/tag for ArgoCD"
  type        = string
  default     = "main"
}

variable "domain_name" {
  description = "Base domain name for applications"
  type        = string
  default     = "democloud.click"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for ALB (wildcard cert)"
  type        = string
  # Get this from ACM console or: aws acm list-certificates
}

variable "strimzi_version" {
  description = "Strimzi Kafka Operator version"
  type        = string
  default     = "0.48.0"  # Latest version with K8s 1.33 support
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.7.12"
}

variable "aws_lb_controller_version" {
  description = "AWS Load Balancer Controller version"
  type        = string
  default     = "1.7.1"
}
