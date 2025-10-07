module "kafka_connect_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-kafka-connect"

  role_policy_arns = {
    policy = aws_iam_policy.kafka_connect.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kafka:kafka-connect"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "kafka_connect" {
  name        = "${local.name}-kafka-connect-policy"
  description = "Policy for Kafka Connect to access S3 and Secrets Manager"

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
          aws_s3_bucket.cdc_data_lake.arn,
          aws_s3_bucket.cdc_dlq.arn,
          aws_s3_bucket.kafka_connect_storage.arn
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
          "${aws_s3_bucket.cdc_data_lake.arn}/*",
          "${aws_s3_bucket.cdc_dlq.arn}/*",
          "${aws_s3_bucket.kafka_connect_storage.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.db_connection.arn,
          aws_secretsmanager_secret.db_master_password.arn
        ]
      }
    ]
  })

  tags = local.tags
}

################################################################################
# Debezium Service Account IAM Role
# Allows Debezium pods to read RDS credentials from Secrets Manager
################################################################################

module "debezium_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-debezium"

  role_policy_arns = {
    policy = aws_iam_policy.debezium.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kafka:debezium"]
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
        Resource = [
          aws_secretsmanager_secret.db_connection.arn,
          aws_secretsmanager_secret.db_master_password.arn
        ]
      }
    ]
  })

  tags = local.tags
}

################################################################################
# CDC Consumer Applications IAM Role
# For custom Python consumer services that process CDC events
################################################################################

module "cdc_consumer_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-cdc-consumer"

  role_policy_arns = {
    policy = aws_iam_policy.cdc_consumer.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "cdc-consumers:inventory-service",
        "cdc-consumers:analytics-service",
        "cdc-consumers:search-indexer"
      ]
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
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cdc_data_lake.arn,
          "${aws_s3_bucket.cdc_data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.cdc_dlq.arn}/*"
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
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${local.name}-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.db_connection.arn
        ]
      }
    ]
  })

  tags = local.tags
}

################################################################################
# Flink Service Account IAM Role (if using Flink for stream processing)
################################################################################

module "flink_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-flink"

  role_policy_arns = {
    policy = aws_iam_policy.flink.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "flink:flink-jobmanager",
        "flink:flink-taskmanager"
      ]
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
          aws_s3_bucket.cdc_data_lake.arn,
          aws_s3_bucket.kafka_connect_storage.arn
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
          "${aws_s3_bucket.cdc_data_lake.arn}/*",
          "${aws_s3_bucket.kafka_connect_storage.arn}/*"
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

module "schema_registry_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-schema-registry"

  role_policy_arns = {
    policy = aws_iam_policy.schema_registry.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kafka:schema-registry"]
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
          aws_s3_bucket.kafka_connect_storage.arn
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
          "${aws_s3_bucket.kafka_connect_storage.arn}/schemas/*"
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

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-external-secrets"

  role_policy_arns = {
    policy = aws_iam_policy.external_secrets.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
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
        Resource = [
          "${aws_secretsmanager_secret.db_connection.arn}",
          "${aws_secretsmanager_secret.db_master_password.arn}"
        ]
      }
    ]
  })

  tags = local.tags
}