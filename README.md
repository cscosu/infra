# Infra

[![Terraform v1.10.5](https://img.shields.io/badge/Terraform-v1.10.5-844fba?logo=terraform)](https://terraform.io)
[![AWS Terraform Provider v5.86.0](https://img.shields.io/badge/hashicorp/aws-v5.86.0-232f3e?logo=amazonwebservices)](https://registry.terraform.io/providers/hashicorp/aws/5.86.0)
[![Traefik v3](https://img.shields.io/badge/Traefik-v3-24a1c1?logo=traefikproxy)](https://traefik.io/traefik)
[![Terraform validation](https://github.com/cscosu/infra2/actions/workflows/terraform.yaml/badge.svg)](https://github.com/cscosu/infra2/actions/workflows/terraform.yaml)

## Principles

- Easy for newcomers
    - Don't use AWS if you can, since adding new users is a long administrative process (and AWS is expensive).
        - Use GitHub Pages for static sites.
        - Use GitHub Actions to upload Docker images, so updating the infra is as easy as pushing to GitHub.
    - Use solutions through the AWS Console UI as much as possible.
        - Use SSM for console access instead of managing SSH keys.
        - Use ECS to manage containers to get logs and management through the UI.
    - Document all changes.
        - See the [decision log](#decision-log) and update if after important decisions.
        - Keep the [infrastructure diagram](#infrastructure-diagram) up to date.
    - Don't make Terraform modules. Even if there is some duplicated code, most of the time each situation is different, and you end up adding weird flags to contort the same module into 2 different situations, making it harder to understand. This strategy encourages less complexity and using less resources since they all have to be copy/pasted every time.
- Infrastructure as Code
    - No modifications should be made through the AWS UI _**at all**_. It leads to drift, and is undocumented. This is infrastructure for a University club, and members cycle every ~2 years. It is very easy to create resources which nobody knows about and each cost $4/month or more, for no good reason.
    - Infrastructure is cattle, not pets. The entire infrastructure must survive coming up and down with `terraform destroy`, and `terraform apply`. Never SSH in and change the configuration file, instead edit the cloud init.
- Low cost
    - Don't prefer AWS managed solutions, as they are typically very expensive.
        - Instead of ELB, we self host Traefik.
        - Instead of Fargate, we use ECS on EC2.
        - Instead of RDS, we run a sidecar database with a snapshotted volume mount.
    - Use [calculator.aws](https://calculator.aws) to estimate costs when making decisions about infrastructure.
- Least privileges
    - Use IAM to scope permissions as tightly as possible.
    - Allow only the ports you need through security groups.
    - Avoid baking secrets.

## Infrastructure Diagram

## Recipes

### Deploy a new container

## Decision Log

This is a log of important decisions made to the infrastructure, reasoning why a decision was made, and why other options were not chosen. Minor changes, like deploying an extra container, do not necessarily need to be a part of the decisions log. However, changes to the _way_ the infrastructure works should be documented here for future generations.

### 2025-02-05: Traefik for redirects

Use Traefik docker labels for redirects. That is, all subdomains should redirect to [osucyber.club](https://osucyber.club) if they are no used by anything else. Also, certain subdomains like [discord.osucyber.club](https://discord.osucyber.club) should go to a Discord invite link. An alternative (which was used before) was to have an API Gateway in front of a Lambda function which handles redirects. However, this introduces more complexity and adds more resources added to Terraform. Using Traefik is more native since we already have it, and it requires only a small amount of configuration. Though, if Traefik is down, the redirects will stop working. Both options are free of cost, so we choose the most minimal option.

First introduced in [77d1d881](https://github.com/cscosu/infra2/commit/77d1d8816cf29184120fc5c5df5193bd379b3052).

### 2025-02-02: Minimize root disk space

Use minimal AMI instead of ECS optimized AMI. The ECS optimized AMI requires a minimum of a 30GB root volume, however we really only need a 4GB root volume. At $0.08/GB/month, this means $2.08/instance/month saved. The ECS agent cleans up old images every 30 minutes by default ([docs](https://github.com/aws/amazon-ecs-agent/blob/0f876b5372c9ecb15228f607f11d2c4be629d364/README.md#L206)), so there is little reason to worry about running out of storage. Additionally, it is easy to change the root storage if needed by just modifying the Terraform. This comes at a maintenance cost of additional user data script to install the required agents, though this should be just copy/paste.

First introduced in [01d3644e](https://github.com/cscosu/infra2/commit/01d3644e9409ea7f49968668dbd3ba844508d313).

### 2025-02-02: Explicitly set availability zone

The EC2 instance, EBS volume, and subnet need to all be in the same availability zone. Before, this was implicitly set. Now, `us-east-2b` was chosen as the availability zone. `us-east-2a` is probably the "default" and most common. We want our spot instances to have the most availability, so we want to be on a less popular AZ. There is no evidence to support this theory, but it sounds true. Specifying an AZ as a Terraform local also helps reduce an implicit dependency between the `aws_instance` and `aws_ebs_volume` so that the `aws_ebs_volume` doesn't need to be destroyed if the `aws_instance` needs to be destroyed.

First introduced in [01d3644e](https://github.com/cscosu/infra2/commit/01d3644e9409ea7f49968668dbd3ba844508d313).

### 2025-01-31: Route53 DNS-01 HTTPS Letsencrypt challenge

Wildcard certificates are particularly useful for the bootcamp because each challenge is on its own subdomain. For Letsencrypt requires a [DNS-01 challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) to get a wildcard certificate. Basically, they need to verify that you own the domain, not just a single subdomain of it like in the HTTP-01 challenge, which requires setting a TXT DNS record. This is handled automatically and with least privileges by only giving Traefik the ability to modify the single record required through IAM.

First introduced in [35afe9b4](https://github.com/cscosu/infra2/commit/35afe9b4c86ba4c5528f753064953ee52239e9bd).

### 2025-01-30: CTFd all in one instance

CTFd additionally needs MySQL and Redis to run. RDS MySQL costs $11/month, and ElastiCache Redis costs $11/month. In the previous infra, these managed AWS solutions were used, and had at most 3% average utilization. Also, these still do not update for free or anything. To be more cost effective, CTFd, MariaDB, and Redis now all run on a single ARM `t4g.small` (2 vCPUs, 2GiB RAM) spot instance with a 20GB EBS volume mounted, which costs a total of $3.92/month.

### 2025-01-29: ECR Container Registry uploading

To reduce friction of setting up credentials, and to encourage tracking containers in Git, GitHub Actions in all repositories under the `cscosu` org can upload Docker images to the ECR. See the [docker-template](https://github.com/cscosu/docker-template/blob/master/.github/workflows/build.yaml) as an example. No keys or secrets need to be set up. This means anyone with push permissions can upload containers, but the only ones who can do that are the engineers, who we can trust. The ease of use tradeoff is worth the "security" risk.

If a container with the same name is uploaded to the ECR as one that exists, it will be updated. So the ECS task can be restarted to pick up the new container, allowing for easy updates.

First introduced in [8857f627](https://github.com/cscosu/infra2/commit/8857f627cdcbc8a64d78eb4fb4e66176b6a64006).

### 2025-01-15: Custom NAT

Public IPv4 addresses are expensive at $3.65/month. Instances without public IPs cannot access the public internet, which is problematic because they need access to the public internet to register themselves to AWS as ECS container instance hosts, to have SSM console terminal access, and also many apps and challenges require internet access (like a Discord bot). The normal AWS solution to this is a NAT Gateway, however that costs $32.85/month so it is definitely not worth it. Another solution is using AWS PrivateLink VPC Interface Endpoints, but that costs $7.30/month and only solves the ECS and SSM issues and not the public internet access issue. To solve this, and for cost effectiveness, the Traefik instance also serves as a custom NAT device using an `iptables` rule.

First introduced in [54157d18](https://github.com/cscosu/infra2/commit/54157d1862129a2b99ee7c0a0da1e5680b1d893a).

### 2025-01-14: Use SSM to log in to instances

Managing SSH keys is frustrating, especially for new users, and storing them in the Terraform state is somewhat scary. Additionally, maintaining a bastion host to access internal instances costs money and increases complexity. AWS SSM allows for terminal access directly in the AWS console to all instances, is tracked to the user who logged in, and is free. SSM is pretty easy to activate, using IAM policies, and overall significantly reduces the time-to-contribution for newcomers to AWS and to our infra.

First introduced in [9021ec0b](https://github.com/cscosu/infra2/commit/9021ec0b1693b0869738efd3843396346bb37bb7#diff-7a94499a9e5aa4a679628391654ebc42fde806a4c2479d2ca390b75614118b23R266).

### 2025-01-07: The beginning

Our infrastructure is simple in theory, all we need to do is run containers. We cannot use Fargate because the bootcamp requires challenges that need `--privileged`. Also, it is more expensive than EC2 backed ECS for 24/7 running apps like our Discord bot.

AWS ELB costs $16.43/month, which is very expensive. Instead, we use Traefik on an EC2 instance within the same ECS cluster as everything else. Traefik runs on an ARM `t4g.nano` (2 vCPUs, 0.5GiB RAM) spot instance for $1.68/month just fine for the traffic that we get. In the future it may be worth making this instance a non-spot instance since if it goes down, everything goes down since it is our ingress. However that is a very easy change, so for now we will see if we run into problems using spot.
