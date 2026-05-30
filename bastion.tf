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

  # Allow all egress. The SSM agent needs more than HTTPS to register: DNS
  # (53) to resolve the SSM endpoints and NTP (123) to keep its clock in sync
  # (SigV4/TLS fail on a skewed clock), plus 443 for the channel and package
  # mirrors. Restricting egress to 443 silently breaks agent registration.
  # Security here is the empty inbound list, not the egress list.
  egress {
    description = "All outbound (SSM channel, DNS, NTP, package mirrors, Postgres)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

  # OS patching: enable dnf-automatic for unattended *security* updates so this
  # long-lived instance doesn't drift behind on OS fixes (the pinned AMI only
  # rolls the desired image forward on a future apply, it doesn't patch a
  # running host). reboot=never means an in-progress operator SSM tunnel or
  # `terraform apply` is never dropped by a surprise reboot; the kernel/glibc
  # fixes that do need a reboot land when the bastion is recreated as the AMI
  # parameter rolls forward (a planned apply, not a surprise). user_data runs
  # only on first boot, so user_data_replace_on_change recreates the instance
  # when this script changes rather than leaving it stale.
  user_data_replace_on_change = true
  user_data                   = <<-EOT
    #!/bin/bash
    set -euo pipefail
    # AL2023 pins releasever to the AMI's baked-in version (deterministic
    # upgrades), so a plain `dnf upgrade` — which dnf-automatic runs — finds
    # nothing and the timer would be a no-op. Track `latest` so dnf-automatic
    # actually pulls published security fixes. Acceptable here: the bastion is a
    # stateless, recreatable t4g.nano, not an app host that needs a frozen
    # package set.
    mkdir -p /etc/dnf/vars
    echo latest > /etc/dnf/vars/releasever
    dnf install -y dnf-automatic
    # reboot=never is AL2023's default; set it explicitly so a future AMI
    # default change can't reintroduce a surprise reboot.
    sed -i \
      -e 's/^upgrade_type = .*/upgrade_type = security/' \
      -e 's/^apply_updates = .*/apply_updates = yes/' \
      -e 's/^reboot = .*/reboot = never/' \
      /etc/dnf/automatic.conf
    systemctl enable --now dnf-automatic.timer
  EOT

  tags = {
    Name = "shared-db-bastion"
  }
}
