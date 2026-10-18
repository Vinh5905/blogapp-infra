# AWS tự thêm route local cho VPC CIDR. Ta chỉ thêm default route cần thiết.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.blogapp.id
  tags   = merge(local.cluster_tags, { Name = "${local.name}-public" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.blogapp.id
  tags   = merge(local.cluster_tags, { Name = "${local.name}-private" })
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.outbound.id
}

# Database chỉ có route local; không có default route ra IGW/NAT.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.blogapp.id
  tags   = merge(local.cluster_tags, { Name = "${local.name}-db" })
}

# Gắn đúng route table cho từng subnet.
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "database_a" {
  subnet_id      = aws_subnet.database_a.id
  route_table_id = aws_route_table.database.id
}

resource "aws_route_table_association" "database_b" {
  subnet_id      = aws_subnet.database_b.id
  route_table_id = aws_route_table.database.id
}
