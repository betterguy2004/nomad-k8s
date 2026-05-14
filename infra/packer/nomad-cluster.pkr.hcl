packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = "ubuntu"
  ami_name      = "${var.ami_name_prefix}-{{timestamp}}"

  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      architecture        = "x86_64"
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  tags = {
    Name    = "${var.ami_name_prefix}-{{timestamp}}"
    Project = "nomad-k8s"
  }
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /ops",
      "sudo chmod 777 /ops"
    ]
  }

  provisioner "file" {
    source      = "../shared"
    destination = "/ops"
  }

  provisioner "shell" {
    script = "../shared/scripts/setup.sh"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
