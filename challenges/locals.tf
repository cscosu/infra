locals {
  name           = "infra2"
  pretty_name    = "infra2"
  chall_domain   = "pwn.osucyber.club"
  domain_zone_id = "Z04227713ABUJ9WL56BCD" # osucyber.club

  instance_count_hackable = 24
  use_spot                = false

  cluster_name = "${local.name}-cluster"

  region = "us-east-2"

  out_dir = "./out"

  tag = "infra2"

  ecr_repository = "749980637880.dkr.ecr.us-east-2.amazonaws.com/bootcamp"
}
