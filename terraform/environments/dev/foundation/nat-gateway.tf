# Elastic IP public của đường ra Internet qua NAT.
resource "aws_eip" "nat" {
  domain     = "vpc"
  tags       = merge(local.cluster_tags, { Name = "${local.name}-${var.availability_zones[0]}" })
  depends_on = [aws_internet_gateway.internet]
}

# Một NAT ở public subnet đầu tiên, dùng chung cho hai private subnet.
resource "aws_nat_gateway" "outbound" {
  allocation_id     = aws_eip.nat.id
  subnet_id         = aws_subnet.public_a.id
  connectivity_type = "public"
  tags              = merge(local.cluster_tags, { Name = "${local.name}-${var.availability_zones[0]}" })
  depends_on        = [aws_route.public_default]
}
