resource "aws_instance" "nomad_cluster" {
  count = var.server_count

  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.public_subnet_id

  vpc_security_group_ids      = [var.cluster_security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.nomad_cluster.name
  associate_public_ip_address = true

  key_name = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data = templatefile("${path.module}/user-data.tftpl", {
    cluster_name = var.retry_join.tag_value
    server_count = var.server_count
    region       = var.aws_region
    kms_key_id   = var.kms_key_id
  })

  tags = {
    Name                        = "${local.name_prefix}-node-${count.index + 1}"
    "${var.retry_join.tag_key}" = var.retry_join.tag_value
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true

    tags = {
      Name = "${local.name_prefix}-node-${count.index + 1}-root"
    }
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
