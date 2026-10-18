# Tên bucket phải duy nhất trên S3. Không đặt credential trong file Terraform.
locals {
  state_bucket_name = "blogapp-dev-tfstate-947856326077-ap-southeast-1"

  # Mỗi root có một key và một IAM policy riêng; dùng workspace default.
  backend_state_keys = {
    bootstrap  = "bootstrap/state.tfstate"
    foundation = "dev/foundation.tfstate"
    cluster    = "dev/cluster.tfstate"
  }
}
