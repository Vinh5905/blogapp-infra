# Tạo policy để gắn vào danh tính vận hành tương ứng; không tự chọn user/role.
# Đây chỉ là quyền backend, không phải quyền tạo VPC/EKS hay quản trị bootstrap.
resource "aws_iam_policy" "backend" {
  for_each = local.backend_state_keys

  name        = "blogapp-dev-tfstate-${each.key}"
  description = "Terraform backend access for BlogApp dev ${each.key}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStatePrefix"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.state.arn
        Condition = {
          StringEquals = {
            # Terraform kiểm tra danh sách workspace ở env:/ cả khi dùng default.
            # Không cấp quyền đọc/ghi state của workspace khác.
            "s3:prefix" = [each.value, "${each.value}.tflock", "env:/"]
          }
        }
      },
      {
        Sid      = "ReadWriteState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.state.arn}/${each.value}"
      },
      {
        Sid      = "ManageStateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/${each.value}.tflock"
      },
      {
        Sid      = "UseStateEncryptionKey"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.state.arn
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = "947856326077"
            "kms:ViaService"    = "s3.ap-southeast-1.amazonaws.com"
          }
          # S3 Bucket Key dùng bucket ARN; object ARN hỗ trợ object không dùng Bucket Key.
          StringLike = {
            "kms:EncryptionContext:aws:s3:arn" = [
              aws_s3_bucket.state.arn,
              "${aws_s3_bucket.state.arn}/${each.value}",
              "${aws_s3_bucket.state.arn}/${each.value}.tflock",
            ]
          }
        }
      },
    ]
  })
}
