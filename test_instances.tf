##############################################################################
# test_instances.tf – Test EC2s in spokes + fake-DC in SDWAN trust subnet
##############################################################################

###############################################################################
# Security Group – Test EC2s (SSH from allowed CIDRs + ICMP internal)
###############################################################################
resource "aws_security_group" "test_ec2" {
  for_each = {
    spoke1 = aws_vpc.spoke1.id
    spoke2 = aws_vpc.spoke2.id
  }

  name_prefix = "test-ec2-${each.key}-"
  description = "Test EC2 in ${each.key}"
  vpc_id      = each.value

  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_mgmt_cidrs
  }

  ingress {
    description = "ICMP from RFC1918"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  ingress {
    description = "SSH from RFC1918"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "test-ec2-${each.key}-sg" }
}

# Fake-DC SG in SDWAN VPC trust subnet
resource "aws_security_group" "fake_dc" {
  name_prefix = "fake-dc-"
  description = "Fake DC test EC2 in SDWAN trust subnet"
  vpc_id      = aws_vpc.sdwan.id

  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_mgmt_cidrs
  }

  ingress {
    description = "ICMP from RFC1918"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  ingress {
    description = "SSH from RFC1918"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fake-dc-sg" }
}

###############################################################################
# User Data – install iputils
###############################################################################
locals {
  test_userdata = <<-EOF
    #!/bin/bash
    yum install -y iputils traceroute
  EOF
}

###############################################################################
# Test EC2 – Spoke 1
###############################################################################
resource "aws_instance" "spoke1_test" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.test_instance_type
  subnet_id              = aws_subnet.spoke1_workload.id
  vpc_security_group_ids = [aws_security_group.test_ec2["spoke1"].id]
  key_name               = var.key_pair_name
  user_data              = local.test_userdata

  tags = { Name = "spoke1-test-ec2" }
}

###############################################################################
# Test EC2 – Spoke 2
###############################################################################
resource "aws_instance" "spoke2_test" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.test_instance_type
  subnet_id              = aws_subnet.spoke2_workload.id
  vpc_security_group_ids = [aws_security_group.test_ec2["spoke2"].id]
  key_name               = var.key_pair_name
  user_data              = local.test_userdata

  tags = { Name = "spoke2-test-ec2" }
}

###############################################################################
# Test EC2 – Fake DC (SDWAN trust subnet)
###############################################################################
resource "aws_instance" "fake_dc" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.test_instance_type
  subnet_id              = aws_subnet.sdwan_trust.id
  vpc_security_group_ids = [aws_security_group.fake_dc.id]
  key_name               = var.key_pair_name
  user_data              = local.test_userdata

  tags = { Name = "fake-dc-test-ec2" }
}
