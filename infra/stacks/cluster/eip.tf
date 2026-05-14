resource "aws_eip" "nomad_cluster" {
  count  = var.server_count
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-node-${count.index + 1}"
  }
}

resource "aws_eip_association" "nomad_cluster" {
  count         = var.server_count
  instance_id   = aws_instance.nomad_cluster[count.index].id
  allocation_id = aws_eip.nomad_cluster[count.index].id
}
