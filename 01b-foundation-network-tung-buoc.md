# D2 — Foundation network từng bước bằng resource trực tiếp

Bài này triển khai phần network và security groups của D2 trong `terraform/environments/dev/foundation`. Code đầy đủ nằm ngay trong root đó, không dùng module và không cần chép thêm một bộ code mẫu. IAM compute, ALB/NLB, interface endpoints và RDS instance sẽ được bổ sung vào cùng root ở các bước sau; hoàn thành bài này chưa phải hoàn thành toàn bộ D2.

## 1. Điều kiện bắt đầu và backend foundation

Hoàn thành [bootstrap remote state](01a-bootstrap-remote-state-tung-buoc.md): bucket/KMS đã được tạo, state bootstrap đã migrate và kiểm tra thành công. Foundation dùng S3 ngay từ lần init đầu, với key riêng `dev/foundation.tfstate`; không migrate state bootstrap vào key này.

Tất cả lệnh trong bài chạy từ **thư mục gốc repo**. Dùng session cá nhân có quyền backend foundation và quyền triển khai network/RDS subnet group:

```bash
export AWS_PROFILE=blogapp-dev
export AWS_REGION=ap-southeast-1
umask 077
aws sts get-caller-identity
```

Account phải là `947856326077`. Đổi tên profile theo session đang dùng. Backend policy do bootstrap tạo chỉ cấp quyền state, không cấp quyền tạo VPC/SG/NAT. Không lưu credentials vào code hoặc backend config.

Nếu chưa ghi file backend foundation, lấy nội dung đã được bootstrap output sẵn:

```bash
terraform -chdir=bootstrap/state output -raw foundation_backend_config > terraform/environments/dev/foundation/backend.hcl
```

Kiểm lệnh thành công và file có đúng bucket, key `dev/foundation.tfstate`, region, KMS ARN, `encrypt = true`, `use_lockfile = true`. File này được Git ignore. Không dùng output bootstrap backend cho foundation vì hai root phải có state key khác nhau.

## 2. Thiết kế mạng được tạo

VPC `10.10.0.0/16` bật DNS support và DNS hostnames. Chọn đúng hai AZ standard đang available trong account. Hậu tố `a`/`b` của resource là vị trí trong danh sách AZ, không buộc AZ thứ nhất phải có tên kết thúc bằng `a`.


| Nhóm    | Subnet thứ nhất | Subnet thứ hai | Route ngoài VPC        | Dùng cho bước sau                                |
| ---------- | ------------------- | ----------------- | ------------------------- | ----------------------------------------------------- |
| Public   | `10.10.0.0/24`    | `10.10.1.0/24`  | `0.0.0.0/0` → IGW      | Public ALB, NAT                                     |
| Private  | `10.10.10.0/24`   | `10.10.11.0/24` | `0.0.0.0/0` → một NAT | Control plane, worker, automation; internal API NLB |
| Database | `10.10.20.0/24`   | `10.10.21.0/24` | Chỉ route local        | RDS                                                 |

Cả ba nhóm dùng cùng thứ tự AZ. Mỗi nhóm có một route table dùng chung cho hai subnet và association riêng cho từng subnet. Database không có default route ra IGW/NAT. DB subnet group chứa hai database subnet, chưa tạo database instance.

Một public NAT nằm trong public subnet thứ nhất, dùng một Elastic IP. Private subnet thứ hai đi qua NAT khác AZ: có thể phát sinh phí truyền dữ liệu giữa AZ, và khi AZ chứa NAT lỗi thì cả hai private subnet mất đường ra Internet qua NAT này. Đây là lựa chọn chi phí cho dev; staging/prod cần thiết kế NAT/HA riêng đã review. Xem [mô hình subnet private và NAT của AWS](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-example-private-subnets-nat.html).

Mọi subnet đều tắt tự cấp public IPv4 cho EC2. Public subnet được xác định bởi route tới IGW; khi tạo public ALB ở bước sau, ALB tự quản lý network interfaces/IP của nó. NAT dùng Elastic IP khai báo riêng.

Tag `kubernetes.io/cluster/blogapp-dev = owned` có trong resource network. Không thêm tag discovery public LB khi chưa dùng controller tạo LB. Khi tạo node/ASG, phải gắn tag theo yêu cầu CCM/ASG tại bước đó; tag VPC/subnet không tự truyền sang EC2.

## 3. Đọc code theo từng file


| File trong `terraform/environments/dev/foundation`                                           | Vai trò                                                      |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| [backend.tf](terraform/environments/dev/foundation/backend.tf)                               | S3 backend, nhận partial config từ `backend.hcl`            |
| [versions.tf](terraform/environments/dev/foundation/versions.tf)                             | Terraform/provider, region, allowed account và tags          |
| [variables.tf](terraform/environments/dev/foundation/variables.tf)                           | Account, region, hai AZ và CIDR VPN tùy chọn               |
| [az-checks.tf](terraform/environments/dev/foundation/az-checks.tf)                           | Kiểm hai AZ có sẵn trong account/region, loại Local Zones |
| [locals.tf](terraform/environments/dev/foundation/locals.tf)                                 | Tên, VPC CIDR, cluster tag                                   |
| [vpc.tf](terraform/environments/dev/foundation/vpc.tf)                                       | VPC, DNS, IPv4                                                |
| [subnets.tf](terraform/environments/dev/foundation/subnets.tf)                               | Sáu subnet với CIDR và thứ tự AZ cố định              |
| [internet-gateway.tf](terraform/environments/dev/foundation/internet-gateway.tf)             | Internet Gateway                                              |
| [nat-gateway.tf](terraform/environments/dev/foundation/nat-gateway.tf)                       | Elastic IP và một public NAT                                |
| [route-tables.tf](terraform/environments/dev/foundation/route-tables.tf)                     | Ba route tables, hai default routes và sáu associations     |
| [database-subnet-group.tf](terraform/environments/dev/foundation/database-subnet-group.tf)   | Nhóm hai subnet để RDS sử dụng sau                       |
| [default-security-group.tf](terraform/environments/dev/foundation/default-security-group.tf) | Xóa rules của default SG                                    |
| [security-groups.tf](terraform/environments/dev/foundation/security-groups.tf)               | Bảy SG theo vai trò                                         |
| [security-group-rules.tf](terraform/environments/dev/foundation/security-group-rules.tf)     | Ingress/egress bằng standalone rule resources                |
| [outputs.tf](terraform/environments/dev/foundation/outputs.tf)                               | IDs và mapping cho root cluster                              |

Terraform đọc tất cả `.tf` trong root, không chạy lần lượt theo tên file. Tham chiếu ID tạo dependency giữa VPC, subnet, NAT, route và SG. `for_each` trong file rules chỉ lặp các resource AWS trực tiếp, không gọi module.

## 4. Security groups trước compute


| SG                  | Inbound được khai báo                                                                                      | Egress được khai báo                                                     |
| --------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| ALB                 | TCP `80`, `443` từ IPv4 Internet                                                                              | TCP `30080` tới worker SG                                                   |
| API NLB             | TCP `6443` từ control plane/worker/automation SG và CIDR VPN đã chọn                                      | TCP `6443` tới control plane SG                                             |
| Control plane       | TCP `6443` từ NLB và node SGs; TCP `2379–2380` chỉ từ control plane; TCP `10250`, UDP `4789` từ node SGs | API qua NLB/direct, etcd giữa control plane, kubelet/VXLAN tới node, HTTPS |
| Worker              | TCP `30080` từ ALB SG; TCP `10250`, UDP `4789` từ node SGs                                                   | API qua NLB/direct, kubelet/VXLAN tới node, MySQL tới RDS, HTTPS           |
| RDS                 | TCP `3306` từ worker và automation SG                                                                        | Không mở kết nối mới                                                    |
| Automation          | Không có inbound                                                                                             | API qua NLB, MySQL tới RDS, HTTPS                                           |
| Interface endpoints | TCP `443` từ control plane/worker/automation SG                                                               | Không mở kết nối mới                                                    |

SG có tính stateful nên traffic trả về của kết nối được phép không cần mở thêm chiều ngược. Kết nối mới vẫn cần egress ở nguồn và ingress ở đích; code khai báo cả hai cho các luồng SG-to-SG. `security_group_id` là SG nhận ingress, còn `referenced_security_group_id` là SG nguồn. Không trộn inline rules với standalone rules trên cùng SG workload. Xem [quy tắc SG và SG reference](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html).

Baseline node dùng **Calico VXLAN**, stacked etcd trên control plane và metrics-server chạy trên node. UDP `4789` mở giữa cả hai nhóm node; TCP `10250` cũng mở giữa hai nhóm để API server/metrics-server gọi kubelet. Quyền worker → kubelet rộng theo SG worker: khi triển khai phải kết hợp kubelet authentication/authorization và NetworkPolicy phù hợp. Không mở cả dải NodePort, BGP, IPIP hoặc Typha khi chưa dùng. Tham khảo [ports Kubernetes](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) và [yêu cầu mạng Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements).

Rule direct `6443` từ node tới control plane phục vụ node và traffic tới API qua Service `kubernetes.default` khi nguồn đã SNAT thành node IP. Với pod CIDR ngoài VPC, cần kiểm SNAT, VXLAN, MTU và đường đi thực tế khi dựng cluster; SG reference không tự cho phép mọi pod IP. Các đường API server → pod webhook/metrics-server cũng phải kiểm theo deployment cụ thể. Các rules hiện tại chuẩn bị network, chưa chứng minh cluster hoạt động.

Node/automation có egress TCP `443` tới `0.0.0.0/0` để tải image/package qua HTTPS, gọi AWS API/SSM qua NAT hoặc interface endpoints sau này. Đây là quyền HTTPS rộng theo đích, không lọc domain; không mở HTTP `80` cho package repositories. DNS đang dựa vào AmazonProvidedDNS của VPC; SG không lọc traffic tới Route 53 Resolver. Nếu dùng custom DNS/NTP hoặc repository qua cổng khác, bổ sung đúng đích/cổng sau khi review nhu cầu.

SG ALB mở `80` mới chỉ cho phép traffic. Ở bước LB phải tạo listener `80` redirect sang `443`, listener TLS/certificate và target/health check port `30080`. API NLB dự kiến internal, phải gắn SG ngay khi tạo, dùng target và TCP health check `6443`; AWS cho phép target reference SG của NLB cả khi bật client-IP preservation. Nếu đổi health-check port phải thêm cả ingress target lẫn egress NLB tương ứng. Xem [SG của NLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-security-groups.html).

## 5. Chọn AZ và biến dev

```bash
aws ec2 describe-availability-zones \
  --region ap-southeast-1 \
  --filters Name=state,Values=available Name=zone-type,Values=availability-zone \
  --query 'AvailabilityZones[].{Name:ZoneName,ID:ZoneId,State:State}' \
  --output table
```

Nếu chưa có `dev.tfvars`, sao chép file mẫu rồi sửa bằng editor:

```bash
cp terraform/environments/dev/foundation/dev.tfvars.example terraform/environments/dev/foundation/dev.tfvars
```

Nếu đã có file thật thì chỉnh file hiện có. Ví dụ sau chỉ dùng khi account của bạn có đúng hai AZ này:

```hcl
availability_zones    = ["ap-southeast-1a", "ap-southeast-1b"]
api_allowed_ipv4_cidrs = []
```

Giữ ổn định thứ tự AZ sau khi apply: đổi thứ tự có thể làm Terraform thay subnet và tài nguyên phụ thuộc. Provider kiểm account; AZ data source kiểm cả hai AZ thuộc region/account đang chọn.

`api_allowed_ipv4_cidrs = []` nghĩa là không thêm CIDR vào API NLB. Nếu dùng VPN, điền đúng CIDR nguồn mà NLB nhìn thấy; validation từ chối CIDR lỗi, IPv6 và `0.0.0.0/0`. SG rule không tạo VPN hoặc route: client vẫn cần đường mạng tới internal NLB. Máy automation phải gắn automation SG; danh tính cá nhân đang chạy Terraform không tự trở thành nguồn traffic trong SG này.

## 6. Init, kiểm tra, review plan rồi apply

```bash
terraform -chdir=terraform/environments/dev/foundation init -backend-config=backend.hcl
terraform -chdir=terraform/environments/dev/foundation validate
terraform -chdir=terraform/environments/dev/foundation workspace show
terraform -chdir=terraform/environments/dev/foundation test
terraform -chdir=terraform/environments/dev/foundation plan -var-file=dev.tfvars -out=foundation-network.tfplan
terraform -chdir=terraform/environments/dev/foundation show foundation-network.tfplan
```

Workspace phải là `default`. Mock tests không tạo tài nguyên AWS; plan thật cần session/quyền/quota. Kiểm VPC CIDR, sáu subnet và AZ, một NAT/EIP, các route và SG như bảng trên. Default SG được Terraform nhận quản lý để xóa ingress/egress mặc định. Không được có module, EC2, ASG, load balancer hoặc RDS instance trong plan của phần này.

Nếu backend đã có tài nguyên thì plan phải phù hợp hiện trạng, không mặc định tất cả là tạo mới. Không xóa state hoặc đổi state key để dựng lại. Nếu cần chuyển backend hiện hữu, xử lý migration riêng trước khi apply.

Sau khi review và chấp nhận saved plan:

```bash
terraform -chdir=terraform/environments/dev/foundation apply foundation-network.tfplan
terraform -chdir=terraform/environments/dev/foundation state list
terraform -chdir=terraform/environments/dev/foundation output
terraform -chdir=terraform/environments/dev/foundation plan -var-file=dev.tfvars -detailed-exitcode
```

Apply saved plan thực hiện các thay đổi đã lưu. Plan cuối nên trả exit code `0`: không còn thay đổi; `1` là lỗi, `2` là có thay đổi cần xem. State foundation được ghi lên key riêng trên S3, không có bước local → S3 cho root mới này.

## 7. Kiểm tài nguyên thực tế trên AWS

Lấy VPC ID từ Terraform output rồi dùng nó để lọc tài nguyên:

```bash
VPC_ID=$(terraform -chdir=terraform/environments/dev/foundation output -raw vpc_id)

aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
  --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,State:State}'

aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsSupport
aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames

aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,AutoPublicIP:MapPublicIpOnLaunch}' \
  --output table

aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[].{ID:RouteTableId,Subnets:Associations[].SubnetId,Routes:Routes}'

aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" Name=state,Values=available \
  --query 'NatGateways[].{ID:NatGatewayId,Subnet:SubnetId,State:State,Addresses:NatGatewayAddresses}'

aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[].{Name:GroupName,ID:GroupId,Ingress:IpPermissions,Egress:IpPermissionsEgress}'

aws rds describe-db-subnet-groups --db-subnet-group-name blogapp-dev \
  --query 'DBSubnetGroups[].{Name:DBSubnetGroupName,VPC:VpcId,Status:SubnetGroupStatus,Subnets:Subnets[].SubnetIdentifier}'
```

Chỉ tiếp tục khi lệnh lấy VPC ID thành công. Kết quả phải có sáu subnet đúng CIDR/AZ, DNS bật, NAT `available` trong public subnet thứ nhất, public default route tới IGW và private default route tới NAT. Database route table chỉ có local; kiểm subnet associations để tránh đọc nhầm route table. AWS còn tạo main route table mặc định của VPC, nên đừng kỳ vọng tổng số route table chỉ là ba.

Kiểm default SG không có rule; bảy SG riêng đúng nguồn/đích/cổng ở mục 4, automation không inbound SSH, RDS không public `3306`. Hiện chưa có targets hoặc EC2 để test packet flow. Khi thêm compute/LB phải kiểm target health, API qua NLB, ALB → NodePort, pod → RDS và traffic giữa AZ trước khi coi đường mạng đã được xác minh. Dùng VPC Flow Logs khi điều tra traffic bị chặn.

## 8. Outputs cho cluster và các bước D2 còn lại

Root hiện công bố VPC ID/CIDR, AZs, subnet IDs và `subnets_by_az`, route table IDs, IGW/NAT IDs, NAT public IP, DB subnet group, `security_group_ids` và `node_security_group_ids`. Hai map SG giúp root cluster gắn đúng SG control plane/worker; gắn nhiều SG sẽ cộng quyền của chúng, nên không tùy tiện gắn tất cả SG lên node.

Các output NLB endpoint/TG ARN, ALB TG ARN, instance profile, SSM transfer bucket, RDS address và secret ARN sẽ được thêm khi các tài nguyên tương ứng được triển khai trong foundation. Không tạo output rỗng hoặc placeholder để giả rằng các phần đó đã có. Không công bố secret value; `sensitive` chỉ che hiển thị, không loại giá trị khỏi state.

Khi root cluster bắt đầu có code, có thể dùng `terraform_remote_state` để đọc output foundation từ key `dev/foundation.tfstate`. Người đọc cần quyền đọc state foundation và giải mã KMS; backend policy riêng của cluster không tự cấp quyền này. Chỉ cấp cho trusted infra workflow vì người đọc backend có thể tiếp cận toàn bộ snapshot state, dù data source chỉ trả outputs. Không cấp source CI quyền đọc state. Về sau có thể xuất contract cần thiết qua Parameter Store để chia sẻ hẹp hơn. Xem [lưu ý bảo mật remote state của HashiCorp](https://developer.hashicorp.com/terraform/language/state/remote-state-data).

Phần IAM/LB/RDS tiếp tục trong cùng root foundation; root cluster quản compute/cluster. Teardown cluster không bao gồm network foundation hay bootstrap S3/KMS. Muốn tháo foundation thì phải xử lý mọi tài nguyên đang dùng subnet/SG và dữ liệu DB trước khi review destroy plan của chính root này. NAT và public IPv4 có phí khi tồn tại; xem [giá VPC](https://aws.amazon.com/vpc/pricing/).
