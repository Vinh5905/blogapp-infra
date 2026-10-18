# Chỉ tạo SG ở đây; rules được quản lý riêng trong security-group-rules.tf.
# Không khai báo inline ingress/egress trên các SG workload.
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Public ALB"
  vpc_id      = aws_vpc.blogapp.id
  tags        = merge(local.cluster_tags, { Name = "${local.name}-alb" })
}

resource "aws_security_group" "api_nlb" {
  name        = "${local.name}-api-nlb"
  description = "Kubernetes API NLB"
  vpc_id      = aws_vpc.blogapp.id
  tags        = merge(local.cluster_tags, { Name = "${local.name}-api-nlb" })
}

resource "aws_security_group" "control_plane" {
  name        = "${local.name}-control-plane"
  description = "Kubernetes control plane nodes"
  vpc_id      = aws_vpc.blogapp.id
  tags        = merge(local.cluster_tags, { Name = "${local.name}-control-plane" })
}

resource "aws_security_group" "worker" {
  name        = "${local.name}-worker"
  description = "Kubernetes worker nodes"
  vpc_id      = aws_vpc.blogapp.id
  tags        = merge(local.cluster_tags, { Name = "${local.name}-worker" })
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "MySQL from workers and DB automation"
  vpc_id      = aws_vpc.blogapp.id
  tags        = merge(local.cluster_tags, { Name = "${local.name}-rds" })
}

resource "aws_security_group" "automation" {
  name        = "${local.name}-automation"
  description = "Automation host managed through SSM without inbound SSH"
  vpc_id      = aws_vpc.blogapp.id
  tags        = merge(local.cluster_tags, { Name = "${local.name}-automation" })
}

resource "aws_security_group" "endpoints" {
  name        = "${local.name}-endpoints"
  description = "Interface endpoints for nodes and automation"
  vpc_id      = aws_vpc.blogapp.id
  tags        = merge(local.cluster_tags, { Name = "${local.name}-endpoints" })
}
