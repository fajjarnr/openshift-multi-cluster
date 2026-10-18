variable "region" {
  description = "The AWS region to create resources in."
  type        = string
  default     = "ap-southeast-1"
}

variable "name_prefix" {
  description = "Project or team identifier used as the leading portion for all resource names."
  type        = string
  default     = "ocp-lab"
}

variable "environment" {
  description = "Environment identifier (e.g. acm, dev, hub)."
  type        = string
  default     = "nonprod"
}

# ==========================================
# Deployment Feature Flags / Toggles
# ==========================================
variable "enable_hub" {
  description = "Toggle to enable/disable Hub VPC and Bastion (set to true to deploy Hub)."
  type        = bool
  default     = true
}

variable "enable_dev" {
  description = "Toggle to enable/disable Dev VPC and Bastion (set to false to deploy Hub first)."
  type        = bool
  default     = true
}

# --- Hub VPC Network (10.137.230.0/25 - 128 IP) ---
variable "hub_vpc_cidr" {
  description = "The CIDR block for the Hub Cluster VPC."
  type        = string
  default     = "10.137.230.0/25"

  validation {
    condition     = can(cidrnetmask(var.hub_vpc_cidr))
    error_message = "hub_vpc_cidr must be a valid CIDR block."
  }
}

variable "hub_public_subnets" {
  description = "Public subnets for Hub VPC (External Ingress / Load Balancers)."
  type = list(object({
    cidr              = string
    availability_zone = optional(string)
    name_suffix       = optional(string)
  }))
  default = [
    {
      cidr              = "10.137.230.0/26"
      availability_zone = "ap-southeast-1a"
      name_suffix       = "hub"
    }
  ]
}

variable "hub_private_subnets" {
  description = "Private subnets for Hub VPC (59 usable IPs, accommodates 20 VMs)."
  type = list(object({
    cidr              = string
    availability_zone = optional(string)
    name_suffix       = optional(string)
  }))
  default = [
    {
      cidr              = "10.137.230.64/26"
      availability_zone = "ap-southeast-1a"
      name_suffix       = "hub"
    }
  ]
}

# --- Dev VPC Network (10.137.230.128/25 - 128 IP) ---
variable "dev_vpc_cidr" {
  description = "The CIDR block for the Dev Cluster VPC."
  type        = string
  default     = "10.137.230.128/25"

  validation {
    condition     = can(cidrnetmask(var.dev_vpc_cidr))
    error_message = "dev_vpc_cidr must be a valid CIDR block."
  }
}

variable "dev_public_subnets" {
  description = "Public subnets for Dev VPC (External Ingress + Bastion Host)."
  type = list(object({
    cidr              = string
    availability_zone = optional(string)
    name_suffix       = optional(string)
  }))
  default = [
    {
      cidr              = "10.137.230.128/26"
      availability_zone = "ap-southeast-1a"
      name_suffix       = "dev"
    }
  ]
}

variable "dev_private_subnets" {
  description = "Private subnets for Dev VPC (59 usable IPs, accommodates 20 VMs)."
  type = list(object({
    cidr              = string
    availability_zone = optional(string)
    name_suffix       = optional(string)
  }))
  default = [
    {
      cidr              = "10.137.230.192/26"
      availability_zone = "ap-southeast-1a"
      name_suffix       = "dev"
    }
  ]
}

# --- Bastion Host Configurations ---
variable "bastion_public_key" {
  description = "The public key file or string for the bastion hosts."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the Bastion jumpboxes."
  type        = string
  default     = "t3.large"
}

variable "bastion_os_name" {
  description = "OS for bastion (ubuntu, amazon_linux, rhel9)."
  type        = string
  default     = "ubuntu"
}

variable "bastion_root_volume_size" {
  description = "Root disk size in GB for the bastion host."
  type        = number
  default     = 100
}

variable "default_tags" {
  description = "Default tags to apply to all supported AWS resources."
  type        = map(string)
  default     = {}
}

variable "public_hosted_zones" {
  description = "Public Route53 hosted zones for OpenShift baseDomain."
  type        = list(string)
  default     = ["ocp.fajjjar.my.id"]
}

# --- ODF Local Volume Raw Disks (untuk LSO LocalVolumeSet) ---
variable "odf_local_disk_count" {
  description = "Number of EBS raw disks to create for ODF LocalVolumeSet (9 = 3 disks x 3 odf nodes)."
  type        = number
  default     = 9
}

variable "odf_local_disk_size" {
  description = "Size (GB) of each raw disk for ODF LocalVolumeSet."
  type        = number
  default     = 300
}

variable "odf_local_disk_type" {
  description = "EBS volume type for ODF raw disks (gp3 = SSD with default 3k IOPS / 125 MBps)."
  type        = string
  default     = "gp3"
}
