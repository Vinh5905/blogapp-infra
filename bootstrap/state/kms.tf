# Khóa mã hóa state, không phải access key để đăng nhập AWS.
resource "aws_kms_key" "state" {
  description             = "Encrypt BlogApp dev Terraform state"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  # Cho account quản trị key và ủy quyền sử dụng qua IAM policy.
  # Backend policy trong iam.tf giới hạn quyền dùng key qua S3.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableAccountIAMPermissions"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::947856326077:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/blogapp-dev-tfstate"
  target_key_id = aws_kms_key.state.key_id
}
