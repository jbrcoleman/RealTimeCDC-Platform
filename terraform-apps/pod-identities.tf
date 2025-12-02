# Pod identities reference resources from terraform-infra via remote state
# See data.tf for local variable definitions

module "kafka_connect_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-kafka-connect"

  additional_policy_arns = {
    kafka_connect = aws_iam_policy.kafka_connect.arn
  }

  associations = {
    kafka_connect = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.kafka.metadata[0].name
      service_account = kubernetes_service_account.kafka_connect.metadata[0].name
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "kafka_connect" {
  name        = "${local.name}-kafka-connect-policy"
  description = "Policy for Kafka Connect to access S3, Secrets Manager, and ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          local.data_lake_bucket_arn,
          local.dlq_bucket_arn,
          local.kafka_connect_storage_bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${local.data_lake_bucket_arn}/*",
          "${local.dlq_bucket_arn}/*",
          "${local.kafka_connect_storage_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = compact([
          local.db_connection_secret_arn,
          local.rds_master_secret_arn
        ])
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

################################################################################
# Debezium Service Account IAM Role
# Allows Debezium pods to read RDS credentials from Secrets Manager
################################################################################

module "debezium_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-debezium"

  additional_policy_arns = {
    debezium = aws_iam_policy.debezium.arn
  }

  associations = {
    debezium = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.kafka.metadata[0].name
      service_account = kubernetes_service_account.debezium.metadata[0].name
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "debezium" {
  name        = "${local.name}-debezium-policy"
  description = "Policy for Debezium to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = compact([
          local.db_connection_secret_arn,
          local.rds_master_secret_arn
        ])
      }
    ]
  })

  tags = local.tags
}

################################################################################
# CDC Consumer Applications IAM Role
# For custom Python consumer services that process CDC events
################################################################################

module "cdc_consumer_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-cdc-consumer"

  additional_policy_arns = {
    cdc_consumer = aws_iam_policy.cdc_consumer.arn
  }

  associations = {
    inventory_service = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.consumers.metadata[0].name
      service_account = kubernetes_service_account.inventory_service.metadata[0].name
    }
    analytics_service = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.consumers.metadata[0].name
      service_account = kubernetes_service_account.analytics_service.metadata[0].name
    }
    search_indexer = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.consumers.metadata[0].name
      service_account = kubernetes_service_account.search_indexer.metadata[0].name
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "cdc_consumer" {
  name        = "${local.name}-cdc-consumer-policy"
  description = "Policy for CDC consumer applications"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          local.data_lake_bucket_arn,
          local.dlq_bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject"
        ]
        Resource = [
          "${local.data_lake_bucket_arn}/*",
          "${local.dlq_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable",
          "dynamodb:CreateTable",
          "dynamodb:ListTables"
        ]
        Resource = [
          "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.name}-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          local.db_connection_secret_arn
        ]
      }
    ]
  })

  tags = local.tags
}

################################################################################
# Flink Service Account IAM Role (if using Flink for stream processing)
################################################################################

module "flink_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-flink"

  additional_policy_arns = {
    flink = aws_iam_policy.flink.arn
  }

  associations = {
    jobmanager = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.flink.metadata[0].name
      service_account = kubernetes_service_account.flink_jobmanager.metadata[0].name
    }
    taskmanager = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.flink.metadata[0].name
      service_account = kubernetes_service_account.flink_taskmanager.metadata[0].name
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "flink" {
  name        = "${local.name}-flink-policy"
  description = "Policy for Flink stream processing jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          local.data_lake_bucket_arn,
          local.kafka_connect_storage_bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${local.data_lake_bucket_arn}/*",
          "${local.kafka_connect_storage_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "${local.name}-flink"
          }
        }
      }
    ]
  })

  tags = local.tags
}

################################################################################
# Schema Registry Service Account IAM Role
################################################################################

module "schema_registry_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-schema-registry"

  additional_policy_arns = {
    schema_registry = aws_iam_policy.schema_registry.arn
  }

  associations = {
    schema_registry = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.kafka.metadata[0].name
      service_account = kubernetes_service_account.schema_registry.metadata[0].name
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "schema_registry" {
  name        = "${local.name}-schema-registry-policy"
  description = "Policy for Schema Registry to store schemas in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          local.kafka_connect_storage_bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${local.kafka_connect_storage_bucket_arn}/schemas/*"
        ]
      }
    ]
  })

  tags = local.tags
}

################################################################################
# External Secrets Operator IAM Role (optional but recommended)
# Allows ESO to sync secrets from AWS Secrets Manager to K8s secrets
################################################################################

module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-external-secrets"

  additional_policy_arns = {
    external_secrets = aws_iam_policy.external_secrets.arn
  }

  associations = {
    external_secrets = {
      cluster_name    = local.cluster_name
      namespace       = kubernetes_namespace.external_secrets.metadata[0].name
      service_account = kubernetes_service_account.external_secrets.metadata[0].name
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "external_secrets" {
  name        = "${local.name}-external-secrets-policy"
  description = "Policy for External Secrets Operator"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = compact([
          local.db_connection_secret_arn,
          local.rds_master_secret_arn
        ])
      }
    ]
  })

  tags = local.tags
}

################################################################################
# EBS CSI Driver Service Account IAM Role
# NOTE: Moved to terraform-infra workspace to ensure it's created before the addon
################################################################################