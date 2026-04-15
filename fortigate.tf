##############################################################################
# fortigate.tf - FortiGate-VM BYOL instance, ENIs, security groups
# All resources gated by var.deploy_fortigate
# License applied manually via GUI after boot (FortiFlex token)
##############################################################################

###############################################################################
# Latest FortiGate BYOL AMI (FortiOS 7.4.x)
###############################################################################
data "aws_ami" "fortigate" {
  count       = var.deploy_fortigate ? 1 : 0
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["FortiGate-VM64-AWS build*7.4*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################################
# Random admin password
###############################################################################
resource "random_password" "fortigate_admin" {
  count   = var.deploy_fortigate ? 1 : 0
  length  = 20
  special = true
}

###############################################################################
# Security Groups
###############################################################################

# -- Untrust / management SG --
resource "aws_security_group" "fortigate_untrust" {
  count       = var.deploy_fortigate ? 1 : 0
  name_prefix = "fgt-untrust-"
  description = "FortiGate untrust / mgmt interface"
  vpc_id      = aws_vpc.sdwan.id

  ingress {
    description = "HTTPS management"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.allowed_mgmt_cidrs
  }

  ingress {
    description = "SSH management"
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = var.allowed_mgmt_cidrs
  }

  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "IPsec NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from anywhere"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fgt-untrust-sg" }
}

# -- Trust SG (GRE + BGP + internal) --
resource "aws_security_group" "fortigate_trust" {
  count       = var.deploy_fortigate ? 1 : 0
  name_prefix = "fgt-trust-"
  description = "FortiGate trust interface - GRE/BGP/internal"
  vpc_id      = aws_vpc.sdwan.id

  ingress {
    description = "RFC1918 internal"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "GRE from TGW"
    from_port   = 0
    to_port     = 0
    protocol    = "47"
    cidr_blocks = [var.sdwan_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fgt-trust-sg" }
}

###############################################################################
# Network Interfaces
###############################################################################

# ENI 0 - untrust (public-facing, mgmt)
resource "aws_network_interface" "fortigate_untrust" {
  count             = var.deploy_fortigate ? 1 : 0
  subnet_id         = aws_subnet.sdwan_untrust.id
  security_groups   = [aws_security_group.fortigate_untrust[0].id]
  source_dest_check = false
  tags              = { Name = "fgt-untrust-eni" }
}

# ENI 1 - trust (GRE tunnel endpoint, internal)
resource "aws_network_interface" "fortigate_trust" {
  count             = var.deploy_fortigate ? 1 : 0
  subnet_id         = aws_subnet.sdwan_trust.id
  security_groups   = [aws_security_group.fortigate_trust[0].id]
  source_dest_check = false
  tags              = { Name = "fgt-trust-eni" }
}

# Elastic IP for management access
resource "aws_eip" "fortigate_mgmt" {
  count             = var.deploy_fortigate ? 1 : 0
  domain            = "vpc"
  network_interface = aws_network_interface.fortigate_untrust[0].id
  tags              = { Name = "fgt-mgmt-eip" }
}

###############################################################################
# FortiGate EC2 Instance
###############################################################################
resource "aws_instance" "fortigate" {
  count         = var.deploy_fortigate ? 1 : 0
  ami           = data.aws_ami.fortigate[0].id
  instance_type = var.fortigate_instance_type
  key_name      = var.key_pair_name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.fortigate_untrust[0].id
  }

  network_interface {
    device_index         = 1
    network_interface_id = aws_network_interface.fortigate_trust[0].id
  }

  # Bootstrap: set admin password, mgmt ports, hostname.
  # License applied manually via GUI after first login (FortiFlex token).
  user_data = base64encode(<<-EOF
    config system global
      set hostname "lab-fortigate"
      set admin-sport 8443
      set admin-ssh-port 2222
    end
    config system admin
      edit "admin"
        set password "${random_password.fortigate_admin[0].result}"
      next
    end
    config system interface
      edit "port1"
        set alias "untrust"
        set allowaccess ping https ssh fgfm
      next
      edit "port2"
        set alias "trust"
        set allowaccess ping
      next
    end
  EOF
  )

  tags = { Name = "lab-fortigate" }
}