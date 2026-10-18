resource "aws_internet_gateway" "internet" {
  vpc_id = aws_vpc.blogapp.id
  tags   = merge(local.cluster_tags, { Name = local.name })
}
