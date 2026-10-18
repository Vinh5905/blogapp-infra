terraform {
  # Lần đầu dùng local để tạo bucket/KMS trước khi có remote backend.
  # Sau apply: làm theo 01a-bootstrap-remote-state-tung-buoc.md để migrate sang S3.
  backend "s3" {}
}
