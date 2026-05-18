# Persistent EBS volumes for Consul/Vault/Nomad data
# These volumes have delete_on_termination = false to persist across instance termination

resource "aws_ebs_volume" "data" {
  count = var.server_count

  # Use same AZ as the corresponding instance
  availability_zone = aws_instance.nomad_cluster[count.index].availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name    = "${local.name_prefix}-data-${count.index + 1}"
    Project = var.project
    Role    = "consul-vault-nomad-data"
  }

  # Create volume after instance so we know the AZ
  depends_on = [aws_instance.nomad_cluster]
}

resource "aws_volume_attachment" "data" {
  count = var.server_count

  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = aws_instance.nomad_cluster[count.index].id

  # Stop instance before detaching to prevent data corruption
  stop_instance_before_detaching = true
}
