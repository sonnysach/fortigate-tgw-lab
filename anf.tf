##############################################################################
# anf.tf - AWS Network Firewall (Inspection VPC)
##############################################################################

###############################################################################
# Firewall Policy - permissive lab rules
###############################################################################

# Stateless rule group: allow all (pass everything to stateful engine)
resource "aws_networkfirewall_rule_group" "stateless_pass_all" {
  capacity = 10
  name     = "lab-stateless-pass-all"
  type     = "STATELESS"
  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 1
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
          }
        }
      }
    }
  }
  tags = { Name = "lab-stateless-pass-all" }
}

# Stateful rule group: allow all ICMP + SSH between RFC1918
resource "aws_networkfirewall_rule_group" "stateful_allow_lab" {
  capacity = 20
  name     = "lab-stateful-allow-rfc1918"
  type     = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "RFC1918"
        ip_set {
          definition = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        }
      }
    }

    rules_source {
      rules_string = <<-RULES
        pass icmp any any -> any any (msg:"Allow all ICMP"; sid:1; rev:2;)
        pass tcp $RFC1918 any -> $RFC1918 22 (msg:"Allow SSH RFC1918"; sid:2; rev:1;)
      RULES
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = { Name = "lab-stateful-allow-rfc1918" }
}

# Firewall policy
resource "aws_networkfirewall_firewall_policy" "inspection" {
  name = "lab-inspection-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateless_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateless_pass_all.arn
      priority     = 1
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful_allow_lab.arn
      priority     = 1
    }

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = { Name = "lab-inspection-policy" }
}

###############################################################################
# Network Firewall
###############################################################################
resource "aws_networkfirewall_firewall" "inspection" {
  name                = "lab-inspection-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.inspection.arn
  vpc_id              = aws_vpc.inspection.id

  subnet_mapping {
    subnet_id = aws_subnet.inspection_fw_az1.id
  }

  subnet_mapping {
    subnet_id = aws_subnet.inspection_fw_az2.id
  }

  tags = { Name = "lab-inspection-firewall" }
}

###############################################################################
# Flow Logging -> CloudWatch
###############################################################################
resource "aws_cloudwatch_log_group" "anf_flow" {
  name              = "/aws/network-firewall/lab-inspection/flow"
  retention_in_days = 7
  tags              = { Name = "anf-flow-logs" }
}

resource "aws_cloudwatch_log_group" "anf_alert" {
  name              = "/aws/network-firewall/lab-inspection/alert"
  retention_in_days = 7
  tags              = { Name = "anf-alert-logs" }
}

resource "aws_networkfirewall_logging_configuration" "inspection" {
  firewall_arn = aws_networkfirewall_firewall.inspection.arn

  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.anf_flow.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }

    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.anf_alert.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }
  }
}

###############################################################################
# Routes: TGW subnets -> ANF endpoint in same AZ
###############################################################################

# Extract VPC endpoint IDs per AZ from the firewall sync states
locals {
  # The firewall returns sync_states keyed by AZ
  fw_sync          = aws_networkfirewall_firewall.inspection.firewall_status[0].sync_states
  anf_endpoint_az1 = [for ss in local.fw_sync : ss.attachment[0].endpoint_id if ss.availability_zone == var.az1][0]
  anf_endpoint_az2 = [for ss in local.fw_sync : ss.attachment[0].endpoint_id if ss.availability_zone == var.az2][0]
}

resource "aws_route" "inspection_tgw_az1_to_anf" {
  route_table_id         = aws_route_table.inspection_tgw_az1.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.anf_endpoint_az1
}

resource "aws_route" "inspection_tgw_az2_to_anf" {
  route_table_id         = aws_route_table.inspection_tgw_az2.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.anf_endpoint_az2
}