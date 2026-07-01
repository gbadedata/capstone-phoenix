output "control_plane_public_ip" {
  description = "Public (Elastic) IP of the k3s server. SSH here and point DNS-adjacent things at it."
  value       = module.compute.server_public_ip
}

output "control_plane_private_ip" {
  description = "Private IP of the k3s server (agents join on this)."
  value       = module.compute.server_private_ip
}

output "worker_public_ips" {
  description = "Public (Elastic) IPs of the worker nodes. DNS A records for the app point at these."
  value       = module.compute.agent_public_ips
}

output "worker_private_ips" {
  description = "Private IPs of the worker nodes."
  value       = module.compute.agent_private_ips
}

output "ssh_user" {
  description = "Default SSH user for the Ubuntu AMI."
  value       = "ubuntu"
}

output "detected_admin_cidr" {
  description = "The /32 that ports 22 and 6443 are locked to."
  value       = local.my_cidr
}
