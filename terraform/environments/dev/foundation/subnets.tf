# Mỗi subnet thuộc một AZ. a/b là vị trí trong availability_zones.
# Public/private được phân biệt bằng route table, không phải tên resource.
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.blogapp.id
  cidr_block              = "10.10.0.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = false
  tags                    = merge(local.cluster_tags, { Name = "${local.name}-public-${var.availability_zones[0]}" })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.blogapp.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = false
  tags                    = merge(local.cluster_tags, { Name = "${local.name}-public-${var.availability_zones[1]}" })
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.blogapp.id
  cidr_block              = "10.10.10.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = false
  tags                    = merge(local.cluster_tags, { Name = "${local.name}-private-${var.availability_zones[0]}" })
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.blogapp.id
  cidr_block              = "10.10.11.0/24"
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = false
  tags                    = merge(local.cluster_tags, { Name = "${local.name}-private-${var.availability_zones[1]}" })
}

resource "aws_subnet" "database_a" {
  vpc_id                  = aws_vpc.blogapp.id
  cidr_block              = "10.10.20.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = false
  tags                    = merge(local.cluster_tags, { Name = "${local.name}-db-${var.availability_zones[0]}" })
}

resource "aws_subnet" "database_b" {
  vpc_id                  = aws_vpc.blogapp.id
  cidr_block              = "10.10.21.0/24"
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = false
  tags                    = merge(local.cluster_tags, { Name = "${local.name}-db-${var.availability_zones[1]}" })
}
