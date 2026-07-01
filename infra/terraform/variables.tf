variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-2"
}

variable "project" {
  description = "Project name, used as a prefix/tag on every resource."
  type        = string
  default     = "capstone-phoenix"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet the nodes live in."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Single AZ for all nodes. Single-AZ keeps EBS-backed PVCs simple (a rescheduled Postgres pod can re-attach its volume). Trade-off documented in ARCHITECTURE.md."
  type        = string
  default     = "eu-west-2a"
}

variable "server_instance_type" {
  description = "Instance type for the k3s control-plane node."
  type        = string
  default     = "t3.small"
}

variable "agent_instance_type" {
  description = "Instance type for the k3s worker nodes."
  type        = string
  default     = "t3.small"
}

variable "agent_count" {
  description = "Number of k3s worker (agent) nodes. Minimum 2 to satisfy the brief."
  type        = number
  default     = 2
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB) per node."
  type        = number
  default     = 20
}

variable "ssh_key_name" {
  description = "Name for the AWS key pair created from your public key."
  type        = string
  default     = "capstone-phoenix"
}

variable "ssh_public_key_path" {
  description = "Path to YOUR SSH public key. This is injected into every node. Generate one with: ssh-keygen -t ed25519"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "my_ip" {
  description = "Your public IPv4, used to lock down ports 22 and 6443. Leave empty to auto-detect the IP of the machine running Terraform."
  type        = string
  default     = ""
}
