resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "default" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-private-subnet"
  }
}

resource "aws_route_table" "default" {
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
    Name = "${local.name}-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.default.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.traefik.primary_network_interface_id
  }

  tags = {
    Name = "${local.name}-rt-private"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-subnet"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.default.id
}
