locals {
  base_tags = var.tags
  az_names  = data.aws_availability_zones.available.names

  public_subnets = {
    for idx, subnet in var.public_subnets :
    coalesce(try(subnet.name_suffix, null), format("%03d", idx)) => merge(
      subnet,
      {
        availability_zone = coalesce(try(subnet.availability_zone, null), element(local.az_names, idx))
        name_suffix       = try(subnet.name_suffix, null)
      }
    )
  }

  private_subnets = {
    for idx, subnet in var.private_subnets :
    coalesce(try(subnet.name_suffix, null), format("%03d", idx)) => merge(
      subnet,
      {
        availability_zone = coalesce(try(subnet.availability_zone, null), element(local.az_names, idx))
        name_suffix       = try(subnet.name_suffix, null)
      }
    )
  }
}

locals {
  public_subnet_keys     = sort(keys(local.public_subnets))
  nat_gateway_subnet_key = length(local.public_subnet_keys) > 0 ? local.public_subnet_keys[0] : null
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.base_tags, { Name = var.vpc_name })
}

resource "aws_subnet" "public" {
  for_each                                    = local.public_subnets
  vpc_id                                      = aws_vpc.main.id
  cidr_block                                  = each.value.cidr
  availability_zone                           = each.value.availability_zone
  map_public_ip_on_launch                     = true
  enable_resource_name_dns_a_record_on_launch = true

  tags = merge(
    local.base_tags,
    {
      Name                     = "${var.vpc_name}-public-${coalesce(each.value.name_suffix, each.key)}"
      "kubernetes.io/role/elb" = "1"
    }
  )
}

resource "aws_subnet" "private" {
  for_each          = local.private_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.availability_zone

  tags = merge(
    local.base_tags,
    {
      Name                              = "${var.vpc_name}-private-${coalesce(each.value.name_suffix, each.key)}"
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.base_tags, { Name = "${var.vpc_name}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.base_tags, { Name = "${var.vpc_name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.base_tags, { Name = "${var.vpc_name}-nat-gw-eip" })
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[local.nat_gateway_subnet_key].id

  tags = merge(local.base_tags, { Name = "${var.vpc_name}-nat-gw" })
}

resource "aws_route_table" "private" {
  for_each = var.enable_nat_gateway ? local.private_subnets : {}
  vpc_id   = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = merge(
    local.base_tags,
    { Name = "${var.vpc_name}-private-rt-${coalesce(each.value.name_suffix, each.key)}" }
  )
}

resource "aws_route_table_association" "private" {
  for_each       = var.enable_nat_gateway ? aws_subnet.private : {}
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"

  tags = merge(local.base_tags, { Name = "${var.vpc_name}-vpce-s3" })
}

resource "aws_vpc_endpoint_route_table_association" "private_s3" {
  for_each        = var.enable_nat_gateway ? aws_route_table.private : {}
  route_table_id  = each.value.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_vpc_endpoint_route_table_association" "public_s3" {
  route_table_id  = aws_route_table.public.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_security_group" "main" {
  name        = "${var.vpc_name}-sg"
  description = "Default security group allowing communication within VPC and egress"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.sg_ingress_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.sg_egress_cidr_blocks
  }

  tags = merge(local.base_tags, { Name = "${var.vpc_name}-sg" })
}
