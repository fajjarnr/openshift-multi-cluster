locals {
  resource_prefix = trimspace(var.environment) != "" ? "${var.name_prefix}-${var.environment}" : var.name_prefix

  names = {
    hub_vpc     = "${local.resource_prefix}-hub-vpc"
    dev_vpc     = "${local.resource_prefix}-dev-vpc"
    bastion_hub = "${local.resource_prefix}-hub-bastion"
    bastion_dev = "${local.resource_prefix}-dev-bastion"
  }

  common_tags = merge(
    var.default_tags,
    {
      Environment = var.environment
      NamePrefix  = var.name_prefix
      ManagedBy   = "terraform"
      Purpose     = "lab"
    }
  )
}
