locals {
  ami_arch = var.instance_architecture == "arm64" ? "arm64" : "x86_64"

  ubuntu_name_pattern = (
    var.instance_architecture == "arm64"
    ? "ubuntu/images/hvm-ssd-gp3/ubuntu-*-2*-arm64-server-*"
    : "ubuntu/images/hvm-ssd-gp3/ubuntu-*-2*-amd64-server-*"
  )

  al2023_name_pattern = (
    var.instance_architecture == "arm64"
    ? "al2023-ami-2023.*-arm64"
    : "al2023-ami-2023.*-x86_64"
  )

  rhel9_name_pattern = (
    var.instance_architecture == "arm64"
    ? "RHEL-9.*_HVM-*-ARM64-*-Hourly2-GP3"
    : "RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP3"
  )
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = [local.ubuntu_name_pattern]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = [local.ami_arch]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [local.al2023_name_pattern]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = [local.ami_arch]
  }
}

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = [local.rhel9_name_pattern]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = [local.ami_arch]
  }
}
