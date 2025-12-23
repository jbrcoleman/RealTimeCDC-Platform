# Prometheus & Grafana Monitoring Stack

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = "62.3.1"
  timeout          = 600

  values = [
    file("${path.module}/../k8s/monitoring/prometheus-stack-values.yaml")
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}

resource "helm_release" "cloudwatch_exporter" {
  name       = "cloudwatch-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-cloudwatch-exporter"
  namespace  = "monitoring"
  version    = "0.25.3"

  values = [
    file("${path.module}/../k8s/monitoring/cloudwatch-exporter-values.yaml")
  ]

  depends_on = [
    helm_release.kube_prometheus_stack
  ]
}

# IAM role for CloudWatch Exporter
resource "aws_iam_role" "cloudwatch_exporter" {
  name = "${local.cluster_name}-cloudwatch-exporter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = {
    Name        = "${local.cluster_name}-cloudwatch-exporter-role"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "cloudwatch_exporter" {
  name = "cloudwatch-read-access"
  role = aws_iam_role.cloudwatch_exporter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "tag:GetResources",
          "rds:DescribeDBInstances",
          "dynamodb:DescribeTable",
          "dynamodb:ListTables",
          "s3:ListAllMyBuckets",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Pod Identity association for CloudWatch Exporter
resource "aws_eks_pod_identity_association" "cloudwatch_exporter" {
  cluster_name    = local.cluster_name
  namespace       = "monitoring"
  service_account = "cloudwatch-exporter"
  role_arn        = aws_iam_role.cloudwatch_exporter.arn

  depends_on = [helm_release.cloudwatch_exporter]
}

# Output Grafana credentials
output "grafana_url" {
  description = "Grafana URL"
  value       = "https://grafana.${var.domain_name}"
}

output "grafana_admin_password_command" {
  description = "Command to retrieve Grafana admin password"
  value       = "kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d"
}
