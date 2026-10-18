output "vpc_id" {
  value = aws_vpc.blogapp.id
}

output "vpc_cidr_block" {
  value = aws_vpc.blogapp.cidr_block
}

output "availability_zones" {
  value = var.availability_zones
}

output "public_subnet_ids" {
  value = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "database_subnet_ids" {
  value = [aws_subnet.database_a.id, aws_subnet.database_b.id]
}

output "database_subnet_group_name" {
  value = aws_db_subnet_group.database.name
}

output "subnets_by_az" {
  value = {
    for index, az in var.availability_zones : az => {
      public_subnet_id   = [aws_subnet.public_a.id, aws_subnet.public_b.id][index]
      private_subnet_id  = [aws_subnet.private_a.id, aws_subnet.private_b.id][index]
      database_subnet_id = [aws_subnet.database_a.id, aws_subnet.database_b.id][index]
    }
  }
}

output "internet_gateway_id" {
  value = aws_internet_gateway.internet.id
}

output "nat_gateway_ids" {
  value = [aws_nat_gateway.outbound.id]
}

output "nat_public_ips" {
  value = [aws_eip.nat.public_ip]
}

output "route_table_ids" {
  value = {
    public   = [aws_route_table.public.id]
    private  = [aws_route_table.private.id]
    database = [aws_route_table.database.id]
  }
}

output "default_security_group_id" {
  value = aws_default_security_group.closed.id
}

output "security_group_ids" {
  description = "Security groups for foundation services and cluster nodes."
  value = {
    alb           = aws_security_group.alb.id
    api_nlb       = aws_security_group.api_nlb.id
    control_plane = aws_security_group.control_plane.id
    worker        = aws_security_group.worker.id
    rds           = aws_security_group.rds.id
    automation    = aws_security_group.automation.id
    endpoints     = aws_security_group.endpoints.id
  }
}

output "node_security_group_ids" {
  description = "Attach the matching SG to each node role in the cluster root."
  value       = local.node_security_groups
}
