# Đóng default SG của VPC mới. Workload dùng SG riêng trong security-groups.tf.
resource "aws_default_security_group" "closed" {
  vpc_id  = aws_vpc.blogapp.id
  ingress = []
  egress  = []
  tags    = merge(local.cluster_tags, { Name = "${local.name}-default" })
}
