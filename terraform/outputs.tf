output "hub_vpc_id" {
  description = "The ID of the Hub VPC."
  value       = var.enable_hub ? module.vpc_hub[0].vpc_id : null
}

output "hub_vpc_cidr" {
  description = "The CIDR block of the Hub VPC."
  value       = var.enable_hub ? module.vpc_hub[0].vpc_cidr : null
}

output "dev_vpc_id" {
  description = "The ID of the Dev VPC."
  value       = var.enable_dev ? module.vpc_dev[0].vpc_id : null
}

output "dev_vpc_cidr" {
  description = "The CIDR block of the Dev VPC."
  value       = var.enable_dev ? module.vpc_dev[0].vpc_cidr : null
}

output "vpc_peering_id" {
  description = "The ID of the VPC Peering connection between Hub and Dev."
  value       = var.enable_hub && var.enable_dev ? aws_vpc_peering_connection.hub_dev[0].id : null
}

output "hub_network" {
  description = "Subnet IDs and CIDRs for OpenShift Hub Cluster."
  value = var.enable_hub ? {
    vpc_id            = module.vpc_hub[0].vpc_id
    network_cidr      = module.vpc_hub[0].vpc_cidr
    public_subnet_id  = module.vpc_hub[0].public_subnet_ids[0]
    public_cidr       = var.hub_public_subnets[0].cidr
    private_subnet_id = module.vpc_hub[0].private_subnet_ids[0]
    private_cidr      = var.hub_private_subnets[0].cidr
    az                = var.hub_private_subnets[0].availability_zone
  } : null
}

output "dev_network" {
  description = "Subnet IDs and CIDRs for OpenShift Dev Cluster."
  value = var.enable_dev ? {
    vpc_id            = module.vpc_dev[0].vpc_id
    network_cidr      = module.vpc_dev[0].vpc_cidr
    public_subnet_id  = module.vpc_dev[0].public_subnet_ids[0]
    public_cidr       = var.dev_public_subnets[0].cidr
    private_subnet_id = module.vpc_dev[0].private_subnet_ids[0]
    private_cidr      = var.dev_private_subnets[0].cidr
    az                = var.dev_private_subnets[0].availability_zone
  } : null
}

# --- Bastion Hub Outputs ---
output "bastion_hub" {
  description = "Details for Hub Bastion EC2 instance."
  value = var.enable_hub ? {
    instance_id = module.bastion_hub[0].instance_id
    public_ip   = module.bastion_hub[0].instance_public_ip
    private_ip  = module.bastion_hub[0].instance_private_ip
    ssh_command = "ssh -i ${var.bastion_public_key} ubuntu@${module.bastion_hub[0].instance_public_ip}"
  } : null
}

# --- Bastion Dev Outputs ---
output "bastion_dev" {
  description = "Details for Dev Bastion EC2 instance."
  value = var.enable_dev ? {
    instance_id = module.bastion_dev[0].instance_id
    public_ip   = module.bastion_dev[0].instance_public_ip
    private_ip  = module.bastion_dev[0].instance_private_ip
    ssh_command = "ssh -i ${var.bastion_public_key} ubuntu@${module.bastion_dev[0].instance_public_ip}"
  } : null
}

output "openshift_hub_install_config_snippet" {
  description = "Snippet to place in hub/install-config.yaml"
  value = var.enable_hub ? (<<-YAML
    networking:
      machineNetwork:
        - cidr: ${module.vpc_hub[0].vpc_cidr}
    platform:
      aws:
        region: ${var.region}
        vpc:
          subnets:
            - id: ${module.vpc_hub[0].public_subnet_ids[0]}
            - id: ${module.vpc_hub[0].private_subnet_ids[0]}
  YAML
  ) : null
}

output "openshift_dev_install_config_snippet" {
  description = "Snippet to place in dev/install-config.yaml"
  value = var.enable_dev ? (<<-YAML
    networking:
      machineNetwork:
        - cidr: ${module.vpc_dev[0].vpc_cidr}
    platform:
      aws:
        region: ${var.region}
        vpc:
          subnets:
            - id: ${module.vpc_dev[0].public_subnet_ids[0]}
            - id: ${module.vpc_dev[0].private_subnet_ids[0]}
  YAML
  ) : null
}


#output "public_zone_ids" {
#  description = "Map of public Route53 zone name to hosted zone ID."
#  value       = { for name, zone in aws_route53_zone.public : name => zone.zone_id }
#}
#
#output "public_zone_name_servers" {
#  description = "Map of public Route53 zone name to its name servers (delegation NS records)."
#  value       = { for name, zone in aws_route53_zone.public : name => zone.name_servers }
#}

