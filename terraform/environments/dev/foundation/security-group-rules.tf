locals {
  node_security_groups = {
    control_plane = aws_security_group.control_plane.id
    worker        = aws_security_group.worker.id
  }
  api_client_security_groups = {
    control_plane = aws_security_group.control_plane.id
    worker        = aws_security_group.worker.id
    automation    = aws_security_group.automation.id
  }
  database_client_security_groups = {
    worker     = aws_security_group.worker.id
    automation = aws_security_group.automation.id
  }
  # Bốn chiều CP->CP, CP->worker, worker->CP, worker->worker.
  node_pairs = {
    for pair in setproduct(keys(local.node_security_groups), keys(local.node_security_groups)) :
    "${pair[0]}_to_${pair[1]}" => {
      source = local.node_security_groups[pair[0]]
      target = local.node_security_groups[pair[1]]
    }
  }
}

# 80 chỉ phục vụ listener redirect sang HTTPS khi bổ sung ALB.
resource "aws_vpc_security_group_ingress_rule" "alb_web" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  description       = "Public ALB HTTP redirect or HTTPS"
}

resource "aws_vpc_security_group_ingress_rule" "alb_to_ingress" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 30080
  to_port                      = 30080
  description                  = "ALB forwards HTTP to Traefik NodePort"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ingress" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "tcp"
  from_port                    = 30080
  to_port                      = 30080
  description                  = "ALB target traffic and health checks"
}

# Nodes join và automation truy cập API qua NLB. NLB sẽ được tạo ở bước LB.
resource "aws_vpc_security_group_ingress_rule" "api_clients" {
  for_each                     = local.api_client_security_groups
  security_group_id            = aws_security_group.api_nlb.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  description                  = "Kubernetes API from ${each.key}"
}

resource "aws_vpc_security_group_egress_rule" "api_clients" {
  for_each                     = local.api_client_security_groups
  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.api_nlb.id
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  description                  = "Kubernetes API through NLB"
}

resource "aws_vpc_security_group_ingress_rule" "api_vpn" {
  for_each          = toset(var.api_allowed_ipv4_cidrs)
  security_group_id = aws_security_group.api_nlb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  description       = "Kubernetes API from approved VPN CIDR"
}

resource "aws_vpc_security_group_ingress_rule" "nlb_to_api" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.api_nlb.id
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  description                  = "API targets and TCP health checks from NLB"
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_api" {
  security_group_id            = aws_security_group.api_nlb.id
  referenced_security_group_id = aws_security_group.control_plane.id
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  description                  = "API targets and TCP health checks"
}

# Direct API cần cho node và pod đã SNAT về node khi gọi kubernetes.default.
resource "aws_vpc_security_group_ingress_rule" "node_to_api" {
  for_each                     = local.node_security_groups
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  description                  = "Direct API from ${each.key} nodes"
}

resource "aws_vpc_security_group_egress_rule" "node_to_api" {
  for_each                     = local.node_security_groups
  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.control_plane.id
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  description                  = "Direct Kubernetes API"
}

resource "aws_vpc_security_group_ingress_rule" "etcd" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.control_plane.id
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
  description                  = "Stacked etcd between control plane nodes only"
}

resource "aws_vpc_security_group_egress_rule" "etcd" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.control_plane.id
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
  description                  = "Stacked etcd between control plane nodes only"
}

# CP gọi kubelet; metrics-server trên worker cần gọi kubelet cả hai nhóm node.
resource "aws_vpc_security_group_ingress_rule" "kubelet" {
  for_each                     = local.node_pairs
  security_group_id            = each.value.target
  referenced_security_group_id = each.value.source
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  description                  = "Kubelet API ${each.key}"
}

resource "aws_vpc_security_group_egress_rule" "kubelet" {
  for_each                     = local.node_pairs
  security_group_id            = each.value.source
  referenced_security_group_id = each.value.target
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  description                  = "Kubelet API ${each.key}"
}

# Baseline Calico VXLAN, không tự mở BGP/IPIP/Typha khi chưa dùng.
resource "aws_vpc_security_group_ingress_rule" "vxlan" {
  for_each                     = local.node_pairs
  security_group_id            = each.value.target
  referenced_security_group_id = each.value.source
  ip_protocol                  = "udp"
  from_port                    = 4789
  to_port                      = 4789
  description                  = "Calico VXLAN ${each.key}"
}

resource "aws_vpc_security_group_egress_rule" "vxlan" {
  for_each                     = local.node_pairs
  security_group_id            = each.value.source
  referenced_security_group_id = each.value.target
  ip_protocol                  = "udp"
  from_port                    = 4789
  to_port                      = 4789
  description                  = "Calico VXLAN ${each.key}"
}

resource "aws_vpc_security_group_ingress_rule" "mysql" {
  for_each                     = local.database_client_security_groups
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "MySQL from ${each.key}"
}

resource "aws_vpc_security_group_egress_rule" "mysql" {
  for_each                     = local.database_client_security_groups
  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "MySQL client to RDS"
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  for_each                     = local.api_client_security_groups
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Interface endpoint HTTPS from ${each.key}"
}

# HTTPS ra ngoài cho SSM, AWS API, image/package repositories qua NAT.
# Cũng bao gồm HTTPS tới interface endpoints khi bổ sung ở bước sau.
resource "aws_vpc_security_group_egress_rule" "bootstrap_https" {
  for_each          = local.api_client_security_groups
  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS for bootstrap, SSM and AWS APIs"
}
