# BlogApp infrastructure

Terraform khai báo trực tiếp các resource `aws_*`. Không có module Registry, GitHub hoặc module local. AWS provider vẫn cần cài để Terraform gọi AWS API.

## Bootstrap remote state

Đọc [bài thực hành bootstrap từng bước](01a-bootstrap-remote-state-tung-buoc.md) trước khi chạy. Quy trình là:

1. Dùng session AWS cá nhân đúng account `947856326077`, region `ap-southeast-1`.
2. Init bootstrap bằng **local backend**, review plan rồi apply để tạo S3, KMS và IAM backend policies.
3. Dùng `terraform output -raw` ghi partial backend config vào từng file `backend.hcl`.
4. Copy mẫu backend S3 đè `bootstrap/state/backend.tf`, chạy `init -migrate-state`.
5. Kiểm state qua Terraform, object version/encryption trên S3 và plan sau migration.
6. Init foundation/cluster với các state key riêng.

`backend.tf` được giao ở trạng thái local cho lần dựng đầu tiên. File `backend.s3.tf.example` chỉ được kích hoạt sau khi bucket đã tồn tại. Sau migration, giữ `backend.tf` ở dạng S3 cho các lần làm việc tiếp theo; không copy lại cấu hình local.

| Root | State key sau bootstrap |
| --- | --- |
| `bootstrap/state` | `bootstrap/state.tfstate` |
| `terraform/environments/dev/foundation` | `dev/foundation.tfstate` |
| `terraform/environments/dev/cluster` | `dev/cluster.tfstate` |

Các root dùng workspace `default`. Không dùng Terraform workspace để phân tách môi trường trong cấu trúc này.

## Cấu trúc code

```text
bootstrap/state/
  backend.tf                 # Local ở lần đầu; đổi sang S3 khi migrate
  backend.s3.tf.example       # Mẫu backend cho bước migration
  versions.tf                # Terraform/provider, region và account guard
  locals.tf                  # Bucket name và ba state key
  bucket.tf                  # Bucket, public block, ownership, versioning, KMS, TLS-only
  kms.tf                     # KMS rotation, key policy, prevent_destroy
  iam.tf                     # Ba backend policies theo từng state key
  outputs.tf                 # Bucket, KMS ARN, ba cấu hình backend HCL và IAM policy ARNs
  state-backups/             # Backup local trước migration, tên có ngày giờ đến giây
  tests/                     # Mock tests, không tạo tài nguyên AWS

terraform/environments/dev/foundation/
  backend.tf                 # S3 backend
  versions.tf                # Provider và tags
  variables.tf               # Account, region, hai AZ và CIDR VPN cho API
  az-checks.tf               # Kiểm tra AZ
  locals.tf                  # CIDR, tên và tags
  vpc.tf                     # VPC
  subnets.tf                 # Sáu subnet public/private/database
  internet-gateway.tf
  nat-gateway.tf             # Một NAT dùng chung
  route-tables.tf            # Routes và associations
  database-subnet-group.tf   # Chưa tạo RDS instance
  default-security-group.tf  # Bỏ rule mặc định
  security-groups.tf         # Bảy SG theo vai trò, tạo trước compute
  security-group-rules.tf    # Rules ingress/egress độc lập
  outputs.tf
  dev.tfvars.example
  tests/

terraform/environments/dev/cluster/
  backend.tf                 # Mới chuẩn bị backend, chưa tạo cluster
```

## IAM và vòng đời backend

Bootstrap tạo policy backend riêng cho từng root, chỉ cấp đọc/ghi state key tương ứng, list prefix, get/put/delete lockfile `.tflock` và dùng KMS qua S3. Không cấp xóa state object, không tạo DynamoDB lock table. KMS key policy cho account ủy quyền qua IAM.

Policy được tạo nhưng không tự gắn vào user/role: chọn đúng danh tính vận hành và gắn policy tương ứng. Quyền backend không thay quyền triển khai VPC/cluster hoặc quản trị bootstrap. Hướng dẫn chi tiết và nguồn quyền nằm trong bài thực hành.

Bucket và KMS có `prevent_destroy = true`; bucket có `force_destroy = false`. Bootstrap nằm ngoài root cluster để teardown cluster không bao gồm bucket/KMS. Các bảo vệ Terraform không ngăn người có quyền xóa tài nguyên trực tiếp qua AWS hoặc xóa luôn resource khỏi code.

## D2 — Foundation network và security groups

Đọc [bài foundation network từng bước](01b-foundation-network-tung-buoc.md) để thực hành backend, đọc code từng file, chọn AZ, init/plan/apply và kiểm network/SG trên AWS. Code đầy đủ ở `terraform/environments/dev/foundation`, dùng resource trực tiếp.

Chỉ tiếp tục khi bootstrap đã migrate và kiểm tra thành công. Dùng cùng session AWS; cấu hình hai AZ trong file `dev.tfvars` riêng, dựa trên `dev.tfvars.example`. Giữ `api_allowed_ipv4_cidrs = []` nếu chưa có VPN; API NLB vẫn có rules nhận từ SG node/automation.

```bash
terraform -chdir=terraform/environments/dev/foundation init -backend-config=backend.hcl
terraform -chdir=terraform/environments/dev/foundation validate
terraform -chdir=terraform/environments/dev/foundation plan -var-file=dev.tfvars -out=foundation-network.tfplan
```

Đọc plan trước khi apply. Nếu root đã có state tại backend khác, xử lý migration/khôi phục trước; không dùng `-reconfigure` để thay thế việc chuyển state. Không triển khai lại bằng state rỗng khi tài nguyên tương ứng vẫn tồn tại.

Code tạo VPC `10.10.0.0/16`, hai public subnet qua IGW, hai private subnet qua một NAT, hai database subnet không có default route Internet và DB subnet group. Một NAT dùng chung là lựa chọn dev, có phụ thuộc AZ và khả năng phát sinh phí truyền giữa AZ.

Bảy SG dành cho ALB, API NLB, control plane, worker, RDS, automation và interface endpoints. Rules có ingress/egress tương ứng cho ALB → NodePort `30080`, NLB → API `6443`, etcd chỉ control plane, kubelet và Calico VXLAN giữa node, MySQL từ worker/automation. Automation không inbound SSH. Node/automation có egress HTTPS để bootstrap/SSM; chưa có CIDR VPN được mở mặc định.

Outputs hiện có VPC/subnet/AZ mapping, route/NAT và SG IDs cho cluster. Đây là phần network và SG của D2; IAM compute, EC2/ASG, ALB/NLB, interface endpoints, RDS instance và các outputs tương ứng tiếp tục ở bước sau. Các lệnh kiểm AWS và giới hạn pod CIDR/SNAT nằm trong bài thực hành.

## Kiểm tra cục bộ

Sau khi provider đã được cài trong từng root:

```bash
terraform fmt -check -recursive
terraform -chdir=bootstrap/state validate
terraform -chdir=bootstrap/state test
terraform -chdir=terraform/environments/dev/foundation validate
terraform -chdir=terraform/environments/dev/foundation test
```

Terraform tests dùng mock provider, không xác minh IAM/session/quota hay tạo bucket thật. Việc migrate lên S3 cần được kiểm tra trong session AWS sau khi review/apply bootstrap.

## File cục bộ

State, state backup, saved plan, `.terraform/`, `backend.hcl`, credentials và `*.tfvars` thật không đưa vào Git. Backup trước migration được lưu tại `bootstrap/state/state-backups/`, ví dụ `pre-migration-20261018-163045.tfstate`.

Đứng trong `bootstrap/state`, chạy:

```bash
umask 077
mkdir -p state-backups
cp -p terraform.tfstate "state-backups/pre-migration-$(date +%Y%m%d-%H%M%S).tfstate"
```

Thư mục này đã nằm trong `.gitignore`. Xem [bài thực hành](01a-bootstrap-remote-state-tung-buoc.md) để tiếp tục đổi backend và migrate. Không xóa state hiện có để bắt đầu lại.

S3, các phiên bản object, KMS và NAT/public IPv4 phát sinh phí khi triển khai. Xem [giá S3](https://aws.amazon.com/s3/pricing/), [giá KMS](https://aws.amazon.com/kms/pricing/) và [giá VPC](https://aws.amazon.com/vpc/pricing/).
