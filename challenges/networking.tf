resource "aws_vpc" "ctf_main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name  = local.name
    event = local.tag
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.ctf_main.id

  tags = {
    Name  = "${local.name}-igw"
    event = local.tag
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

### No Hack ###

resource "aws_subnet" "nohack_subnet" {
  vpc_id                  = aws_vpc.ctf_main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name  = "${local.name}-nohack"
    event = local.tag
  }
}

resource "aws_route_table" "nohack_rt" {
  vpc_id = aws_vpc.ctf_main.id

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.internet_gateway.id
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name  = "${local.name}-nohack-rt"
    event = local.tag
  }
}

resource "aws_route_table_association" "nohack_rt" {
  subnet_id      = aws_subnet.nohack_subnet.id
  route_table_id = aws_route_table.nohack_rt.id
}

### Hackable Challenges ###

resource "aws_subnet" "hack_subnet" {
  vpc_id                  = aws_vpc.ctf_main.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name  = "${local.name}-hack"
    event = local.tag
  }
}

resource "aws_route_table" "hack_rt" {
  vpc_id = aws_vpc.ctf_main.id

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.internet_gateway.id
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name  = "${local.name}-hack-rt"
    event = local.tag
  }
}

resource "aws_route_table_association" "hack_rt" {
  subnet_id      = aws_subnet.hack_subnet.id
  route_table_id = aws_route_table.hack_rt.id
}

### Route 53 ###

resource "aws_route53_record" "chall_domain_record" {
  count   = 1
  zone_id = local.domain_zone_id
  name    = local.chall_domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.traefik.public_ip]
}

resource "aws_route53_record" "wildcard_chall_domain_record" {
  count   = 1
  zone_id = local.domain_zone_id
  name    = "*.${local.chall_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.traefik.public_ip]
}
