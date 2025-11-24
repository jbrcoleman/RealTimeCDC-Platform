# Strimzi Kafka Operator
# Strimzi 0.48.0+ fully supports Kubernetes 1.33
# The K8s 1.33 compatibility issue was fixed in Strimzi 0.47.0 (PR #11392)
resource "helm_release" "strimzi_operator" {
  name       = "strimzi-operator"
  repository = "https://strimzi.io/charts/"
  chart      = "strimzi-kafka-operator"
  version    = var.strimzi_version
  namespace  = kubernetes_namespace.kafka.metadata[0].name

  create_namespace = false
  atomic           = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      resources = {
        limits = {
          memory = "512Mi"
          cpu    = "500m"
        }
        requests = {
          memory = "256Mi"
          cpu    = "100m"
        }
      }
      logLevel = "INFO"

      # Kafka version configurations
      # Supports Kafka 4.1.0 (defined in ArgoCD manifests)
      watchNamespaces = [kubernetes_namespace.kafka.metadata[0].name]

      # Feature gates for KRaft mode (no ZooKeeper)
      featureGates = "+UseKRaft,+KafkaNodePools"
    })
  ]

  depends_on = [
    kubectl_manifest.karpenter_nodepool_default
  ]
}
