resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
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

data "aws_availability_zones" "default" {
  state = "available"
}

resource "aws_subnet" "default" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = data.aws_availability_zones.default.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-subnet"
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

resource "aws_route_table_association" "default" {
  subnet_id      = aws_subnet.default.id
  route_table_id = aws_route_table.default.id
}
