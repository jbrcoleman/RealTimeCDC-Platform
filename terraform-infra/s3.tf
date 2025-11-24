# Main data lake bucket for CDC events
resource "aws_s3_bucket" "cdc_data_lake" {
  bucket = "${local.name}-data-lake-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.tags,
    {
      Name        = "${local.name}-data-lake"
      Purpose     = "CDC events storage"
      DataClass   = "operational"
    }
  )
}

# Enable versioning for data protection
resource "aws_s3_bucket_versioning" "cdc_data_lake" {
  bucket = aws_s3_bucket.cdc_data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cdc_data_lake" {
  bucket = aws_s3_bucket.cdc_data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "cdc_data_lake" {
  bucket = aws_s3_bucket.cdc_data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "cdc_data_lake" {
  bucket = aws_s3_bucket.cdc_data_lake.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER_IR"
    }
  }

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Intelligent tiering for automated cost optimization
resource "aws_s3_bucket_intelligent_tiering_configuration" "cdc_data_lake" {
  bucket = aws_s3_bucket.cdc_data_lake.id
  name   = "EntireDataLake"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 180
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 365
  }
}

// S3 Bucket for dlq events
resource "aws_s3_bucket" "cdc_dlq" {
  bucket = "${local.name}-dlq-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.tags,
    {
      Name    = "${local.name}-dlq"
      Purpose = "Dead letter queue for failed CDC events"
    }
  )
}

resource "aws_s3_bucket_versioning" "cdc_dlq" {
  bucket = aws_s3_bucket.cdc_dlq.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cdc_dlq" {
  bucket = aws_s3_bucket.cdc_dlq.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cdc_dlq" {
  bucket = aws_s3_bucket.cdc_dlq.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire DLQ objects after 30 days (adjust as needed)
resource "aws_s3_bucket_lifecycle_configuration" "cdc_dlq" {
  bucket = aws_s3_bucket.cdc_dlq.id

  rule {
    id     = "expire-old-dlq-events"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

// S3 Bucket for kafka Connect Offsets
resource "aws_s3_bucket" "kafka_connect_storage" {
  bucket = "${local.name}-kafka-connect-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.tags,
    {
      Name    = "${local.name}-kafka-connect"
      Purpose = "Kafka Connect offsets and configuration"
    }
  )
}

resource "aws_s3_bucket_versioning" "kafka_connect_storage" {
  bucket = aws_s3_bucket.kafka_connect_storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kafka_connect_storage" {
  bucket = aws_s3_bucket.kafka_connect_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "kafka_connect_storage" {
  bucket = aws_s3_bucket.kafka_connect_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}