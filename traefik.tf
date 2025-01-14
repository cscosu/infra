resource "tls_private_key" "traefik" {
  algorithm = "RSA"
}

resource "local_file" "traefik_private_key" {
  content         = tls_private_key.traefik.private_key_pem
  filename        = "${local.out_dir}/traefik_key.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "traefik" {
  key_name   = "${local.name}-ssh-key-traefik"
  public_key = tls_private_key.traefik.public_key_openssh
}

# resource "aws_eip" "traefik" {
#   domain = "vpc"
#   tags = {
#     Name = "traefik-eip-${terraform.workspace}"
#   }
# }

data "aws_ami" "ecs-optimized" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm*"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id             = aws_vpc.default.id
  service_name       = "com.amazonaws.${local.region}.ssm"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = [aws_subnet.default.id]
  security_group_ids = [aws_security_group.traefik.id, aws_security_group.ctfd.id]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id             = aws_vpc.default.id
  service_name       = "com.amazonaws.${local.region}.ssmmessages"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = [aws_subnet.default.id]
  security_group_ids = [aws_security_group.traefik.id, aws_security_group.ctfd.id]

  private_dns_enabled = true
}

resource "aws_instance" "traefik" {
  ami                  = data.aws_ami.ecs-optimized.id
  instance_type        = "t4g.nano"
  subnet_id            = aws_subnet.default.id
  key_name             = aws_key_pair.traefik.key_name
  iam_instance_profile = aws_iam_instance_profile.ecs_instance.name

  vpc_security_group_ids = [
    aws_security_group.traefik.id,
  ]

  associate_public_ip_address = true

  user_data = base64encode("#!/bin/bash\n\necho \"ECS_CLUSTER=${aws_ecs_cluster.default.name}\" > /etc/ecs/ecs.config\n")

  tags = {
    Name = "${local.name}-ec2-traefik"
  }
}

resource "aws_ecs_cluster" "default" {
  name = "${local.name}-cluster"
}

resource "aws_ecs_task_definition" "traefik" {
  family = "${local.name}-ecs-task-definition-traefik"

  container_definitions = jsonencode([
    {
      name              = "traefik"
      image             = "arm64v8/traefik:v3.3.1"
      memoryReservation = 200
      essential         = true

      environment = [
        {
          name  = "TRAEFIK_PROVIDERS_ECS_CLUSTERS"
          value = aws_ecs_cluster.default.id,
        },
        {
          name  = "TRAEFIK_PROVIDERS_ECS_AUTODISCOVERCLUSTERS"
          value = "false",
        },
        {
          name  = "TRAEFIK_PROVIDERS_ECS_EXPOSEDBYDEFAULT",
          value = "false",
        },
        {
          name  = "TRAEFIK_PING",
          value = "true"
        },
        {
          name  = "TRAEFIK_ENTRYPOINTS_WEB_ADDRESS",
          value = ":80"
        },
        # {
        #   name  = "TRAEFIK_PROVIDERS_ECS_HEALTHYTASKSONLY",
        #   value = "true"
        # },
        {
          name  = "TRAEFIK_PROVIDERS_ECS_REFRESHSECONDS",
          value = "15"
        },
        {
          name  = "TRAEFIK_LOG_FILEPATH",
          value = "/traefiklogs",
        },
        {
          name  = "TRAEFIK_LOG_LEVEL",
          value = "TRACE",
        }
      ]

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        },
        {
          containerPort = 443
          hostPort      = 443
        },
      ]

      dockerLabels = {
        "traefik.enable"                                       = "true"
        "traefik.http.middlewares.retry.retry.attempts"        = "4"
        "traefik.http.middlewares.retry.retry.initialInterval" = "100ms"
      }

      #   logConfiguration = {
      #     logDriver = "awslogs"
      #     options = {
      #       "awslogs-group"         = aws_cloudwatch_log_group.cluster.name
      #       "awslogs-region"        = locals.region,
      #       "awslogs-stream-prefix" = "traefik"
      #     }
      #   }

      healthCheck = {
        retries = 3
        command = [
          "CMD-SHELL",
          "traefik healthcheck"
        ]
        timeout  = 3
        interval = 10
      }

      stopTimeout = 300
    }
  ])

  requires_compatibilities = []
  tags                     = {}
}

resource "aws_ecs_service" "traefik" {
  name            = "${local.name}-ecs-service-traefik"
  cluster         = aws_ecs_cluster.default.id
  task_definition = aws_ecs_task_definition.traefik.arn
  desired_count   = 1
}

resource "aws_security_group" "traefik" {
  name   = "${local.name}-sg-traefik"
  vpc_id = aws_vpc.default.id

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

  ingress {
    from_port       = 22
    to_port         = 22
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

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${local.name}-iam-instance-profile-ecs-instance"
  role = aws_iam_role.ecs_instance.name
}

resource "aws_iam_role" "ecs_instance" {
  name               = "${local.name}-iam-role-ecs-instance"
  assume_role_policy = data.aws_iam_policy_document.ecs_instance.json
}

resource "aws_iam_role_policy" "ecs_cluster_permissions" {
  name   = "${local.name}-iam-role-policy-ecs-cluster-permissions"
  role   = aws_iam_role.ecs_instance.id
  policy = data.aws_iam_policy_document.ecs_cluster_permissions.json
}

data "aws_iam_policy_document" "ecs_instance" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "ecs_cluster_permissions" {
  statement {
    effect = "Allow"
    actions = [
      # Traefik ECS Plugin
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "ecs:DescribeContainerInstances",
      "ecs:DescribeTaskDefinition",
      "ec2:DescribeInstances",

      # AWS ECS Agent
      "ecs:DeregisterContainerInstance",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:RegisterContainerInstance",
      "ecs:StartTelemetrySession",
      "ecs:SubmitContainerStateChange",
      "ecs:SubmitTaskStateChange",

      # SSM, AWS web UI shell
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = [
      "*"
    ]
  }
}
