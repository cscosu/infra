resource "aws_instance" "auth" {
  ami                         = data.aws_ami.minimal-arm64.id
  availability_zone           = local.availability_zone
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.private.id
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance.name
  vpc_security_group_ids      = [aws_security_group.auth.id]
  associate_public_ip_address = false
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 4
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      instance_interruption_behavior = "stop"
      spot_instance_type             = "persistent"
    }
  }

  user_data = base64encode(<<-INIT
    #!/bin/bash
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    amazon-linux-extras disable docker
    amazon-linux-extras enable ecs
    yum install -y ecs-init tc
    echo "ECS_CLUSTER=${aws_ecs_cluster.default.name}" > /etc/ecs/ecs.config

    cat <<EOF > /etc/systemd/system/mount-ebs.service
    [Unit]
    Description=Format and Mount Device
    DefaultDependencies=no
    Before=local-fs.target
    Wants=local-fs.target

    [Service]
    Type=oneshot
    ExecStartPre=/bin/bash -c '(while ! /usr/bin/lsblk -ln -o FSTYPE /dev/sdh 2>/dev/null; do echo "Waiting for block device /dev/sdh..."; sleep 2; done); sleep 2'
    ExecStart=/bin/bash -c "if [ \"\$(lsblk -ln -o FSTYPE /dev/sdh)\" != \"ext4\" ]; then /usr/sbin/mkfs.ext4 -L auth /dev/sdh ; fi && /usr/bin/mkdir -p /auth && /usr/bin/mount /dev/sdh /auth ; /usr/bin/mkdir -p /auth/auth"
    ExecStop=/usr/bin/umount /auth
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    EOF

    systemctl daemon-reload
    systemctl enable mount-ebs
    systemctl start mount-ebs
    systemctl enable ecs
    systemctl start --no-block ecs
    INIT
  )

  tags = {
    Name = "${local.name}-auth"
  }
}

resource "aws_ecs_task_definition" "auth" {
  family = "${local.name}-auth"

  container_definitions = jsonencode([
    {
      name              = "auth"
      image             = "${aws_ecr_repository.default.repository_url}:auth2"
      memoryReservation = 256

      mountPoints = [
        {
          sourceVolume  = "auth"
          containerPath = "/auth"
          readOnly      = false
        }
      ]

      dockerLabels = {
        "traefik.enable"                               = "true"
        "traefik.http.routers.auth.rule"               = "Host(`auth.${local.domain}`)"
        "traefik.http.routers.auth.entrypoints"        = "websecure"
        "traefik.http.routers.auth.tls.certResolver"   = "letsencrypt"
        "traefik.http.routers.auth.tls.domains.0.main" = "*.${local.domain}"
      }

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 0
          name          = "auth"
        }
      ]

      environment = [
        { name = "DB_URL", value = "/auth/auth.db" },
      ]

      healthCheck = {
        retries = 3
        command = [
          "CMD-SHELL",
          "true"
        ]
        timeout  = 3
        interval = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.default.name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "auth"
        }
      }
    }
  ])

  volume {
    name      = "auth"
    host_path = "/auth/auth"
  }
}

resource "aws_ebs_volume" "auth" {
  availability_zone = local.availability_zone
  size              = 2
  type              = "gp3"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "auth" {
  device_name  = "/dev/sdh"
  instance_id  = aws_instance.auth.id
  volume_id    = aws_ebs_volume.auth.id
  force_detach = true
}

resource "aws_ecs_service" "auth" {
  depends_on      = [aws_iam_role_policy.ecs_cluster_permissions]
  name            = "${local.name}-auth"
  cluster         = aws_ecs_cluster.default.id
  task_definition = aws_ecs_task_definition.auth.arn
  desired_count   = 1

  placement_constraints {
    type       = "memberOf"
    expression = "ec2InstanceId in ['${aws_instance.auth.id}']"
  }
}

resource "aws_security_group" "auth" {
  name   = "${local.name}-auth"
  vpc_id = aws_vpc.default.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.traefik.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
