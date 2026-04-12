##############################################################################
# outputs.tf – All required outputs
##############################################################################

# ── FortiGate (only when deployed) ──────────────────────────────────────────
output "fortigate_mgmt_url" {
  description = "FortiGate management URL (HTTPS on port 8443)"
  value       = var.deploy_fortigate ? "https://${aws_eip.fortigate_mgmt[0].public_ip}:8443" : "FortiGate not deployed (deploy_fortigate = false)"
}

output "fortigate_admin_password" {
  description = "FortiGate initial admin password"
  value       = var.deploy_fortigate ? random_password.fortigate_admin[0].result : "N/A"
  sensitive   = true
}

output "fortigate_mgmt_ssh" {
  description = "SSH command for FortiGate management"
  value       = var.deploy_fortigate ? "ssh -p 2222 admin@${aws_eip.fortigate_mgmt[0].public_ip}" : "FortiGate not deployed (deploy_fortigate = false)"
}

output "fortigate_trust_private_ip" {
  description = "FortiGate trust interface private IP (GRE source for TGW Connect)"
  value       = var.deploy_fortigate ? aws_network_interface.fortigate_trust[0].private_ip : "N/A"
}

# ── TGW Connect Peers (only when FortiGate deployed) ───────────────────────
output "tgw_connect_peer1_tgw_address" {
  description = "TGW-side GRE/BGP IP for Connect Peer 1"
  value       = var.deploy_fortigate ? aws_ec2_transit_gateway_connect_peer.fortigate_peer1[0].transit_gateway_address : "N/A"
}

output "tgw_connect_peer1_bgp_addresses" {
  description = "Inside tunnel addresses for Connect Peer 1 (169.254.100.0/29)"
  value       = var.deploy_fortigate ? aws_ec2_transit_gateway_connect_peer.fortigate_peer1[0].inside_cidr_blocks : []
}

output "tgw_connect_peer2_tgw_address" {
  description = "TGW-side GRE/BGP IP for Connect Peer 2"
  value       = var.deploy_fortigate ? aws_ec2_transit_gateway_connect_peer.fortigate_peer2[0].transit_gateway_address : "N/A"
}

output "tgw_connect_peer2_bgp_addresses" {
  description = "Inside tunnel addresses for Connect Peer 2 (169.254.200.0/29)"
  value       = var.deploy_fortigate ? aws_ec2_transit_gateway_connect_peer.fortigate_peer2[0].inside_cidr_blocks : []
}

output "tgw_amazon_side_asn" {
  description = "TGW Amazon-side BGP ASN"
  value       = var.tgw_asn
}

# ── Test EC2s ───────────────────────────────────────────────────────────────
output "spoke1_test_ec2_public_ip" {
  description = "Spoke 1 test EC2 public IP"
  value       = aws_instance.spoke1_test.public_ip
}

output "spoke1_test_ec2_private_ip" {
  description = "Spoke 1 test EC2 private IP"
  value       = aws_instance.spoke1_test.private_ip
}

output "spoke1_ssh_command" {
  description = "SSH command for Spoke 1 test EC2"
  value       = "ssh -i <key.pem> ec2-user@${aws_instance.spoke1_test.public_ip}"
}

output "spoke2_test_ec2_public_ip" {
  description = "Spoke 2 test EC2 public IP"
  value       = aws_instance.spoke2_test.public_ip
}

output "spoke2_test_ec2_private_ip" {
  description = "Spoke 2 test EC2 private IP"
  value       = aws_instance.spoke2_test.private_ip
}

output "spoke2_ssh_command" {
  description = "SSH command for Spoke 2 test EC2"
  value       = "ssh -i <key.pem> ec2-user@${aws_instance.spoke2_test.public_ip}"
}

output "simulated_dc_private_ip" {
  description = "Simulated DC test EC2 private IP (in SDWAN trust subnet)"
  value       = aws_instance.fake_dc.private_ip
}

output "simulated_dc_note" {
  description = "Simulated DC has no public IP – SSH via FortiGate or spoke EC2 hop"
  value       = "Reach simulated DC at ${aws_instance.fake_dc.private_ip} via FortiGate trust network"
}

# ── Reminder ────────────────────────────────────────────────────────────────
output "cost_reminder" {
  description = "Estimated daily cost reminder"
  value       = "Estimated ~$12/day. Run 'terraform destroy' when done to avoid charges."
}
