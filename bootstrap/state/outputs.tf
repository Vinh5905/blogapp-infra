output "state_bucket_name" {
  value = aws_s3_bucket.state.id
}

output "kms_key_arn" {
  value = aws_kms_key.state.arn
}

output "bootstrap_backend_config" {
  description = "Dùng terraform output -raw để ghi vào bootstrap/state/backend.hcl."
  value       = <<-EOT
    bucket              = "${aws_s3_bucket.state.id}"
    key                 = "${local.backend_state_keys.bootstrap}"
    region              = "ap-southeast-1"
    allowed_account_ids = ["947856326077"]
    encrypt             = true
    kms_key_id          = "${aws_kms_key.state.arn}"
    use_lockfile        = true
  EOT
}

output "foundation_backend_config" {
  description = "Dùng terraform output -raw để ghi vào foundation/backend.hcl."
  value       = <<-EOT
    bucket              = "${aws_s3_bucket.state.id}"
    key                 = "${local.backend_state_keys.foundation}"
    region              = "ap-southeast-1"
    allowed_account_ids = ["947856326077"]
    encrypt             = true
    kms_key_id          = "${aws_kms_key.state.arn}"
    use_lockfile        = true
  EOT
}

output "cluster_backend_config" {
  description = "Dùng terraform output -raw để ghi vào cluster/backend.hcl."
  value       = <<-EOT
    bucket              = "${aws_s3_bucket.state.id}"
    key                 = "${local.backend_state_keys.cluster}"
    region              = "ap-southeast-1"
    allowed_account_ids = ["947856326077"]
    encrypt             = true
    kms_key_id          = "${aws_kms_key.state.arn}"
    use_lockfile        = true
  EOT
}

output "backend_policy_arns" {
  description = "Gắn policy tương ứng vào IAM role/user được phép vận hành từng root."
  value       = { for name, policy in aws_iam_policy.backend : name => policy.arn }
}
