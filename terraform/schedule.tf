data "aws_iam_policy_document" "eventbridge_ec2_schedule_role_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:RebootInstances",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "eventbridge_ec2_schedule_policy" {
  name        = "${local.name}-eventbridge-ec2-schedule"
  description = "Policy to allow EventBridge to stop and start EC2 instances"
  policy      = data.aws_iam_policy_document.eventbridge_ec2_schedule_role_policy.json
}

data "aws_iam_policy_document" "eventbridge_ec2_schedule_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_ec2_schedule_role" {
  name               = "${local.name}-eventbridge-ec2-schedule"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_ec2_schedule_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "eventbridge_ec2_schedule_attachment" {
  role       = aws_iam_role.eventbridge_ec2_schedule_role.name
  policy_arn = aws_iam_policy.eventbridge_ec2_schedule_policy.arn
}

resource "aws_scheduler_schedule" "ec2_start_schedule" {
  name = "${local.name}-ec2-start-schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 9 ? * * *)"
  schedule_expression_timezone = "US/Eastern"
  description                  = "Start instances event"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.eventbridge_ec2_schedule_role.arn

    input = jsonencode({
      InstanceIds = [
        aws_instance.auth.id,
        aws_instance.ctfd.id,
      ]
    })
  }
}

resource "aws_scheduler_schedule" "ec2_stop_schedule" {
  name = "${local.name}-ec2-stop-schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 1 ? * * *)"
  schedule_expression_timezone = "US/Eastern"
  description                  = "Stop instances event"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.eventbridge_ec2_schedule_role.arn

    input = jsonencode({
      InstanceIds = [
        aws_instance.auth.id,
        aws_instance.ctfd.id,
      ]
    })
  }
}
