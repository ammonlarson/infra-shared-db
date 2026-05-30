# SSM bastion — the only operator/CI path to the now-private RDS instance.
#
# It carries no inbound rules: AWS Systems Manager Session Manager works
# entirely over the agent's outbound connection, so operators and CI reach
# Postgres with `aws ssm start-session ... AWS-StartPortForwardingSessionToRemoteHost`
# (see scripts/db-tunnel.sh and README). The instance gets a public IP only so
# the SSM agent can reach the SSM endpoints through the default VPC's internet
# gateway — cheaper than a NAT gateway or SSM interface VPC endpoints. The
# public IP does not expose RDS: RDS is private and only this SG can reach it.

# AL2023 ships and runs the SSM agent out of the box; arm64 matches t4g.nano.
data "aws_ssm_parameter" "bastion_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "bastion" {
  name        = "shared-db-bastion"
  description = "SSM bastion for shared RDS (egress only)"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "HTTPS to SSM endpoints and package mirrors"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Postgres to the shared RDS instance"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

data "aws_iam_policy_document" "bastion_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "shared-db-bastion"
  assume_role_policy = data.aws_iam_policy_document.bastion_assume.json
}

# AmazonSSMManagedInstanceCore is the minimal managed policy that lets the SSM
# agent register the instance and open Session Manager channels.
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "shared-db-bastion"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.bastion_ami.value
  instance_type          = "t4g.nano"
  subnet_id              = data.aws_subnets.default.ids[0]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # Public IP for SSM-agent egress via the IGW (no NAT). No key pair: access is
  # Session Manager only.
  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = {
    Name = "shared-db-bastion"
  }
}
