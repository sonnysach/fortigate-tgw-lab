##############################################################################
# vpc.tf – VPCs, subnets, IGWs, route tables, NAT gateways
##############################################################################

# ── Data: Latest Amazon Linux 2023 AMI (for test EC2s) ─────────────────────
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################################
# 1. SDWAN VPC  (10.10.0.0/16)
###############################################################################
resource "aws_vpc" "sdwan" {
  cidr_block           = var.sdwan_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "sdwan-vpc" }
}

# -- Subnets --
resource "aws_subnet" "sdwan_untrust" {
  vpc_id                  = aws_vpc.sdwan.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = var.az1
  map_public_ip_on_launch = true
  tags                    = { Name = "sdwan-untrust" }
}

resource "aws_subnet" "sdwan_trust" {
  vpc_id            = aws_vpc.sdwan.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = var.az1
  tags              = { Name = "sdwan-trust" }
}

resource "aws_subnet" "sdwan_tgw" {
  vpc_id            = aws_vpc.sdwan.id
  cidr_block        = "10.10.3.0/24"
  availability_zone = var.az1
  tags              = { Name = "sdwan-tgw-attach" }
}

# -- Internet Gateway --
resource "aws_internet_gateway" "sdwan" {
  vpc_id = aws_vpc.sdwan.id
  tags   = { Name = "sdwan-igw" }
}

# -- Route Tables --
resource "aws_route_table" "sdwan_untrust" {
  vpc_id = aws_vpc.sdwan.id
  tags   = { Name = "sdwan-untrust-rt" }
}

resource "aws_route" "sdwan_untrust_default" {
  route_table_id         = aws_route_table.sdwan_untrust.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.sdwan.id
}

resource "aws_route_table_association" "sdwan_untrust" {
  subnet_id      = aws_subnet.sdwan_untrust.id
  route_table_id = aws_route_table.sdwan_untrust.id
}

resource "aws_route_table" "sdwan_trust" {
  vpc_id = aws_vpc.sdwan.id
  tags   = { Name = "sdwan-trust-rt" }
}

resource "aws_route" "sdwan_trust_to_tgw" {
  route_table_id         = aws_route_table.sdwan_trust.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route_table_association" "sdwan_trust" {
  subnet_id      = aws_subnet.sdwan_trust.id
  route_table_id = aws_route_table.sdwan_trust.id
}

resource "aws_route_table" "sdwan_tgw" {
  vpc_id = aws_vpc.sdwan.id
  tags   = { Name = "sdwan-tgw-rt" }
}

resource "aws_route_table_association" "sdwan_tgw" {
  subnet_id      = aws_subnet.sdwan_tgw.id
  route_table_id = aws_route_table.sdwan_tgw.id
}

###############################################################################
# 2. INSPECTION VPC  (10.200.0.0/16)
###############################################################################
resource "aws_vpc" "inspection" {
  cidr_block           = var.inspection_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "inspection-vpc" }
}

# -- TGW subnets (one per AZ) --
resource "aws_subnet" "inspection_tgw_az1" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.200.1.0/28"
  availability_zone = var.az1
  tags              = { Name = "inspection-tgw-az1" }
}

resource "aws_subnet" "inspection_tgw_az2" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.200.11.0/28"
  availability_zone = var.az2
  tags              = { Name = "inspection-tgw-az2" }
}

# -- Firewall subnets (one per AZ) --
resource "aws_subnet" "inspection_fw_az1" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.200.2.0/28"
  availability_zone = var.az1
  tags              = { Name = "inspection-fw-az1" }
}

resource "aws_subnet" "inspection_fw_az2" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.200.12.0/28"
  availability_zone = var.az2
  tags              = { Name = "inspection-fw-az2" }
}

# -- Route Tables for Inspection VPC --
# TGW subnet RT: send traffic to ANF endpoints
resource "aws_route_table" "inspection_tgw_az1" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "inspection-tgw-az1-rt" }
}

resource "aws_route_table" "inspection_tgw_az2" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "inspection-tgw-az2-rt" }
}

resource "aws_route_table_association" "inspection_tgw_az1" {
  subnet_id      = aws_subnet.inspection_tgw_az1.id
  route_table_id = aws_route_table.inspection_tgw_az1.id
}

resource "aws_route_table_association" "inspection_tgw_az2" {
  subnet_id      = aws_subnet.inspection_tgw_az2.id
  route_table_id = aws_route_table.inspection_tgw_az2.id
}

# Firewall subnet RT: return traffic to TGW
resource "aws_route_table" "inspection_fw_az1" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "inspection-fw-az1-rt" }
}

resource "aws_route_table" "inspection_fw_az2" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "inspection-fw-az2-rt" }
}

resource "aws_route" "inspection_fw_az1_return" {
  route_table_id         = aws_route_table.inspection_fw_az1.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "inspection_fw_az2_return" {
  route_table_id         = aws_route_table.inspection_fw_az2.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route_table_association" "inspection_fw_az1" {
  subnet_id      = aws_subnet.inspection_fw_az1.id
  route_table_id = aws_route_table.inspection_fw_az1.id
}

resource "aws_route_table_association" "inspection_fw_az2" {
  subnet_id      = aws_subnet.inspection_fw_az2.id
  route_table_id = aws_route_table.inspection_fw_az2.id
}

# Routes from TGW subnets → ANF endpoints (added after ANF is created, see anf.tf)

###############################################################################
# 3. SPOKE 1 VPC  (10.1.0.0/16)
###############################################################################
resource "aws_vpc" "spoke1" {
  cidr_block           = var.spoke1_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "spoke1-vpc" }
}

resource "aws_subnet" "spoke1_workload" {
  vpc_id                  = aws_vpc.spoke1.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = var.az1
  map_public_ip_on_launch = true
  tags                    = { Name = "spoke1-workload" }
}

resource "aws_internet_gateway" "spoke1" {
  vpc_id = aws_vpc.spoke1.id
  tags   = { Name = "spoke1-igw" }
}

resource "aws_route_table" "spoke1" {
  vpc_id = aws_vpc.spoke1.id
  tags   = { Name = "spoke1-rt" }
}

resource "aws_route" "spoke1_default_tgw" {
  route_table_id         = aws_route_table.spoke1.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "spoke1_igw" {
  route_table_id         = aws_route_table.spoke1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.spoke1.id
}

resource "aws_route_table_association" "spoke1" {
  subnet_id      = aws_subnet.spoke1_workload.id
  route_table_id = aws_route_table.spoke1.id
}

###############################################################################
# 4. SPOKE 2 VPC  (10.2.0.0/16)
###############################################################################
resource "aws_vpc" "spoke2" {
  cidr_block           = var.spoke2_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "spoke2-vpc" }
}

resource "aws_subnet" "spoke2_workload" {
  vpc_id                  = aws_vpc.spoke2.id
  cidr_block              = "10.2.1.0/24"
  availability_zone       = var.az1
  map_public_ip_on_launch = true
  tags                    = { Name = "spoke2-workload" }
}

resource "aws_internet_gateway" "spoke2" {
  vpc_id = aws_vpc.spoke2.id
  tags   = { Name = "spoke2-igw" }
}

resource "aws_route_table" "spoke2" {
  vpc_id = aws_vpc.spoke2.id
  tags   = { Name = "spoke2-rt" }
}

resource "aws_route" "spoke2_default_tgw" {
  route_table_id         = aws_route_table.spoke2.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "spoke2_igw" {
  route_table_id         = aws_route_table.spoke2.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.spoke2.id
}

resource "aws_route_table_association" "spoke2" {
  subnet_id      = aws_subnet.spoke2_workload.id
  route_table_id = aws_route_table.spoke2.id
}
