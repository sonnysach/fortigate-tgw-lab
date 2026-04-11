##############################################################################
# tgw.tf – Transit Gateway, attachments, Connect, route tables
##############################################################################

###############################################################################
# Transit Gateway
###############################################################################
resource "aws_ec2_transit_gateway" "main" {
  description                     = "FortiGate-TGW-Lab"
  amazon_side_asn                 = var.tgw_asn
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  tags                            = { Name = "lab-tgw" }
}

###############################################################################
# VPC Attachments
###############################################################################

# -- SDWAN VPC attachment (used as transport for TGW Connect) --
resource "aws_ec2_transit_gateway_vpc_attachment" "sdwan" {
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  vpc_id                 = aws_vpc.sdwan.id
  subnet_ids             = [aws_subnet.sdwan_tgw.id]
  appliance_mode_support = "disable"
  dns_support            = "enable"
  tags                   = { Name = "sdwan-vpc-attach" }
}

# -- Inspection VPC attachment (appliance mode ON) --
resource "aws_ec2_transit_gateway_vpc_attachment" "inspection" {
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  vpc_id                 = aws_vpc.inspection.id
  subnet_ids             = [aws_subnet.inspection_tgw_az1.id, aws_subnet.inspection_tgw_az2.id]
  appliance_mode_support = "enable"
  dns_support            = "enable"
  tags                   = { Name = "inspection-vpc-attach" }
}

# -- Spoke 1 VPC attachment --
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke1" {
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  vpc_id                 = aws_vpc.spoke1.id
  subnet_ids             = [aws_subnet.spoke1_workload.id]
  appliance_mode_support = "disable"
  dns_support            = "enable"
  tags                   = { Name = "spoke1-vpc-attach" }
}

# -- Spoke 2 VPC attachment --
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke2" {
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  vpc_id                 = aws_vpc.spoke2.id
  subnet_ids             = [aws_subnet.spoke2_workload.id]
  appliance_mode_support = "disable"
  dns_support            = "enable"
  tags                   = { Name = "spoke2-vpc-attach" }
}

###############################################################################
# TGW Connect (GRE + BGP over the SDWAN VPC attachment)
###############################################################################
resource "aws_ec2_transit_gateway_connect" "fortigate" {
  count                   = var.deploy_fortigate ? 1 : 0
  transport_attachment_id = aws_ec2_transit_gateway_vpc_attachment.sdwan.id
  transit_gateway_id      = aws_ec2_transit_gateway.main.id
  protocol                = "gre"
  tags                    = { Name = "fortigate-connect" }
}

resource "aws_ec2_transit_gateway_connect_peer" "fortigate_peer1" {
  count                         = var.deploy_fortigate ? 1 : 0
  transit_gateway_attachment_id = aws_ec2_transit_gateway_connect.fortigate[0].id
  peer_address                  = aws_network_interface.fortigate_trust[0].private_ip
  inside_cidr_blocks            = ["169.254.100.0/29"]
  bgp_asn                       = var.fortigate_asn
  tags                          = { Name = "fgt-connect-peer-1" }
}

resource "aws_ec2_transit_gateway_connect_peer" "fortigate_peer2" {
  count                         = var.deploy_fortigate ? 1 : 0
  transit_gateway_attachment_id = aws_ec2_transit_gateway_connect.fortigate[0].id
  peer_address                  = aws_network_interface.fortigate_trust[0].private_ip
  inside_cidr_blocks            = ["169.254.200.0/29"]
  bgp_asn                       = var.fortigate_asn
  tags                          = { Name = "fgt-connect-peer-2" }
}

###############################################################################
# TGW Route Tables
###############################################################################

# ── SDWAN RT ────────────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_route_table" "sdwan" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = { Name = "sdwan-rt" }
}

resource "aws_ec2_transit_gateway_route_table_association" "connect" {
  count                          = var.deploy_fortigate ? 1 : 0
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_connect.fortigate[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.sdwan.id
}

resource "aws_ec2_transit_gateway_route" "sdwan_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.sdwan.id
}

# ── Spoke RT ────────────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = { Name = "spoke-rt" }
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke1" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke1.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke2" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route" "spoke_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# ── Firewall RT ─────────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_route_table" "firewall" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = { Name = "firewall-rt" }
}

resource "aws_ec2_transit_gateway_route_table_association" "inspection" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
}

# Propagate spoke attachments into Firewall RT
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke1_to_fw" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke1.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke2_to_fw" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
}

# Propagate Connect attachment into Firewall RT (BGP-learned DC route)
resource "aws_ec2_transit_gateway_route_table_propagation" "connect_to_fw" {
  count                          = var.deploy_fortigate ? 1 : 0
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_connect.fortigate[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
}
