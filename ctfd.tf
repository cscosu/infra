resource "aws_instance" "ctfd" {
  ami                         = data.aws_ami.ecs-optimized.id
  instance_type               = "t4g.small"
  subnet_id                   = aws_subnet.default.id
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance.name
  vpc_security_group_ids      = [aws_security_group.ctfd.id]
  associate_public_ip_address = false

  instance_market_options {
    market_type = "spot"
    spot_options {
      instance_interruption_behavior = "stop"
      spot_instance_type             = "persistent"
    }
  }

  user_data = base64encode(<<-INIT
    #!/bin/bash
    
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
    ExecStart=/bin/bash -c "if [ \"\$(lsblk -ln -o FSTYPE /dev/sdh)\" != \"ext4\" ]; then /usr/sbin/mkfs.ext4 -L ctfd /dev/sdh ; fi && /usr/bin/mkdir -p /ctfd && /usr/bin/mount /dev/sdh /ctfd ; /usr/bin/mkdir -p /ctfd/mariadb && /usr/bin/chown 999:999 /ctfd/mariadb && /usr/bin/mkdir -p /ctfd/ctfd && /usr/bin/chown 1001:1001 /ctfd/ctfd"
    ExecStop=/usr/bin/umount /ctfd
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    EOF

    systemctl daemon-reload
    systemctl enable mount-ebs
    systemctl start mount-ebs
    INIT
  )

  tags = {
    Name = "${local.name}-ec2-ctfd"
  }
}

resource "random_password" "ctfd_jwt_secret_key" {
  length = 64
}

resource "aws_ecs_task_definition" "ctfd" {
  family = "${local.name}-ecs-task-definition-ctfd"

  container_definitions = jsonencode([
    {
      name              = "ctfd"
      image             = "ghcr.io/ctfd/ctfd:3.7.5"
      memoryReservation = 200

      links = ["redis", "mariadb"],

      dependsOn = [
        {
          containerName = "redis",
          condition     = "HEALTHY"
        },
        {
          containerName = "mariadb",
          condition     = "HEALTHY"
        },
      ]

      mountPoints = [
        {
          sourceVolume  = "ctfd"
          containerPath = "/ctfd"
          readOnly      = false
        }
      ]

      entryPoint = ["/bin/sh", "-c", "python3 -c \"import urllib.request; import zipfile; open('plugin.zip', 'wb').write(urllib.request.urlopen('https://github.com/cscosu/ctfd-writeups/archive/refs/heads/main.zip').read()); zipfile.ZipFile('plugin.zip', 'r').extractall('plugin')\" && cp -r plugin/ctfd-writeups-main/ctfd-writeups CTFd/plugins/ctfd-writeups && /opt/CTFd/docker-entrypoint.sh"]

      dockerLabels = {
        "traefik.enable"                             = "true"
        "traefik.http.routers.ctfd.rule"             = "Host(`bootcamp.testing.osucyber.club`)"
        "traefik.http.routers.ctfd.entrypoints"      = "websecure"
        "traefik.http.routers.ctfd.tls.certResolver" = "letsencrypt",
      }

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 0
          name          = "ctfd"
        }
      ]

      environment = [
        {
          name  = "SECRET_KEY",
          value = random_password.ctfd_jwt_secret_key.result,
        },
        {
          name  = "UPLOAD_FOLDER"
          value = "/ctfd/uploads",
        },
        {
          name  = "LOG_FOLDER"
          value = "/ctfd/logs",
        },
        {
          name  = "REVERSE_PROXY",
          value = "true",
        },
        {
          name  = "DATABASE_URL",
          value = "mysql+pymysql://ctfd:ctfd@mariadb/ctfd",
        },
        {
          name  = "REDIS_URL",
          value = "redis://redis:6379",
        }
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
          "awslogs-region"        = local.region,
          "awslogs-stream-prefix" = "ctfd",
        }
      }

      stopTimeout = 300
    },
    {
      name              = "redis"
      image             = "redis:7.4.2"
      memoryReservation = 200

      mountPoints = [
        {
          sourceVolume  = "redis"
          containerPath = "/data"
          readOnly      = false
        }
      ]

      healthCheck = {
        retries = 3
        command = [
          "CMD-SHELL",
          "redis-cli ping"
        ]
        timeout  = 3
        interval = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.default.name
          "awslogs-region"        = local.region,
          "awslogs-stream-prefix" = "ctfd",
        }
      }

      stopTimeout = 300
    },
    {
      name              = "mariadb"
      image             = "mariadb:11.6.2-ubi"
      memoryReservation = 200

      command = [
        "mysqld",
        "--character-set-server=utf8mb4",
        "--collation-server=utf8mb4_unicode_ci",
        "--wait_timeout=28800",
        "--log-warnings=0",
      ]

      environment = [
        {
          name  = "MARIADB_ROOT_PASSWORD",
          value = "ctfd",
        },
        {
          name  = "MARIADB_USER",
          value = "ctfd",
        },
        {
          name  = "MARIADB_PASSWORD",
          value = "ctfd",
        },
        {
          name  = "MARIADB_DATABASE",
          value = "ctfd",
        },
        {
          name  = "MARIADB_AUTO_UPGRADE",
          value = "1",
        },
      ]

      mountPoints = [
        {
          sourceVolume  = "mariadb"
          containerPath = "/var/lib/mysql"
          readOnly      = false
        }
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
          "awslogs-region"        = local.region,
          "awslogs-stream-prefix" = "ctfd",
        }
      }

      stopTimeout = 300
    }
  ])

  volume {
    name      = "ctfd"
    host_path = "/ctfd/ctfd"
  }

  volume {
    name      = "redis"
    host_path = "/ctfd/redis"
  }

  volume {
    name      = "mariadb"
    host_path = "/ctfd/mariadb"
  }

  requires_compatibilities = []
  tags                     = {}
}

resource "aws_ebs_volume" "ctfd" {
  availability_zone = aws_instance.ctfd.availability_zone
  size              = 20
  type              = "gp3"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "ctfd" {
  device_name = "/dev/sdh"
  instance_id = aws_instance.ctfd.id
  volume_id   = aws_ebs_volume.ctfd.id
}

resource "aws_ecs_service" "ctfd" {
  depends_on      = [aws_iam_role_policy.ecs_cluster_permissions]
  name            = "${local.name}-ecs-service-ctfd"
  cluster         = aws_ecs_cluster.default.id
  task_definition = aws_ecs_task_definition.ctfd.arn
  desired_count   = 1

  placement_constraints {
    type       = "memberOf"
    expression = "ec2InstanceId in ['${aws_instance.ctfd.id}']"
  }
}

resource "aws_security_group" "ctfd" {
  name   = "${local.name}-sg-ctfd"
  vpc_id = aws_vpc.default.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # security_groups = [aws_security_group.traefik.id]
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
