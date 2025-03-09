resource "aws_ecr_repository" "default" {
  name = local.name
}

resource "aws_ecr_lifecycle_policy" "default" {
  repository = aws_ecr_repository.default.name

  policy = jsonencode({
    "rules" : [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_iam_openid_connect_provider" "gh_oidc" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "ci_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gh_oidc.arn]
    }
    condition {
      test = "StringLike"
      values = [
        "repo:cscosu/*:*",
      ]
      variable = "token.actions.githubusercontent.com:sub"
    }
    condition {
      test = "StringEquals"
      values = [
        "sts.amazonaws.com"
      ]
      variable = "token.actions.githubusercontent.com:aud"
    }
  }
}

data "aws_iam_policy_document" "ci" {
  statement {
    sid    = "GetAuthorizationToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      aws_ecr_repository.default.arn
    ]
  }
}

resource "aws_iam_role" "ci" {
  name               = "${local.name}-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_role.json
}

resource "aws_iam_role_policy" "ci" {
  role   = aws_iam_role.ci.name
  policy = data.aws_iam_policy_document.ci.json
}
