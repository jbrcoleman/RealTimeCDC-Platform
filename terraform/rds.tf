resource "random_password" "db_master_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_master_password" {
  name                    = "${local.name}-db-master-password"
  recovery_window_in_days = 0 

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_master_password" {
  secret_id     = aws_secretsmanager_secret.db_master_password.id
  secret_string = random_password.db_master_password.result
}

# Security group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for RDS PostgreSQL instance"

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.name}-rds"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(
    local.tags,
    {
      Name = "${local.name}-db-subnet-group"
    }
  )
}

# Parameter group for PostgreSQL with logical replication enabled
resource "aws_db_parameter_group" "postgres_cdc" {
  name_prefix = "${local.name}-postgres-cdc-"
  family      = "postgres16"
  description = "PostgreSQL parameter group for CDC with logical replication"

  # Enable logical replication for Debezium
  # Note: rds.logical_replication is a static parameter that requires instance reboot
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_replication_slots"
    value        = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_wal_senders"
    value        = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "wal_sender_timeout"
    value = "0"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

# RDS PostgreSQL instance
resource "aws_db_instance" "postgres" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t3.micro" 

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "ecommerce"
  username = "dbadmin"
  password = random_password.db_master_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres_cdc.name

  publicly_accessible = false
  skip_final_snapshot = true # Set to false for production

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection = false # Set to true for production

  tags = merge(
    local.tags,
    {
      Name = "${local.name}-postgres"
    }
  )
}

# Store connection info in Secrets Manager for easy access
resource "aws_secretsmanager_secret" "db_connection" {
  name                    = "${local.name}-db-connection"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_connection" {
  secret_id = aws_secretsmanager_secret.db_connection.id
  secret_string = jsonencode({
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    database = aws_db_instance.postgres.db_name
    username = aws_db_instance.postgres.username
    password = random_password.db_master_password.result
    endpoint = aws_db_instance.postgres.endpoint
  })
}