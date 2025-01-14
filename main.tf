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
