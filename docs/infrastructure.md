# Hạ tầng lab

## Target envelope và evidence

Target budget do người dùng cung cấp: một VPS nhỏ, 4 vCPU, 4 GB RAM và 40 GB SSD. Linux inventory ban đầu được thu trực tiếp qua SSH ngày 2026-11-20; Docker runtime và Lab 07 được xác minh lại ngày 2026-11-23. Raw inventories, host identifiers, exact network values và current host security posture được giữ local-only, không lưu trong repository công khai.

| Hạng mục | Runtime evidence đã làm sạch | Giới hạn |
|---|---|---|
| OS/kernel | Ubuntu 24.04 LTS, x86-64, kernel dòng 6.8 | Snapshot; compatibility phải được kiểm tra lại trước khi pin runtime |
| CPU | 4 guest-visible vCPU | Không chứng minh physical-host capacity |
| RAM/swap | `MemTotal` xấp xỉ 3.8 GiB, `MemAvailable` xấp xỉ 3.3 GiB; không swap | Giá trị thay đổi theo tải; không dùng swap để thay RAM Kubernetes |
| Disk | Virtual disk theo target budget; root filesystem ext4, ROTA=0; sample I/O một giây không đủ để đo latency | Không chứng minh backing media vật lý hay sustained IOPS |
| Virtualization/cgroups | KVM, cgroup v2; CPU/memory/io/pids controllers quan sát được; transient service có quota/cap | Root cgroup không nhất thiết cung cấp limit files; inspect đúng service cgroup |
| Networking | Lab 04 route/resolver PASS; sau Docker install IPv4/IPv6 route, DNS và registry reachability PASS (HTTP 401 trên cả hai family); không có non-SSH public listener hoặc Docker-published port ở final check | Exact addresses, prefixes, routes, listeners and raw rules remain local-only; public application ingress is not enabled |
| SSH/security | Fresh key-only SSH and host-change gate PASS after a temporary connection interruption; no SSH hardening was applied | Current authentication policy and config source details remain local-only; public-exposure gate remains separate |
| Existing software | Docker Engine 29.10.0, Compose 5.8.0 and containerd 2.4.2 installed via the approved five-package set; services active at final check | Runtime state is a snapshot; no standalone containerd package or public app workload |
| Health | systemd hoạt động; snapshot không có failed units | Chỉ là snapshot thời điểm kiểm tra |

## Runtime learning results

- Phase 0 inventory và Labs 01–06 đã chạy trực tiếp bằng Windows OpenSSH helper. Kết quả và giới hạn chi tiết được ghi trong [progress](progress.md) và từng lab.
- Lab 03 chạy workload tạm qua systemd với CPU, memory, task và duration limits; unit, process, cgroup và upload directory đã được xác minh cleanup.
- Lab 04 chỉ đọc route/socket state và thực hiện một bounded NSS lookup; không thay đổi network.
- Lab 05 chỉ đọc filesystem/disk counters và chạy bounded `du`; không thay đổi disk.
- Lab 06 chỉ tạo dữ liệu tạm trong private directory và đã xóa chính xác.
- Lab 07 cài đúng năm package được duyệt; BusyBox smoke giới hạn 64 MiB/0.25 CPU/16 PIDs, health/DNS/cgroups/graceful stop/cleanup PASS; không publish port.
- Các kết quả là snapshots; public ingress, NAT egress, authoritative DNS và sustained disk performance chưa được chứng minh.

## Network và bảo mật

- Tài liệu công khai không lưu địa chỉ máy, route values, raw rule dumps, current SSH effective values hay firewall posture. Xem output live trực tiếp và không copy raw data vào Git.
- Không sửa thủ công SSH, UFW, provider firewall hoặc routing. Docker installation đã tự tạo bridge/packet-filter rules và đổi IPv4 forwarding từ 0 sang 1; IPv6 forwarding vẫn 0.
- Trước khi bật dịch vụ public, xác minh host/provider ingress, SSH recovery path, console/out-of-band recovery và resource gates. `scripts/validate.sh public-services` yêu cầu live host checks và evidence thủ công còn fresh.
- Docker bridge publishing có thể cài forwarding/NAT rules ngoài đường lọc UFW thông thường; bind lab service vào localhost và dùng SSH tunnel cho tới khi ingress được review.
- Docker tự động đặt IPv4 forwarding thành 1; không nạp kernel modules và không chỉnh network daemon thủ công. Kubernetes cần preflight riêng.
- Không mở Kubernetes API, etcd, kubelet, NodePort hoặc application ports ra Internet mặc định.

## Kết luận hiện tại

Linux Labs 01–06 và Docker Lab 07 đã chạy; Docker install, runtime verification, bounded smoke và cleanup PASS. Docker app deployment/public exposure, Labs 08–11 on-VPS and Kubernetes remain untested/deferred until their separate gates and scope are met. Do not use Swap to compensate for RAM.
