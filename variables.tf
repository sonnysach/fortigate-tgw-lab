##############################################################################
# variables.tf – Input variables
##############################################################################

# ── Feature Toggles ─────────────────────────────────────────────────────────
variable "deploy_fortigate" {
  description = "Set to false to skip FortiGate VM and TGW Connect resources (e.g. while waiting for BYOL license). All other infra still deploys."
  type        = bool
  default     = true
}

# ── Region ──────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# ── Availability Zones ──────────────────────────────────────────────────────
variable "az1" {
  description = "First availability zone"
  type        = string
  default     = "us-east-1a"
}

variable "az2" {
  description = "Second availability zone"
  type        = string
  default     = "us-east-1b"
}

# ── Access Control ──────────────────────────────────────────────────────────
variable "allowed_mgmt_cidrs" {
  description = "List of CIDRs allowed to reach FortiGate mgmt (HTTPS 8443, SSH 2222) and test EC2 SSH. Must be populated before apply."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.allowed_mgmt_cidrs) > 0
    error_message = "You must specify at least one CIDR in allowed_mgmt_cidrs (e.g. your public IP/32)."
  }
}

# ── CIDR Blocks ─────────────────────────────────────────────────────────────
variable "sdwan_vpc_cidr" {
  description = "CIDR for the SDWAN VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "inspection_vpc_cidr" {
  description = "CIDR for the Inspection VPC"
  type        = string
  default     = "10.200.0.0/16"
}

variable "spoke1_vpc_cidr" {
  description = "CIDR for Spoke 1 VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "spoke2_vpc_cidr" {
  description = "CIDR for Spoke 2 VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "fake_dc_cidr" {
  description = "Simulated on-prem DC CIDR advertised by FortiGate via BGP"
  type        = string
  default     = "10.100.0.0/16"
}

# ── FortiGate ───────────────────────────────────────────────────────────────
variable "fortigate_instance_type" {
  description = "EC2 instance type for the FortiGate-VM"
  type        = string
  default     = "c6i.large"
}

variable "fortigate_asn" {
  description = "BGP ASN for the FortiGate side"
  type        = number
  default     = 65000
}

# ── TGW ─────────────────────────────────────────────────────────────────────
variable "tgw_asn" {
  description = "BGP ASN for the TGW (Amazon side)"
  type        = number
  default     = 64512
}

# ── Test EC2 ────────────────────────────────────────────────────────────────
variable "test_instance_type" {
  description = "EC2 instance type for test workloads"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 Key Pair for SSH access to test instances and FortiGate"
  type        = string
}

# ── Budget ──────────────────────────────────────────────────────────────────
variable "budget_alert_email" {
  description = "Email address for AWS Budget alerts"
  type        = string
}
