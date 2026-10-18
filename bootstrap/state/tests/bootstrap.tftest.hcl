# Mock provider: các test này không tạo bucket/KMS trên AWS.
mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::blogapp-dev-tfstate-947856326077-ap-southeast-1"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:ap-southeast-1:947856326077:key/00000000-0000-4000-8000-000000000000"
    }
  }
}

run "backend_permission_boundaries" {
  command = apply

  assert {
    condition = alltrue([
      for name, resource in aws_iam_policy.backend : alltrue([
        for statement in jsondecode(resource.policy).Statement :
        !contains(statement.Action, "s3:*") &&
        (!contains(statement.Action, "s3:DeleteObject") ||
        statement.Resource == "${aws_s3_bucket.state.arn}/${local.backend_state_keys[name]}.tflock")
      ])
    ])
    error_message = "Backend policies may delete only their own lockfile, never a state object."
  }

  assert {
    condition = alltrue([
      for name, resource in aws_iam_policy.backend :
      jsondecode(resource.policy).Statement[1].Resource == "${aws_s3_bucket.state.arn}/${local.backend_state_keys[name]}"
    ])
    error_message = "Each backend policy must access only its own state key."
  }

  assert {
    condition = alltrue([
      for resource in values(aws_iam_policy.backend) : alltrue([
        for statement in jsondecode(resource.policy).Statement :
        statement.Resource == aws_kms_key.state.arn &&
        statement.Condition.StringEquals["kms:ViaService"] == "s3.ap-southeast-1.amazonaws.com"
        if contains(statement.Action, "kms:Decrypt")
      ])
    ])
    error_message = "Backend encryption access must use the bootstrap key through regional S3."
  }

  assert {
    condition = (
      length(aws_iam_policy.backend) == 3 &&
      length(distinct(values(local.backend_state_keys))) == 3 &&
      local.backend_state_keys.bootstrap == "bootstrap/state.tfstate"
    )
    error_message = "Bootstrap, foundation and cluster must have separate state keys and policies."
  }

  assert {
    condition = (
      jsondecode(aws_kms_key.state.policy).Statement[0].Principal.AWS == "arn:aws:iam::947856326077:root"
    )
    error_message = "The key policy must retain account IAM delegation for backend identities."
  }
}

run "state_storage_protection" {
  command = apply

  assert {
    condition = (
      aws_s3_bucket_public_access_block.state.block_public_acls &&
      aws_s3_bucket_public_access_block.state.block_public_policy &&
      aws_s3_bucket_public_access_block.state.ignore_public_acls &&
      aws_s3_bucket_public_access_block.state.restrict_public_buckets
    )
    error_message = "State storage must block public access."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.state.versioning_configuration).status == "Enabled"
    error_message = "State storage must retain object versions."
  }

  assert {
    condition = (
      one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms" &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).kms_master_key_id == aws_kms_key.state.arn
    )
    error_message = "State objects must use the bootstrap KMS key."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "The bucket policy must deny insecure transport."
  }

  assert {
    condition     = !aws_s3_bucket.state.force_destroy && aws_kms_key.state.enable_key_rotation
    error_message = "Do not force-delete state objects; enable key rotation."
  }
}
