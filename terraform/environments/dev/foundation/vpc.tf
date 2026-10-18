# VPC là không gian mạng; resource này chưa tạo subnet, route hay EC2.
resource "aws_vpc" "blogapp" {
  cidr_block                       = local.vpc_cidr
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = false
  tags                             = merge(local.cluster_tags, { Name = local.name })
  depends_on                       = [data.aws_availability_zones.available]
}
