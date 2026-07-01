# Least-privilege node security group.
#   22   -> your IP only (SSH)
#   6443 -> your IP only (kubectl to the k3s API; NOT open to the world)
#   80   -> world (HTTP / ACME http-01 challenge)
#   443  -> world (HTTPS)
#   all node-to-node traffic allowed within the SG (flannel VXLAN, kubelet, API, etc.)
resource "aws_security_group" "nodes" {
  name_prefix = "${var.project}-nodes-"
  description = "Least-privilege SG for k3s nodes"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_cidr]
  }

  ingress {
    description = "Kubernetes API from admin IP"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_cidr]
  }

  ingress {
    description = "HTTP from the world"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from the world"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All node-to-node traffic within the cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-nodes-sg" }

  lifecycle {
    create_before_destroy = true
  }
}
