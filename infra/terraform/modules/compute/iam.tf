# IAM role + instance profile attached to every node so in-cluster controllers (the AWS EBS
# CSI driver) can call AWS APIs using the instance's role — no static access keys anywhere.

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project}-node-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = { Name = "${var.project}-node-role" }
}

# AWS-managed policy scoped to exactly what the EBS CSI driver needs.
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.project}-node-profile"
  role = aws_iam_role.node.name
}
