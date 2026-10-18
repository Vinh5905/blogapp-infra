# Mock provider: mọi resource chỉ được giả lập trong test, không gọi AWS.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-southeast-1a", "ap-southeast-1b"]
    }
  }
}

variables {
  availability_zones = ["ap-southeast-1a", "ap-southeast-1b"]
}

run "network_paths" {
  command = apply

  assert {
    condition = (
      aws_route.public_default.route_table_id == aws_route_table.public.id &&
      aws_route.public_default.gateway_id == aws_internet_gateway.internet.id &&
      aws_route.private_default.route_table_id == aws_route_table.private.id &&
      aws_route.private_default.nat_gateway_id == aws_nat_gateway.outbound.id
    )
    error_message = "Public egress must use IGW; private egress must use NAT."
  }

  assert {
    condition = (
      aws_nat_gateway.outbound.subnet_id == aws_subnet.public_a.id &&
      aws_nat_gateway.outbound.allocation_id == aws_eip.nat.id &&
      aws_nat_gateway.outbound.connectivity_type == "public"
    )
    error_message = "Place the single public NAT in the first public subnet with its EIP."
  }

  assert {
    condition = (
      aws_route_table_association.database_a.route_table_id == aws_route_table.database.id &&
      aws_route_table_association.database_b.route_table_id == aws_route_table.database.id &&
      aws_route_table.database.id != aws_route_table.private.id &&
      aws_route_table.database.id != aws_route_table.public.id
    )
    error_message = "Database subnets must have their own route table."
  }

  assert {
    condition = alltrue([
      !aws_subnet.public_a.map_public_ip_on_launch,
      !aws_subnet.public_b.map_public_ip_on_launch,
      !aws_subnet.private_a.map_public_ip_on_launch,
      !aws_subnet.private_b.map_public_ip_on_launch,
      !aws_subnet.database_a.map_public_ip_on_launch,
      !aws_subnet.database_b.map_public_ip_on_launch,
    ])
    error_message = "Do not automatically assign public IPs to EC2 in these subnets."
  }

  assert {
    condition = (
      length(aws_default_security_group.closed.ingress) == 0 &&
      length(aws_default_security_group.closed.egress) == 0 &&
      length(aws_db_subnet_group.database.subnet_ids) == 2 &&
      aws_subnet.database_a.availability_zone != aws_subnet.database_b.availability_zone
    )
    error_message = "Keep the default SG closed and database subnets in two AZs."
  }

  assert {
    condition = (
      length(output.public_subnet_ids) == 2 &&
      length(output.private_subnet_ids) == 2 &&
      length(output.database_subnet_ids) == 2 &&
      length(output.nat_gateway_ids) == 1
    )
    error_message = "Preserve the subnet and single-NAT output contract."
  }

  assert {
    condition = (
      aws_vpc.blogapp.enable_dns_support &&
      aws_vpc.blogapp.enable_dns_hostnames &&
      aws_subnet.public_a.availability_zone == aws_subnet.private_a.availability_zone &&
      aws_subnet.private_a.availability_zone == aws_subnet.database_a.availability_zone &&
      aws_subnet.public_b.availability_zone == aws_subnet.private_b.availability_zone &&
      aws_subnet.private_b.availability_zone == aws_subnet.database_b.availability_zone &&
      output.subnets_by_az["ap-southeast-1a"].private_subnet_id == aws_subnet.private_a.id &&
      output.subnets_by_az["ap-southeast-1b"].private_subnet_id == aws_subnet.private_b.id
    )
    error_message = "Enable VPC DNS and preserve subnet AZ mapping for cluster consumers."
  }
}

run "reject_unavailable_zone" {
  command = plan
  variables {
    availability_zones = ["ap-southeast-1a", "ap-southeast-1z"]
  }
  expect_failures = [data.aws_availability_zones.available]
}

run "reject_duplicate_zones" {
  command = plan
  variables {
    availability_zones = ["ap-southeast-1a", "ap-southeast-1a"]
  }
  expect_failures = [var.availability_zones]
}

run "security_group_boundaries" {
  command = apply

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.api_vpn) == 0 &&
      aws_vpc_security_group_ingress_rule.alb_to_ingress.security_group_id == output.node_security_group_ids.worker &&
      aws_vpc_security_group_ingress_rule.alb_to_ingress.referenced_security_group_id == aws_security_group.alb.id &&
      aws_vpc_security_group_ingress_rule.alb_to_ingress.from_port == 30080 &&
      aws_vpc_security_group_ingress_rule.alb_to_ingress.to_port == 30080 &&
      aws_vpc_security_group_egress_rule.alb_to_ingress.referenced_security_group_id == aws_security_group.worker.id
    )
    error_message = "Keep API CIDRs closed by default and NodePort restricted to ALB with matching egress."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.etcd.security_group_id == aws_security_group.control_plane.id &&
      aws_vpc_security_group_ingress_rule.etcd.referenced_security_group_id == aws_security_group.control_plane.id &&
      aws_vpc_security_group_ingress_rule.etcd.from_port == 2379 &&
      aws_vpc_security_group_ingress_rule.etcd.to_port == 2380 &&
      aws_vpc_security_group_ingress_rule.nlb_to_api.referenced_security_group_id == aws_security_group.api_nlb.id &&
      aws_vpc_security_group_egress_rule.nlb_to_api.from_port == 6443 &&
      aws_vpc_security_group_egress_rule.nlb_to_api.to_port == 6443
    )
    error_message = "Limit etcd to control plane and permit the NLB target/health-check path on 6443."
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.vxlan) == 4 &&
      length(aws_vpc_security_group_egress_rule.vxlan) == 4 &&
      alltrue([for rule in aws_vpc_security_group_ingress_rule.vxlan :
        rule.ip_protocol == "udp" && rule.from_port == 4789 && rule.to_port == 4789
      ]) &&
      aws_vpc_security_group_ingress_rule.kubelet["worker_to_control_plane"].security_group_id == aws_security_group.control_plane.id &&
      aws_vpc_security_group_ingress_rule.kubelet["worker_to_control_plane"].referenced_security_group_id == aws_security_group.worker.id
    )
    error_message = "Allow bidirectional VXLAN between node roles and metrics-server access to control plane kubelet."
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.mysql) == 2 &&
      alltrue([for rule in aws_vpc_security_group_ingress_rule.mysql :
        rule.security_group_id == aws_security_group.rds.id &&
        rule.from_port == 3306 && rule.to_port == 3306 &&
        contains([aws_security_group.worker.id, aws_security_group.automation.id], rule.referenced_security_group_id)
      ]) &&
      length(aws_vpc_security_group_ingress_rule.endpoint_https) == 3 &&
      alltrue([for rule in aws_vpc_security_group_egress_rule.bootstrap_https :
        rule.ip_protocol == "tcp" && rule.from_port == 443 && rule.to_port == 443
      ])
    )
    error_message = "Restrict database clients and bootstrap internet egress to the intended sources and HTTPS."
  }
}

run "approved_vpn" {
  command = plan
  variables {
    api_allowed_ipv4_cidrs = ["192.0.2.10/32"]
  }
  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.api_vpn["192.0.2.10/32"].from_port == 6443 &&
      aws_vpc_security_group_ingress_rule.api_vpn["192.0.2.10/32"].to_port == 6443
    )
    error_message = "An approved VPN CIDR may access only the API listener."
  }
}

run "reject_public_api" {
  command = plan
  variables {
    api_allowed_ipv4_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.api_allowed_ipv4_cidrs]
}

run "reject_malformed_api_cidr" {
  command = plan
  variables {
    api_allowed_ipv4_cidrs = ["not-a-cidr"]
  }
  expect_failures = [var.api_allowed_ipv4_cidrs]
}

run "reject_ipv6_api_cidr" {
  command = plan
  variables {
    api_allowed_ipv4_cidrs = ["2001:db8::/64"]
  }
  expect_failures = [var.api_allowed_ipv4_cidrs]
}
