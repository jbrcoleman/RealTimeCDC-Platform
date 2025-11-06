locals {
  # RDS-managed secret ARN (null until RDS instance is created with manage_master_user_password)
  rds_master_secret_arn = length(aws_db_instance.postgres.master_user_secret) > 0 ? aws_db_instance.postgres.master_user_secret[0].secret_arn : ""
}

module "kafka_connect_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-kafka-connect"

  additional_policy_arns = {
    kafka_connect = aws_iam_policy.kafka_connect.arn
  }

  associations = {
    kafka_connect = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kafka"
      service_account = "kafka-connect"
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
        Resource = compact([
          aws_secretsmanager_secret.db_connection.arn,
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
      cluster_name    = module.eks.cluster_name
      namespace       = "kafka"
      service_account = "debezium"
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
          aws_secretsmanager_secret.db_connection.arn,
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
      cluster_name    = module.eks.cluster_name
      namespace       = "cdc-consumers"
      service_account = "inventory-service"
    }
    analytics_service = {
      cluster_name    = module.eks.cluster_name
      namespace       = "cdc-consumers"
      service_account = "analytics-service"
    }
    search_indexer = {
      cluster_name    = module.eks.cluster_name
      namespace       = "cdc-consumers"
      service_account = "search-indexer"
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
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable",
          "dynamodb:CreateTable",
          "dynamodb:ListTables"
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

module "flink_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-flink"

  additional_policy_arns = {
    flink = aws_iam_policy.flink.arn
  }

  associations = {
    jobmanager = {
      cluster_name    = module.eks.cluster_name
      namespace       = "flink"
      service_account = "flink-jobmanager"
    }
    taskmanager = {
      cluster_name    = module.eks.cluster_name
      namespace       = "flink"
      service_account = "flink-taskmanager"
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

module "schema_registry_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-schema-registry"

  additional_policy_arns = {
    schema_registry = aws_iam_policy.schema_registry.arn
  }

  associations = {
    schema_registry = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kafka"
      service_account = "schema-registry"
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

module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-external-secrets"

  additional_policy_arns = {
    external_secrets = aws_iam_policy.external_secrets.arn
  }

  associations = {
    external_secrets = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
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
          aws_secretsmanager_secret.db_connection.arn,
          local.rds_master_secret_arn
        ])
      }
    ]
  })

  tags = local.tags
}

################################################################################
# EBS CSI Driver Service Account IAM Role
# Required for EBS volumes provisioning in EKS
################################################################################

module "ebs_csi_driver_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "${local.name}-ebs-csi-driver"

  additional_policy_arns = {
    ebs_csi_driver = aws_iam_policy.ebs_csi_driver.arn
  }

  associations = {
    ebs_csi_controller = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "ebs_csi_driver" {
  name        = "${local.name}-ebs-csi-driver-policy"
  description = "Policy for EBS CSI Driver to manage EBS volumes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/CSIVolumeName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/CSIVolumeName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/kubernetes.io/created-for/pvc/name" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/CSIVolumeSnapshotName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      }
    ]
  })

  tags = local.tags
}