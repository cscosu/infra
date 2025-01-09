resource "tls_private_key" "challenges_private_key" {
  algorithm = "RSA"
}

resource "local_file" "challenges_private_key" {
  content         = tls_private_key.challenges_private_key.private_key_pem
  filename        = "${local.out_dir}/challenges_key.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "ecs" {
  key_name   = "${local.cluster_name}-challenges"
  public_key = tls_private_key.challenges_private_key.public_key_openssh
}

resource "aws_ecs_cluster" "challenge_cluster" {
  name = local.cluster_name

  tags = {
    Name  = "${local.name}-ecs-cluster"
    event = local.tag
  }
}

data "template_file" "ecs_launchdata" {
  template = file("ecs/launchdata.sh")
  vars = {
    ecs_cluster = local.cluster_name
  }
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}

resource "aws_launch_template" "ecs_server_template" {
  name_prefix   = "${local.cluster_name}-challenge-server-template"
  image_id      = "ami-0f234b7d5e6637a6f"
  instance_type = "t3.medium"
  key_name      = aws_key_pair.ecs.key_name

  tags = {
    event = local.tag
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs.id, aws_security_group.allow_bastion_ssh.id]
  }

  user_data              = base64encode(data.template_file.ecs_launchdata.rendered)
  ebs_optimized          = false
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 100
    }
  }
}

resource "aws_autoscaling_group" "ecs_server_autoscale" {
  name                = "${local.cluster_name}-ecs-hackable"
  min_size            = local.instance_count_hackable - 8
  max_size            = local.instance_count_hackable + 8
  desired_capacity    = local.instance_count_hackable
  vpc_zone_identifier = [aws_subnet.hack_subnet.id]

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = local.use_spot ? 0 : local.instance_count_hackable
      on_demand_percentage_above_base_capacity = local.use_spot ? 0 : 100
      spot_allocation_strategy                 = "lowest-price"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs_server_template.id
      }

      override {
        instance_type     = "t3.medium"
        weighted_capacity = "4"
      }

      override {
        instance_type     = "t3.large"
        weighted_capacity = "8"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "ECS ${local.cluster_name} - Hackable"
    propagate_at_launch = true
  }

  tag {
    key                 = "event"
    value               = local.tag
    propagate_at_launch = true
  }
}

resource "aws_security_group" "ecs" {
  name        = "${local.cluster_name}-ecs-sg"
  description = "Container Instance Allowed Ports"
  vpc_id      = aws_vpc.ctf_main.id

  ingress {
    from_port       = 40000
    to_port         = 42000
    protocol        = "tcp"
    security_groups = [aws_security_group.traefik.id]
  }

  ingress {
    from_port       = 45000
    to_port         = 45010
    protocol        = "tcp"
    security_groups = [aws_security_group.traefik.id]
  }

  ingress {
    from_port       = 7000
    to_port         = 7100
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

  tags = {
    Name  = "${local.name}-ecs-sg"
    event = local.tag
  }
}

### IAM ###

/* ecs iam role and ecs-policies */
resource "aws_iam_role" "ecs_role" {
  name               = "${local.cluster_name}-ecs-role"
  assume_role_policy = file("ecs/role.json")
}

/**
 * IAM profile to be used in auto-scaling launch configuration.
 */
resource "aws_iam_instance_profile" "ecs" {
  name = "${local.cluster_name}-ecs-instance-profile"
  path = "/"
  role = aws_iam_role.ecs_role.id

  tags = {
    event = local.tag
  }
}

data "template_file" "ecs_instance_role_policy" {
  template = file("ecs/instance-role-policy.json")

  vars = {
    cluster_arn = aws_ecs_cluster.challenge_cluster.arn
    ecr_name    = split("/", local.ecr_repository)[1]
  }
}

/* ec2 container instance role & policy */
resource "aws_iam_role_policy" "ecs_instance_role_policy" {
  name   = "${local.cluster_name}-ecs-instance-role-policy"
  policy = data.template_file.ecs_instance_role_policy.rendered
  role   = aws_iam_role.ecs_role.id
}

/* ecs service scheduler role */

data "template_file" "ecs_service_role_policy" {
  template = file("ecs/service-role-policy.json")
}

resource "aws_iam_role_policy" "ecs_service_role_policy" {
  name   = "${local.cluster_name}-ecs-service-role-policy"
  policy = data.template_file.ecs_service_role_policy.rendered
  role   = aws_iam_role.ecs_role.id
}
