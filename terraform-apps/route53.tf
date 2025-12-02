# Assumes you have a hosted zone for democloud.click
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Get ELB hosted zone ID
data "aws_elb_hosted_zone_id" "main" {}

# Wait for ALB to be created
resource "time_sleep" "wait_for_alb" {
  create_duration = "120s"

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubectl_manifest.argocd_root_app
  ]
}

# Get ALB DNS name from Kubernetes Ingress (after ArgoCD creates it)
# Note: Both ArgoCD and Flink ingresses share the same ALB (group.name: shared-alb)
# so we only need to query one ingress to get the shared ALB hostname
data "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
  }

  depends_on = [time_sleep.wait_for_alb]
}

# Local value to extract ALB hostname
locals {
  alb_hostname = data.kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname
}

# ArgoCD DNS Record
resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "argocd.${var.domain_name}"
  type    = "A"

  alias {
    name                   = local.alb_hostname
    zone_id                = data.aws_elb_hosted_zone_id.main.id
    evaluate_target_health = true
  }

  depends_on = [data.kubernetes_ingress_v1.argocd]
}

# Flink DNS Record
# Uses the same ALB hostname since both ingresses share the same ALB
resource "aws_route53_record" "flink" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "flink.${var.domain_name}"
  type    = "A"

  alias {
    name                   = local.alb_hostname
    zone_id                = data.aws_elb_hosted_zone_id.main.id
    evaluate_target_health = true
  }

  depends_on = [data.kubernetes_ingress_v1.argocd]
}
