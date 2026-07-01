# Auto-detect the runner's public IP unless my_ip is set explicitly.
data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_cidr = var.my_ip != "" ? "${var.my_ip}/32" : "${chomp(data.http.myip.response_body)}/32"
}

# Latest Ubuntu 22.04 LTS (Jammy) AMI from Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Your SSH public key, registered as an AWS key pair.
resource "aws_key_pair" "this" {
  key_name   = var.ssh_key_name
  public_key = file(pathexpand(var.ssh_public_key_path))
}

module "network" {
  source            = "./modules/network"
  project           = var.project
  vpc_cidr          = var.vpc_cidr
  subnet_cidr       = var.subnet_cidr
  availability_zone = var.availability_zone
}

module "security_group" {
  source  = "./modules/security_group"
  project = var.project
  vpc_id  = module.network.vpc_id
  my_cidr = local.my_cidr
}

module "compute" {
  source               = "./modules/compute"
  project              = var.project
  ami_id               = data.aws_ami.ubuntu.id
  key_name             = aws_key_pair.this.key_name
  subnet_id            = module.network.subnet_id
  security_group_id    = module.security_group.security_group_id
  availability_zone    = var.availability_zone
  server_instance_type = var.server_instance_type
  agent_instance_type  = var.agent_instance_type
  agent_count          = var.agent_count
  root_volume_size     = var.root_volume_size
}

# Render an Ansible inventory from the live node IPs so Phase 2 is plug-and-play.
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"
  content = templatefile("${path.module}/templates/hosts.ini.tpl", {
    server_public_ip  = module.compute.server_public_ip
    server_private_ip = module.compute.server_private_ip
    agent_public_ips  = module.compute.agent_public_ips
    agent_private_ips = module.compute.agent_private_ips
  })
  file_permission = "0644"
}
