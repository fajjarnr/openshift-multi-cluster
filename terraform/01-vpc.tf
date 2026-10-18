# --- 1. Hub Cluster VPC ---
module "vpc_hub" {
  count  = var.enable_hub ? 1 : 0
  source = "./modules/vpc"

  vpc_name        = local.names.hub_vpc
  vpc_cidr        = var.hub_vpc_cidr
  public_subnets  = var.hub_public_subnets
  private_subnets = var.hub_private_subnets
  region          = var.region
  tags            = merge(local.common_tags, { Cluster = "hub" })
}

# --- 2. Dev Cluster VPC ---
module "vpc_dev" {
  count  = var.enable_dev ? 1 : 0
  source = "./modules/vpc"

  vpc_name        = local.names.dev_vpc
  vpc_cidr        = var.dev_vpc_cidr
  public_subnets  = var.dev_public_subnets
  private_subnets = var.dev_private_subnets
  region          = var.region
  tags            = merge(local.common_tags, { Cluster = "dev" })
}

# --- 3. VPC Peering Connection (Hub <-> Dev) ---
# Active only if both Hub and Dev VPCs are enabled
resource "aws_vpc_peering_connection" "hub_dev" {
  count       = var.enable_hub && var.enable_dev ? 1 : 0
  vpc_id      = module.vpc_hub[0].vpc_id
  peer_vpc_id = module.vpc_dev[0].vpc_id
  auto_accept = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.resource_prefix}-hub-dev-peering"
    }
  )
}

resource "aws_vpc_peering_connection_options" "hub" {
  count                     = var.enable_hub && var.enable_dev ? 1 : 0
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_dev[0].id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_vpc_peering_connection_options" "dev" {
  count                     = var.enable_hub && var.enable_dev ? 1 : 0
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_dev[0].id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

# --- 4. Route Table Entries across VPC Peering ---
# Routes in Hub VPC pointing to Dev VPC CIDR
resource "aws_route" "hub_to_dev_private" {
  for_each                  = var.enable_hub && var.enable_dev ? module.vpc_hub[0].private_route_table_ids : {}
  route_table_id            = each.value
  destination_cidr_block    = module.vpc_dev[0].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_dev[0].id
}

resource "aws_route" "hub_to_dev_public" {
  count                     = var.enable_hub && var.enable_dev ? 1 : 0
  route_table_id            = module.vpc_hub[0].public_route_table_id
  destination_cidr_block    = module.vpc_dev[0].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_dev[0].id
}

# Routes in Dev VPC pointing to Hub VPC CIDR
resource "aws_route" "dev_to_hub_private" {
  for_each                  = var.enable_hub && var.enable_dev ? module.vpc_dev[0].private_route_table_ids : {}
  route_table_id            = each.value
  destination_cidr_block    = module.vpc_hub[0].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_dev[0].id
}

resource "aws_route" "dev_to_hub_public" {
  count                     = var.enable_hub && var.enable_dev ? 1 : 0
  route_table_id            = module.vpc_dev[0].public_route_table_id
  destination_cidr_block    = module.vpc_hub[0].vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_dev[0].id
}
