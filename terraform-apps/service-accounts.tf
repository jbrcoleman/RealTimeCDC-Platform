# Service Accounts for Pod Identity associations

# Kafka Service Accounts
resource "kubernetes_service_account" "kafka_connect" {
  metadata {
    name      = "kafka-connect"
    namespace = kubernetes_namespace.kafka.metadata[0].name
  }
}

resource "kubernetes_service_account" "debezium" {
  metadata {
    name      = "debezium"
    namespace = kubernetes_namespace.kafka.metadata[0].name
  }
}

resource "kubernetes_service_account" "schema_registry" {
  metadata {
    name      = "schema-registry"
    namespace = kubernetes_namespace.kafka.metadata[0].name
  }
}

# CDC Consumer Service Accounts
resource "kubernetes_service_account" "inventory_service" {
  metadata {
    name      = "inventory-service"
    namespace = kubernetes_namespace.consumers.metadata[0].name
  }
}

resource "kubernetes_service_account" "analytics_service" {
  metadata {
    name      = "analytics-service"
    namespace = kubernetes_namespace.consumers.metadata[0].name
  }
}

resource "kubernetes_service_account" "search_indexer" {
  metadata {
    name      = "search-indexer"
    namespace = kubernetes_namespace.consumers.metadata[0].name
  }
}

# Flink Service Accounts
resource "kubernetes_service_account" "flink_jobmanager" {
  metadata {
    name      = "flink-jobmanager"
    namespace = kubernetes_namespace.flink.metadata[0].name
  }
}

resource "kubernetes_service_account" "flink_taskmanager" {
  metadata {
    name      = "flink-taskmanager"
    namespace = kubernetes_namespace.flink.metadata[0].name
  }
}

# External Secrets Operator Service Account
resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      name = "external-secrets"
    }
  }
}

resource "kubernetes_service_account" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
  }
}
