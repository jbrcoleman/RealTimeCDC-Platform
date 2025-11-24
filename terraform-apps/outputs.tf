output "kafka_namespace" {
  description = "Kafka namespace"
  value       = kubernetes_namespace.kafka.metadata[0].name
}

output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_initial_password_command" {
  description = "Command to retrieve ArgoCD initial admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_url" {
  description = "ArgoCD URL"
  value       = "https://argocd.${var.domain_name}"
}

output "flink_url" {
  description = "Flink JobManager UI URL"
  value       = "https://flink.${var.domain_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = try(data.kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, "Waiting for ALB creation...")
}
