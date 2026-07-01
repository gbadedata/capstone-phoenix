resource "aws_instance" "server" {
  ami                    = var.ami_id
  instance_type          = var.server_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  availability_zone      = var.availability_zone

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project}-server"
    Role = "server"
  }
}

resource "aws_instance" "agent" {
  count                  = var.agent_count
  ami                    = var.ami_id
  instance_type          = var.agent_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  availability_zone      = var.availability_zone

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project}-agent-${count.index + 1}"
    Role = "agent"
  }
}

# Elastic IPs so node addresses survive stop/start — DNS targets and SSH stay stable.
resource "aws_eip" "server" {
  instance = aws_instance.server.id
  domain   = "vpc"
  tags     = { Name = "${var.project}-server-eip" }
}

resource "aws_eip" "agent" {
  count    = var.agent_count
  instance = aws_instance.agent[count.index].id
  domain   = "vpc"
  tags     = { Name = "${var.project}-agent-${count.index + 1}-eip" }
}
