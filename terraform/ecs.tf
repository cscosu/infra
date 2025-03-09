resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${local.name}-ecs-instance"
  role = aws_iam_role.ecs_instance.name
}

resource "aws_iam_role" "ecs_instance" {
  name               = "${local.name}-ecs-instance"
  assume_role_policy = data.aws_iam_policy_document.ecs_instance.json
}

resource "aws_iam_role_policy" "ecs_cluster_permissions" {
  name   = "${local.name}-ecs-cluster-permissions"
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
      # AWS ECS Agent
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:StartTelemetrySession",

      # Allow downloading images from private ECR
      "ecr:GetAuthorizationToken",

      "logs:CreateLogStream",
      "logs:PutLogEvents",

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
      "ssmmessages:OpenDataChannel",
    ]
    resources = [
      "*"
    ]
  }

  # Allow downloading images from private ECR
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      aws_ecr_repository.default.arn
    ]
  }

  # AWS ECS Agent
  statement {
    effect = "Allow"
    actions = [
      "ecs:DeregisterContainerInstance",
      "ecs:RegisterContainerInstance",
      "ecs:SubmitContainerStateChange",
      "ecs:SubmitTaskStateChange",
    ]
    resources = [
      aws_ecs_cluster.default.arn
    ]
  }
}

resource "aws_ecs_cluster" "default" {
  name = local.name
}

data "aws_ami" "minimal-arm64" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-minimal-hvm*"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}
