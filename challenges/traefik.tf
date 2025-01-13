locals {


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
