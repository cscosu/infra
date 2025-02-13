resource "aws_eip" "traefik" {
  instance = aws_instance.traefik.id
  domain   = "vpc"
  tags = {
    Name = "traefik-eip-${terraform.workspace}"
  }
}

resource "aws_instance" "traefik" {
  ami                         = data.aws_ami.minimal-arm64.id
  availability_zone           = local.availability_zone
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.public.id
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance.name
  vpc_security_group_ids      = [aws_security_group.traefik.id]
  source_dest_check           = false
  associate_public_ip_address = true
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 4
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

    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    cat <<EOF > /etc/systemd/system/nat-setup.service
    [Unit]
    Description=Setup NAT routing
    After=docker.service
    Requires=docker.service
    PartOf=docker.service

    [Service]
    Type=oneshot
    ExecStart=/usr/sbin/iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
    ExecStop=/usr/sbin/iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
    RemainAfterExit=yes

    [Install]
    WantedBy=docker.service
    Also=docker.service
    EOF

    systemctl daemon-reload
    systemctl enable nat-setup
    systemctl start nat-setup
    systemctl enable ecs
    systemctl start --no-block ecs
    INIT
  )

  tags = {
    Name = "${local.name}-ec2-traefik"
  }
}

resource "aws_ecs_task_definition" "traefik" {
  family        = "${local.name}-ecs-task-definition-traefik"
  task_role_arn = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name              = "traefik"
      image             = "traefik:v3.3.3"
      memoryReservation = 200
      essential         = true

      environment = [
        { name = "AWS_DEFAULT_REGION", value = local.region },
        { name = "TRAEFIK_PROVIDERS_ECS_CLUSTERS", value = aws_ecs_cluster.default.id },
        { name = "TRAEFIK_PROVIDERS_ECS_EXPOSEDBYDEFAULT", value = "false" },
        { name = "TRAEFIK_PROVIDERS_ECS_REFRESHSECONDS", value = "15" },
        # { name = "TRAEFIK_PROVIDERS_ECS_HEALTHYTASKSONLY", value = "true" },
        { name = "TRAEFIK_PING", value = "true" },
        { name = "TRAEFIK_LOG_LEVEL", value = "INFO" },
        { name = "TRAEFIK_LOG_FORMAT", value = "json" },
        { name = "TRAEFIK_ACCESSLOG", value = "true" },
        { name = "TRAEFIK_ACCESSLOG_FORMAT", value = "json" },
        { name = "TRAEFIK_ENTRYPOINTS_WEB_ADDRESS", value = ":80" },
        { name = "TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO", value = "websecure" },
        { name = "TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS", value = ":443" },
        { name = "TRAEFIK_ENTRYPOINTS_WEBSECURE_HTTP_TLS_CERTRESOLVER", value = "letsencrypt" },
        { name = "TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL", value = "cscosu@gmail.com" },
        { name = "TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_KEYTYPE", value = "EC384" },
        { name = "TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER", value = "route53" },
        { name = "TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE", value = "/etc/traefik/acme/acme.json" },
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
        "traefik.enable" = "true"

        "traefik.http.routers.catchall.rule"                                  = "HostRegexp(`^.+\\.testing\\.osucyber\\.club$`)"
        "traefik.http.routers.catchall.priority"                              = "1"
        "traefik.http.routers.catchall.middlewares"                           = "redirect-to-main"
        "traefik.http.middlewares.redirect-to-main.redirectregex.regex"       = ".*"
        "traefik.http.middlewares.redirect-to-main.redirectregex.replacement" = "https://osucyber.club"

        "traefik.http.routers.discord.rule"                                       = "Host(`discord.testing.osucyber.club`)"
        "traefik.http.routers.discord.middlewares"                                = "redirect-discord"
        "traefik.http.middlewares.redirect-discord.redirectregex.regex"           = ".*"
        "traefik.http.middlewares.redirect-discord.redirectregex.replacement"     = "https://discord.gg/x4VgQBTBCp"
        "traefik.http.routers.zoom.rule"                                          = "Host(`zoom.testing.osucyber.club`)"
        "traefik.http.routers.zoom.middlewares"                                   = "redirect-zoom"
        "traefik.http.middlewares.redirect-zoom.redirectregex.regex"              = ".*"
        "traefik.http.middlewares.redirect-zoom.redirectregex.replacement"        = "https://osu.zoom.us/j/94385413286?pwd=L2pHUEc0blZqV0Erc3pNeWxRTW4vUT09"
        "traefik.http.routers.mailinglist.rule"                                   = "Host(`mailinglist.testing.osucyber.club`)"
        "traefik.http.routers.mailinglist.middlewares"                            = "redirect-mailinglist"
        "traefik.http.middlewares.redirect-mailinglist.redirectregex.regex"       = ".*"
        "traefik.http.middlewares.redirect-mailinglist.redirectregex.replacement" = "https://eepurl.com/c0qMHn"
        "traefik.http.routers.attend.rule"                                        = "Host(`attend.testing.osucyber.club`)"
        "traefik.http.routers.attend.middlewares"                                 = "redirect-attend"
        "traefik.http.middlewares.redirect-attend.redirectregex.regex"            = ".*"
        "traefik.http.middlewares.redirect-attend.redirectregex.replacement"      = "https://auth.osucyber.club"
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.default.name
          "awslogs-region"        = local.region,
          "awslogs-stream-prefix" = "traefik",
        }
      }

      mountPoints = [
        {
          sourceVolume  = "certs"
          containerPath = "/etc/traefik/acme"
          readOnly      = false
        }
      ]

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

  volume {
    name      = "certs"
    host_path = "/certs"
  }
}

resource "aws_ecs_service" "traefik" {
  depends_on      = [aws_iam_role_policy.ecs_cluster_permissions]
  name            = "${local.name}-ecs-service-traefik"
  cluster         = aws_ecs_cluster.default.id
  task_definition = aws_ecs_task_definition.traefik.arn
  desired_count   = 1

  placement_constraints {
    type       = "memberOf"
    expression = "ec2InstanceId in ['${aws_instance.traefik.id}']"
  }
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

resource "aws_iam_role" "task_role" {
  name               = "${local.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "traefik" {
  role   = aws_iam_role.task_role.id
  policy = data.aws_iam_policy_document.traefik.json
}

data "aws_iam_policy_document" "traefik" {
  statement {
    # Traefik ECS Plugin
    effect = "Allow"
    actions = [
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "ecs:DescribeContainerInstances",
      "ecs:DescribeTaskDefinition",
      "ec2:DescribeInstances",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:GetChange"
    ]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZonesByName"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListResourceRecordSets"
    ]
    resources = [
      "arn:aws:route53:::hostedzone/${local.domain_zone_id}"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      "arn:aws:route53:::hostedzone/${local.domain_zone_id}"
    ]
    condition {
      test     = "StringEquals"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["_acme-challenge.testing.${local.domain}"]
    }
    condition {
      test     = "StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }
  }
}

resource "aws_route53_record" "wildcard_domain_record" {
  count   = 1
  zone_id = local.domain_zone_id
  name    = "*.testing.${local.domain}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.traefik.public_ip]
}
