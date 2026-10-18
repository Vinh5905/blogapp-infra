# Danh sách subnet cho RDS ở bài sau; chưa tạo DB instance.
resource "aws_db_subnet_group" "database" {
  name        = local.name
  description = "Database subnet group for ${local.name}"
  subnet_ids  = [aws_subnet.database_a.id, aws_subnet.database_b.id]
  tags        = merge(local.cluster_tags, { Name = local.name })
}
