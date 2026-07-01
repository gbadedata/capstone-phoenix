output "server_public_ip" {
  value = aws_eip.server.public_ip
}

output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "agent_public_ips" {
  value = aws_eip.agent[*].public_ip
}

output "agent_private_ips" {
  value = aws_instance.agent[*].private_ip
}
