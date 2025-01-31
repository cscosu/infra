
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
      # AWS ECS Agent
      "ecs:DeregisterContainerInstance",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:RegisterContainerInstance",
      "ecs:StartTelemetrySession",
      "ecs:SubmitContainerStateChange",
      "ecs:SubmitTaskStateChange",

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
      "ssmmessages:OpenDataChannel"
    ]
    resources = [
      "*"
    ]
  }

  #   statement {
  #     effect = "Allow"
  #     actions = [
  #       "logs:CreateLogStream",
  #       "logs:PutLogEvents",
  #     ]
  #     resources = [
  #       "arn:aws:logs:*:*:*"
  #     ]
  #   }
}

resource "aws_ecs_cluster" "default" {
  name = "${local.name}-cluster"
}

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
