resource "aws_security_group" "nomad_cluster" {
  name        = "${local.name_prefix}-cluster-sg"
  description = "Nomad/Consul/Vault cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "SSH from allowed IP"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  ingress {
    from_port   = 4646
    to_port     = 4648
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "Nomad from allowed IP"
  }

  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "Vault from allowed IP"
  }

  ingress {
    from_port   = 8500
    to_port     = 8502
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "Consul UI/gRPC from allowed IP"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Cluster internal"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${local.name_prefix}-cluster-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.nomad_cluster.id]
    description     = "MySQL from cluster only"
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}
