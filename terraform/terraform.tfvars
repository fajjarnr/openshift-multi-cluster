region      = "ap-southeast-1"
name_prefix = "ocp-lab"
environment = "nonprod"

# ==============================================================================
# Feature Flags / Toggles
# Set enable_dev = false jika ingin deploy infra Hub terlebih dahulu.
# Ubah enable_dev = true saat siap deploy Development cluster & VPC Peering.
# ==============================================================================
enable_hub = true
enable_dev = false

# ==========================================
# 1. Hub Cluster VPC (10.137.230.0/25)
# ==========================================
hub_vpc_cidr = "10.137.230.0/25"

hub_public_subnets = [
  {
    cidr              = "10.137.230.0/26"
    availability_zone = "ap-southeast-1a"
    name_suffix       = "hub"
  }
]

hub_private_subnets = [
  {
    cidr              = "10.137.230.64/26"
    availability_zone = "ap-southeast-1a"
    name_suffix       = "hub"
  }
]

# ==========================================
# 2. Development Cluster VPC (10.137.230.128/25)
# ==========================================
dev_vpc_cidr = "10.137.230.128/25"

dev_public_subnets = [
  {
    cidr              = "10.137.230.128/26"
    availability_zone = "ap-southeast-1a"
    name_suffix       = "dev"
  }
]

dev_private_subnets = [
  {
    cidr              = "10.137.230.192/26"
    availability_zone = "ap-southeast-1a"
    name_suffix       = "dev"
  }
]

# ==========================================
# 3. Bastion Hosts (Hub & Dev)
# ==========================================
bastion_public_key       = "~/.ssh/id_ed25519.pub"
bastion_instance_type    = "t3.large"
bastion_os_name          = "ubuntu"
bastion_root_volume_size = 100

default_tags = {
  Project     = "multi-cluster"
  Environment = "nonprod"
  ManagedBy   = "terraform"
}

# ==========================================
# 4. Route53 Public Hosted Zones
# ==========================================
public_hosted_zones = [
  "ocp.fajjjar.my.id"
]

