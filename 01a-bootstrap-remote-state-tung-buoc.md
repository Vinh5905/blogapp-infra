# Bootstrap remote state từng bước

## 1. Vì sao phải bắt đầu bằng local state?

State ghi resource Terraform nào đang quản lý tài nguyên AWS nào. Backend quyết định nơi Terraform đọc/ghi state. Backend được khởi tạo trước khi Terraform tạo resource, nên S3 backend không thể dùng một bucket chưa tồn tại.

Root `bootstrap/state` giải quyết vòng này theo hai giai đoạn:

```text
Lần đầu: local state → tạo S3 bucket + KMS + IAM backend policies
Sau đó:  init -migrate-state → state bootstrap nằm trên S3
```

Foundation và cluster dùng cùng bucket nhưng ba root có ba object state riêng. Terraform S3 locking dùng `.tflock`; không cần DynamoDB. Xem [S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3).

## 2. Code bootstrap tạo những gì?

Đọc các file theo thứ tự:


| File                                       | Nội dung                                                               |
| -------------------------------------------- | ------------------------------------------------------------------------- |
| [backend.tf](bootstrap/state/backend.tf)   | Local backend cho lần đầu                                            |
| [versions.tf](bootstrap/state/versions.tf) | Terraform >= 1.10, provider AWS, account/region guard                   |
| [locals.tf](bootstrap/state/locals.tf)     | Bucket name, ba state key                                               |
| [kms.tf](bootstrap/state/kms.tf)           | KMS rotation, key policy cho account ủy quyền IAM, prevent_destroy    |
| [bucket.tf](bootstrap/state/bucket.tf)     | Bucket, versioning, block public access, tắt ACL, SSE-KMS và TLS-only |
| [iam.tf](bootstrap/state/iam.tf)           | Backend policy riêng cho bootstrap/foundation/cluster                  |
| [outputs.tf](bootstrap/state/outputs.tf)   | Bucket, KMS ARN, ba cấu hình backend HCL, policy ARNs                 |

Tất cả dùng `resource` trực tiếp, không dùng module. Bucket name `blogapp-dev-tfstate-947856326077-ap-southeast-1` ghép project/environment/account/region để giảm khả năng trùng; vẫn phải duy nhất trong namespace S3 đang sử dụng. `force_destroy = false` ngăn Terraform tự vét object; `prevent_destroy = true` ngăn plan destroy/replace bucket và key khi khai báo còn trong code.

## 3. Dùng session AWS cá nhân đang có

Đứng ở thư mục gốc repo. Dùng profile cá nhân có quyền bootstrap trong đúng account, có thể là profile đăng nhập AWS Console qua `aws login`, hoặc profile SSO nếu bạn đã sử dụng IAM Identity Center. Không bắt buộc cấu hình Identity Center để dùng bài này.

```bash
export AWS_PROFILE=blogapp-dev
export AWS_REGION=ap-southeast-1
umask 077
aws sts get-caller-identity
```

Đổi tên profile nếu session của bạn dùng tên khác. Kết quả phải có `Account` là `947856326077`. Nếu session hết hạn, làm mới session theo cơ chế đăng nhập của profile trước khi tiếp tục. Không ghi access key, secret key hoặc session token vào Terraform/backend config. Xem [đăng nhập CLI](https://docs.aws.amazon.com/cli/latest/reference/login/).

Danh tính bootstrap cần quyền tạo/quản lý bucket, cấu hình S3, KMS và IAM managed policies. Các backend policy được tạo ở bước sau chỉ cấp truy cập state, không cấp quyền dựng toàn bộ hạ tầng. Không đổi sang principal chỉ có quyền backend trước khi hoàn thành bootstrap.

## 4. Init local, review plan, rồi apply

Trước lần đầu, `bootstrap/state/backend.tf` là:

```hcl
terraform {
  backend "local" {}
}
```

File `backend.s3.tf.example` chưa được Terraform đọc vì không có đuôi `.tf`. Không bật mẫu S3 trước khi tạo bucket.

```bash
terraform -chdir=bootstrap/state init
terraform -chdir=bootstrap/state validate
terraform -chdir=bootstrap/state workspace show
terraform -chdir=bootstrap/state plan -out=bootstrap.tfplan
```

Workspace phải là `default`. Plan lần dựng mới phải tạo bucket/cấu hình S3, KMS/alias và ba IAM policies, không destroy/replace tài nguyên đang dùng. Nếu state hoặc tài nguyên đã tồn tại, kiểm tra hiện trạng trước; không xóa state hay dùng lại saved plan từ cấu hình khác.

Sau khi đọc và chấp nhận plan, thực hiện:

```bash
terraform -chdir=bootstrap/state apply bootstrap.tfplan
terraform -chdir=bootstrap/state state list
terraform -chdir=bootstrap/state output
```

Apply saved plan thực hiện ngay các thay đổi đã lưu. Ở bước này state bootstrap vẫn ở local, mặc dù S3 bucket đã tồn tại.

## 5. Ghi Terraform outputs vào backend.hcl

```bash
terraform -chdir=bootstrap/state output -raw bootstrap_backend_config > bootstrap/state/backend.hcl
terraform -chdir=bootstrap/state output -raw foundation_backend_config > terraform/environments/dev/foundation/backend.hcl
terraform -chdir=bootstrap/state output -raw cluster_backend_config > terraform/environments/dev/cluster/backend.hcl
```

Bạn tự chuẩn bị các thư mục trước. Sau khi apply bootstrap thành công, các output đã chứa sẵn nội dung HCL với bucket/KMS thực tế. `-raw` lấy nguyên nội dung chuỗi; dấu `>` ghi nội dung đó vào file. `umask 077` ở bước đầu giúp các file mới có quyền `0600`. Kiểm tra lệnh output thành công và file có nội dung trước khi init:


| File                                                | Key                       |
| ----------------------------------------------------- | --------------------------- |
| `bootstrap/state/backend.hcl`                       | `bootstrap/state.tfstate` |
| `terraform/environments/dev/foundation/backend.hcl` | `dev/foundation.tfstate`  |
| `terraform/environments/dev/cluster/backend.hcl`    | `dev/cluster.tfstate`     |

Ví dụ cấu trúc file bootstrap (ARN thật được Terraform điền từ resource đã tạo):

```hcl
bucket              = "blogapp-dev-tfstate-947856326077-ap-southeast-1"
key                 = "bootstrap/state.tfstate"
region              = "ap-southeast-1"
allowed_account_ids = ["947856326077"]
encrypt             = true
kms_key_id          = "arn:aws:kms:ap-southeast-1:947856326077:key/<key-id-thuc-te>"
use_lockfile        = true
```

Backend không nhận `var.*` hoặc tham chiếu resource. Các tham chiếu trong `outputs.tf` được Terraform tính thành giá trị cụ thể sau apply, rồi mới ghi vào `backend.hcl`. Không copy nguyên ví dụ có placeholder để init. Các lệnh output chỉ đọc state và ghi file, không apply hay migrate.

## 6. Bảo vệ bản dự phòng, đổi backend và migrate

Backup được lưu trong `bootstrap/state/state-backups/`, đã có trong `.gitignore`. Từ thư mục gốc repo, chuyển vào thư mục bootstrap state:

```bash
cd bootstrap/state
```

Sau khi apply bootstrap thành công và trước khi đổi backend, chạy:

```bash
umask 077
mkdir -p state-backups
cp -p terraform.tfstate "state-backups/pre-migration-$(date +%Y%m%d-%H%M%S).tfstate"
```

Ví dụ tên file: `state-backups/pre-migration-20261018-163045.tfstate`. Timestamp có đủ năm, tháng, ngày, giờ, phút, giây theo múi giờ của máy. `cp -p` sao chép state local và giữ quyền cùng thời gian của file gốc. Chỉ tiếp tục khi lệnh copy thành công.

Sau khi có bản backup và file `backend.hcl`, đổi sang backend S3. Vẫn đứng trong `bootstrap/state`:

```bash
cp backend.s3.tf.example backend.tf
terraform init -migrate-state -backend-config=backend.hcl
```

`backend.tf` lúc này là:

```hcl
terraform {
  backend "s3" {}
}
```

Đọc câu hỏi migration của Terraform, kiểm đúng backend rồi xác nhận sao chép state hiện có sang S3. Không dùng `-reconfigure` thay cho `-migrate-state`, không chạy apply thêm để cố sửa lỗi migration. Nếu lỗi, giữ nguyên state/cache và bản dự phòng, xử lý nguyên nhân rồi chạy lại migration. Xem [terraform init](https://developer.hashicorp.com/terraform/cli/commands/init).

## 7. Kiểm kết quả migration

Sau khi migration thành công, trở về thư mục gốc repo để chạy các lệnh kiểm tra bên dưới:

```bash
cd ../..
```

Dùng danh tính bootstrap có quyền kiểm tra bucket/object versions:

```bash
terraform -chdir=bootstrap/state state list
terraform -chdir=bootstrap/state plan -detailed-exitcode

aws s3api get-bucket-versioning \
  --bucket blogapp-dev-tfstate-947856326077-ap-southeast-1

aws s3api head-object \
  --bucket blogapp-dev-tfstate-947856326077-ap-southeast-1 \
  --key bootstrap/state.tfstate \
  --query '{Encryption:ServerSideEncryption,KMS:SSEKMSKeyId,Version:VersionId}'

aws s3api list-object-versions \
  --bucket blogapp-dev-tfstate-947856326077-ap-southeast-1 \
  --prefix bootstrap/state.tfstate \
  --query 'Versions[?Key==`bootstrap/state.tfstate`].{Version:VersionId,Latest:IsLatest,Modified:LastModified}'
```

Kết quả cần thấy:

- `state list` vẫn có 11 resource: sáu S3, KMS key/alias và ba IAM policies.
- Plan không có thay đổi sau migration; exit code `0` (code `1` là lỗi, `2` là có thay đổi).
- Bucket versioning là `Enabled`.
- Object `bootstrap/state.tfstate` tồn tại, có VersionId, mã hóa `aws:kms`, đúng KMS ARN của bootstrap.
- Danh sách object versions có phiên bản hiện tại. Chỉ cần ít nhất một version sau lần ghi đầu tiên.

Lockfile tồn tại trong lúc Terraform giữ lock và thường được xóa khi kết thúc; không yêu cầu `.tflock` còn tồn tại sau plan. Lệnh kiểm versions cần quyền `s3:ListBucketVersions`; quyền này không nằm trong policy backend tối thiểu. Xem [AWS CLI list-object-versions](https://docs.aws.amazon.com/cli/latest/reference/s3api/list-object-versions.html).

Giữ `backend.tf` dạng S3 sau migration. Khi checkout trên máy khác, lấy `backend.hcl` hợp lệ từ quy trình của dự án và init S3 bình thường, không bật lại local. Giữ các bản dự phòng trong `bootstrap/state/state-backups/`; các bản cần lưu từ file tự sinh như `terraform.tfstate.backup` cũng lưu trong thư mục này với tên có timestamp. Không xóa state hoặc bản dự phòng trước khi kiểm migration xong. Thư mục đã được Git ignore nhưng vẫn cần hạn chế quyền truy cập và bảo vệ dữ liệu lưu trên máy.

## 8. Quyền backend và bảo vệ khi teardown

```bash
terraform -chdir=bootstrap/state output backend_policy_arns
```

Bootstrap tạo ba managed policies. Gắn policy tương ứng vào role/user đã được chọn để vận hành root đó. Code không tự cấp quyền cho một principal chưa được chỉ định. Dùng role/session ngắn hạn; với SSO, quản trị quyền qua permission set phù hợp.

Mỗi policy cho phép:

- `s3:ListBucket` cho state/lock prefix và prefix `env:/` mà Terraform dùng để kiểm workspace; không cấp object access cho workspace khác.
- `s3:GetObject`, `s3:PutObject` trên đúng một state key.
- `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` trên đúng lockfile của key đó; không cấp xóa state object.
- `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey` trên đúng KMS key, qua S3 trong đúng region/account và encryption context của bucket/object tương ứng.

KMS key policy cho account dùng IAM để ủy quyền. Bucket Key dùng bucket ARN làm encryption context, nên quyền S3 theo từng object vẫn là phần phân tách các root. Backend policy không cấp quyền thay key policy hay xóa key. Xem [KMS key policy](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html) và [SSE-KMS encryption context](https://docs.aws.amazon.com/AmazonS3/latest/userguide/specifying-kms-encryption.html).

Bootstrap nằm ở root riêng; teardown cluster chỉ thao tác root cluster. Bucket/KMS có `prevent_destroy`, bucket không force-delete object. Không đưa bucket/KMS vào root cluster và không gỡ bảo vệ để teardown workload.

Để vận hành lâu dài, nên bổ sung access logging vào bucket log riêng, CloudTrail S3 data events và CloudWatch metrics theo nhu cầu giám sát; các hạng mục này có chi phí và không được tạo trong bootstrap tối thiểu này. S3 lưu cả các version cũ, KMS tính phí key/request; xem [giá S3](https://aws.amazon.com/s3/pricing/), [giá KMS](https://aws.amazon.com/kms/pricing/) và [giám sát S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/monitoring-overview.html).

## 9. Init các root sử dụng bucket

Sau khi hoàn thành các kiểm tra trên:

```bash
terraform -chdir=terraform/environments/dev/foundation init -backend-config=backend.hcl
terraform -chdir=terraform/environments/dev/cluster init -backend-config=backend.hcl
```

Đây là init backend cho từng root, không sao chép state bootstrap sang foundation/cluster. Nếu một root đã có state cần chuyển từ backend khác, phải dùng quy trình migration cho chính root đó. Không ghi đè state hoặc dùng root rỗng để dựng lại tài nguyên đang tồn tại.
