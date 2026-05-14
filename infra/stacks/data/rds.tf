resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-rds-subnet-group"
  }
}

resource "aws_db_parameter_group" "mysql" {
  name   = "${local.name_prefix}-mysql80"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "${local.name_prefix}-mysql80"
  }
}

resource "aws_db_instance" "mysql" {
  identifier     = "${local.name_prefix}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "nomad"
  username = "admin"
  password = random_password.rds_master.result

  vpc_security_group_ids = [var.rds_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.mysql.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  skip_final_snapshot = true

  tags = {
    Name = "${local.name_prefix}-mysql"
  }
}

resource "aws_secretsmanager_secret" "rds_master" {
  name                    = "${local.name_prefix}/rds/master-password"
  recovery_window_in_days = 0

  tags = {
    Name = "${local.name_prefix}-rds-master"
  }
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id
  secret_string = jsonencode({
    username = aws_db_instance.mysql.username
    password = random_password.rds_master.result
    host     = aws_db_instance.mysql.address
    port     = aws_db_instance.mysql.port
    database = aws_db_instance.mysql.db_name
  })
}
