resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name = local.name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.availability_zone

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.default.id
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = local.availability_zone

  tags = {
    Name = "${local.name}-private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.default.id

  # The default route in the private subnet is to use the Traefik instance as a
  # NAT device. Instances in the private subnet do not have public IPs, so they
  # have to use another instance's public IP to connect to the internet. Traefik
  # itself does not do this, it can be any instance configured to forward IP
  # packets, but we just reuse the Traefik instance for this purpose since it
  # already has a public IP.
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.traefik.primary_network_interface_id
  }

  tags = {
    Name = "${local.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
