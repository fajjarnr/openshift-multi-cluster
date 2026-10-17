locals {
  bastion_key_material = try(file(pathexpand(var.bastion_public_key)), var.bastion_public_key)
  bastion_user_data    = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y unzip curl jq git tmux ca-certificates
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
  EOF
}

resource "aws_key_pair" "bastion_key" {
  count      = (var.enable_hub || var.enable_dev) && trimspace(local.bastion_key_material) != "" ? 1 : 0
  key_name   = "${local.resource_prefix}-bastion-key"
  public_key = trimspace(local.bastion_key_material)
}

# --- 1. Bastion Host for Hub Cluster ---
module "bastion_hub" {
  count  = var.enable_hub ? 1 : 0
  source = "./modules/ec2"

  instance_name               = local.names.bastion_hub
  instance_type               = var.bastion_instance_type
  os_name                     = var.bastion_os_name
  root_volume_size            = var.bastion_root_volume_size
  root_volume_type            = "gp3"
  key_name                    = length(aws_key_pair.bastion_key) > 0 ? aws_key_pair.bastion_key[0].key_name : ""
  subnet_id                   = module.vpc_hub[0].public_subnet_ids[0]
  vpc_security_group_ids      = [module.vpc_hub[0].security_group_id]
  associate_public_ip_address = true
  enable_ssm                  = true
  user_data                   = local.bastion_user_data
  tags                        = merge(local.common_tags, { Cluster = "hub", Role = "bastion" })

  depends_on = [module.vpc_hub]
}

# --- 2. Bastion Host for Development Cluster ---
module "bastion_dev" {
  count  = var.enable_dev ? 1 : 0
  source = "./modules/ec2"

  instance_name               = local.names.bastion_dev
  instance_type               = var.bastion_instance_type
  os_name                     = var.bastion_os_name
  root_volume_size            = var.bastion_root_volume_size
  root_volume_type            = "gp3"
  key_name                    = length(aws_key_pair.bastion_key) > 0 ? aws_key_pair.bastion_key[0].key_name : ""
  subnet_id                   = module.vpc_dev[0].public_subnet_ids[0]
  vpc_security_group_ids      = [module.vpc_dev[0].security_group_id]
  associate_public_ip_address = true
  enable_ssm                  = true
  user_data                   = local.bastion_user_data
  tags                        = merge(local.common_tags, { Cluster = "development", Role = "bastion" })

  depends_on = [module.vpc_dev]
}
