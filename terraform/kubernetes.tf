################################################################################
# Kubernetes Namespaces
################################################################################

resource "kubernetes_namespace" "kafka" {
  metadata {
    name = "kafka"
    labels = {
      name                              = "kafka"
      "app.kubernetes.io/name"          = "kafka"
      "app.kubernetes.io/part-of"       = "cdc-platform"
    }
  }
}

resource "kubernetes_namespace" "cdc_consumers" {
  metadata {
    name = "cdc-consumers"
    labels = {
      name                              = "cdc-consumers"
      "app.kubernetes.io/name"          = "cdc-consumers"
      "app.kubernetes.io/part-of"       = "cdc-platform"
    }
  }
}

resource "kubernetes_namespace" "flink" {
  metadata {
    name = "flink"
    labels = {
      name                              = "flink"
      "app.kubernetes.io/name"          = "flink"
      "app.kubernetes.io/part-of"       = "cdc-platform"
    }
  }
}

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      name                              = "external-secrets"
      "app.kubernetes.io/name"          = "external-secrets"
      "app.kubernetes.io/part-of"       = "cdc-platform"
    }
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      name                              = "monitoring"
      "app.kubernetes.io/name"          = "monitoring"
      "app.kubernetes.io/part-of"       = "cdc-platform"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name                              = "argocd"
      "app.kubernetes.io/name"          = "argocd"
      "app.kubernetes.io/part-of"       = "cdc-platform"
    }
  }
}

################################################################################
# Kafka Namespace Service Accounts
################################################################################

resource "kubernetes_service_account" "kafka_connect" {
  metadata {
    name      = "kafka-connect"
    namespace = kubernetes_namespace.kafka.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "kafka-connect"
      "app.kubernetes.io/component" = "kafka-connect"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}

resource "kubernetes_service_account" "debezium" {
  metadata {
    name      = "debezium"
    namespace = kubernetes_namespace.kafka.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "debezium"
      "app.kubernetes.io/component" = "cdc-connector"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}

resource "kubernetes_service_account" "schema_registry" {
  metadata {
    name      = "schema-registry"
    namespace = kubernetes_namespace.kafka.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "schema-registry"
      "app.kubernetes.io/component" = "schema-registry"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}

################################################################################
# CDC Consumers Namespace Service Accounts
################################################################################

resource "kubernetes_service_account" "inventory_service" {
  metadata {
    name      = "inventory-service"
    namespace = kubernetes_namespace.cdc_consumers.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "inventory-service"
      "app.kubernetes.io/component" = "consumer"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}

resource "kubernetes_service_account" "analytics_service" {
  metadata {
    name      = "analytics-service"
    namespace = kubernetes_namespace.cdc_consumers.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "analytics-service"
      "app.kubernetes.io/component" = "consumer"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}

resource "kubernetes_service_account" "search_indexer" {
  metadata {
    name      = "search-indexer"
    namespace = kubernetes_namespace.cdc_consumers.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "search-indexer"
      "app.kubernetes.io/component" = "consumer"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}

################################################################################
# Flink Namespace Service Accounts
################################################################################

resource "kubernetes_service_account" "flink_jobmanager" {
  metadata {
    name      = "flink-jobmanager"
    namespace = kubernetes_namespace.flink.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "flink"
      "app.kubernetes.io/component" = "jobmanager"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}

resource "kubernetes_service_account" "flink_taskmanager" {
  metadata {
    name      = "flink-taskmanager"
    namespace = kubernetes_namespace.flink.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "flink"
      "app.kubernetes.io/component" = "taskmanager"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}

################################################################################
# External Secrets Namespace Service Accounts
################################################################################

resource "kubernetes_service_account" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "external-secrets"
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/part-of"   = "cdc-platform"
    }
  }
}
