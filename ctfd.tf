resource "aws_instance" "ctfd" {
  ami                         = data.aws_ami.ecs-optimized.id
  instance_type               = "t4g.small"
  subnet_id                   = aws_subnet.default.id
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance.name
  depends_on                  = [aws_internet_gateway.default]
  vpc_security_group_ids      = [aws_security_group.ctfd.id]
  associate_public_ip_address = false
  user_data_replace_on_change = true

  user_data = base64encode("#!/bin/bash\n\necho \"ECS_CLUSTER=${aws_ecs_cluster.default.name}\" > /etc/ecs/ecs.config\n")

  tags = {
    Name = "${local.name}-ec2-ctfd"
  }
}

resource "aws_ecs_task_definition" "ctfd" {
  family = "${local.name}-ecs-task-definition-ctfd"

  container_definitions = jsonencode([
    {
      name              = "ctfd"
      image             = "traefik/whoami:latest"
      memoryReservation = 200

      portMappings = [
        {
          containerPort = 80
          hostPort      = 32769
          name          = "ctfd"
        }
      ]

      dockerLabels = {
        "traefik.enable"                                        = "true"
        "traefik.http.routers.whoami.rule"                      = "Host(`whoami.osucyber.club`)"
        "traefik.http.services.whoami.loadbalancer.server.port" = "32769"
      }

      #   mountPoints = [
      #     {
      #       sourceVolume  = "redis-data"
      #       containerPath = "/data"
      #       readOnly      = false
      #     }
      #   ]
      systemControls = []

      #   healthCheck = {
      #     retries = 3
      #     command = [
      #       "CMD-SHELL",
      #       "redis-cli ping"
      #     ]
      #     timeout  = 3
      #     interval = 10
      #   }

      stopTimeout = 300
    }
  ])

  #   volume {
  #     name      = "redis-data"
  #     host_path = "/redis-data"
  #   }

  requires_compatibilities = []
  tags                     = {}
}

resource "aws_ecs_service" "ctfd" {
  depends_on      = [aws_iam_role_policy.ecs_cluster_permissions, aws_instance.ctfd, aws_ecs_cluster.default]
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
