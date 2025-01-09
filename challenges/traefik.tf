locals {
  traefik_ami = "ami-0dc59a0c089abde51"
}

data "aws_elb_service_account" "elb_service_acc" {}

resource "aws_iam_role" "traefik_role" {
  name = "${local.cluster_name}_traefik_role"

  tags = {
    event = local.tag
  }

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "template_file" "traefik_instance_role_policy" {
  template = file("traefik/traefik.json")

  vars = {
    chall_domain   = local.chall_domain
    domain_zone_id = local.domain_zone_id
  }
}

resource "aws_iam_role_policy" "traefik_instance_role_policy" {
  name   = "${local.cluster_name}-traefik-instance-role-policy"
  policy = data.template_file.traefik_instance_role_policy.rendered
  role   = aws_iam_role.traefik_role.id
}

resource "aws_iam_instance_profile" "traefik" {
  name = "${local.cluster_name}-traefik-instance-profile"
  path = "/"
  role = aws_iam_role.traefik_role.id
  tags = {
    event = local.tag
  }
}

resource "tls_private_key" "traefik" {
  algorithm = "RSA"
}

resource "local_file" "traefik_private_key" {
  content         = tls_private_key.traefik.private_key_pem
  filename        = "${local.out_dir}/traefik_key.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "traefik" {
  key_name   = "${local.cluster_name}-traefik"
  public_key = tls_private_key.traefik.public_key_openssh

  tags = {
    event = local.tag
  }
}

resource "aws_eip" "traefik" {
  instance = aws_instance.traefik.id

  tags = {
    event = local.tag
  }
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

locals {
  // Defined by AMI
  traefik_user = "ec2-user"
}

resource "aws_instance" "traefik" {
  ami                    = data.aws_ami.amazon-linux-2.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.traefik.key_name
  subnet_id              = aws_subnet.nohack_subnet.id
  vpc_security_group_ids = [aws_security_group.traefik.id, aws_security_group.allow_ssh_anywhere.id]
  iam_instance_profile   = aws_iam_instance_profile.traefik.id

  credit_specification {
    cpu_credits = "unlimited"
  }

  tags = {
    Name  = "Traefik (${local.cluster_name})"
    event = local.tag
  }

  disable_api_termination = false
  ebs_optimized           = true
  get_password_data       = false
  hibernation             = false
  monitoring              = true

  user_data = base64encode(file("traefik/cloud-init.yml"))

  connection {
    type        = "ssh"
    user        = local.traefik_user
    private_key = tls_private_key.traefik.private_key_pem
    host        = self.public_ip
  }

  provisioner "file" {
    content     = file("traefik/traefik.service")
    destination = "/tmp/traefik.service"
  }

  provisioner "file" {
    content = templatefile("traefik/traefik.yml", {
      cluster_name = local.cluster_name
    })
    destination = "/tmp/traefik.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/traefik",
      "sudo install -m 644 /tmp/dynamic.yml /etc/traefik/dynamic.yml",
      "sudo install -m 644 /tmp/traefik.yml /etc/traefik/traefik.yml",
      "sudo install -m 644 /tmp/traefik.service /etc/systemd/system/traefik.service",
      "sudo chown -R traefik:traefik /etc/traefik/",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now traefik.service",
    ]
    on_failure = fail
  }

  associate_public_ip_address = true
  lifecycle {
    ignore_changes = [
      associate_public_ip_address
    ]
  }
}

resource "local_file" "traefik_public_ip" {
  content  = aws_eip.traefik.public_ip
  filename = "${local.out_dir}/traefik_public_ip"
}

resource "aws_security_group" "traefik" {
  name   = "traefik-${local.name}"
  vpc_id = aws_vpc.ctf_main.id

  tags = {
    event = local.tag
  }

  ingress {
    from_port       = 13370
    to_port         = 13450
    protocol        = "tcp"
    security_groups = []
    cidr_blocks     = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = []
    cidr_blocks     = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = []
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
