terraform {
  backend "s3" {
    key    = "terraform.tfstate"
    bucket = "infra2-tf-state"
    region = "us-east-2"
  }
}

provider "aws" {
  region  = local.region
  profile = "default"
}

resource "aws_cloudwatch_log_group" "default" {
  name              = "/core"
  retention_in_days = 90
}
