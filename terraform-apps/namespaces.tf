# Kafka namespace
resource "kubernetes_namespace" "kafka" {
  metadata {
    name = "kafka"
    labels = {
      name = "kafka"
    }
  }
}

# ArgoCD namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name = "argocd"
    }
  }
}

# Flink namespace
resource "kubernetes_namespace" "flink" {
  metadata {
    name = "flink"
    labels = {
      name = "flink"
    }
  }
}

# Consumers namespace
resource "kubernetes_namespace" "consumers" {
  metadata {
    name = "consumers"
    labels = {
      name = "consumers"
    }
  }
}
