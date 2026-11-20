# Hạ tầng lab

## Target envelope và evidence

Target budget do người dùng cung cấp: một VPS nhỏ, 4 vCPU, 4 GB RAM và 40 GB SSD. Các runtime measurements bên dưới được thu trực tiếp qua SSH vào ngày 2026-11-20; raw inventories, host identifiers, exact network values và current host security posture được giữ local-only, không lưu trong repository công khai.

| Hạng mục | Runtime evidence đã làm sạch | Giới hạn |
|---|---|---|
| OS/kernel | Ubuntu 24.04 LTS, x86-64, kernel dòng 6.8 | Snapshot; compatibility phải được kiểm tra lại trước khi pin runtime |
| CPU | 4 guest-visible vCPU | Không chứng minh physical-host capacity |
| RAM/swap | `MemTotal` xấp xỉ 3.8 GiB, `MemAvailable` xấp xỉ 3.3 GiB; không swap | Giá trị thay đổi theo tải; không dùng swap để thay RAM Kubernetes |
| Disk | Virtual disk theo target budget; root filesystem ext4, ROTA=0; sample I/O một giây không đủ để đo latency | Không chứng minh backing media vật lý hay sustained IOPS |
| Virtualization/cgroups | KVM, cgroup v2; CPU/memory/io/pids controllers quan sát được; transient service có quota/cap | Root cgroup không nhất thiết cung cấp limit files; inspect đúng service cgroup |
| Networking | Lab 04 xác nhận route lookup và resolver hoạt động tại thời điểm chạy | Exact addresses, prefixes, routes, listener details và firewall policy không được lưu công khai; inbound reachability chưa thử |
| SSH/security | SSH key-only client check thành công; live effective configuration được thu bằng đúng connection context | Current authentication policy và config source details chỉ lưu local; chưa áp dụng hardening |
| Existing software | Docker, Compose, containerd, `ctr` và `crictl` chưa được phát hiện trong inventory | Recheck ngay trước khi cài runtime |
| Health | systemd hoạt động; snapshot không có failed units | Chỉ là snapshot thời điểm kiểm tra |

## Runtime learning results

- Phase 0 inventory và Labs 01–06 đã chạy trực tiếp bằng Windows OpenSSH helper. Kết quả và giới hạn chi tiết được ghi trong [progress](progress.md) và từng lab.
- Lab 03 chạy workload tạm qua systemd với CPU, memory, task và duration limits; unit, process, cgroup và upload directory đã được xác minh cleanup.
- Lab 04 chỉ đọc route/socket state và thực hiện một bounded NSS lookup; không thay đổi network.
- Lab 05 chỉ đọc filesystem/disk counters và chạy bounded `du`; không thay đổi disk.
- Lab 06 chỉ tạo dữ liệu tạm trong private directory và đã xóa chính xác.
- Các kết quả là snapshots; public ingress, NAT egress, authoritative DNS và sustained disk performance chưa được chứng minh.

## Network và bảo mật

- Tài liệu công khai không lưu địa chỉ máy, route values, raw rule dumps, current SSH effective values hay firewall posture. Xem output live trực tiếp và không copy raw data vào Git.
- Chưa thực hiện thay đổi SSH, firewall, network, package, partition, mount hoặc cluster state trong các lab read-only.
- Trước khi bật dịch vụ public, xác minh host/provider ingress, SSH recovery path, console/out-of-band recovery và resource gates. `scripts/validate.sh public-services` yêu cầu live host checks và evidence thủ công còn fresh.
- Docker bridge publishing có thể cài forwarding/NAT rules ngoài đường lọc UFW thông thường; bind lab service vào localhost và dùng SSH tunnel cho tới khi ingress được review.
- Chưa thay đổi IPv4 forwarding hoặc nạp kernel modules. Kiểm tra nhu cầu riêng trước Docker/Kubernetes.
- Không mở Kubernetes API, etcd, kubelet, NodePort hoặc application ports ra Internet mặc định.

## Kết luận hiện tại

Có thể tiếp tục Linux, networking, storage và Bash labs chỉ đọc hoặc giới hạn tài nguyên. Docker/containerd và Kubernetes vẫn deferred cho tới khi security, runtime compatibility và resource gates phù hợp được xác minh lại trên host. Không dùng Swap để bù RAM.
