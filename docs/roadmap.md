# Roadmap học DevOps

Không chuyển phase theo lịch nếu gate hoặc evidence còn thiếu. Mỗi lab phải được chạy, xác minh, troubleshoot và dọn trước khi ghi PASS trong `docs/progress.md`.

## Phase 1 — Linux foundation

| Lab | Nội dung | Trạng thái/điều kiện |
|---|---|---|
| 01 | Linux filesystem, users, permissions, process/thread, package manager | Hoàn tất; ACL NOT TESTED vì utility chưa cài. |
| 02 | systemd, transient service, process, signals, journalctl | Đang thực hiện; dùng workload giới hạn và cleanup tự động. |
| 03 | CPU, RAM, load average, memory pressure, disk I/O, cgroups | Kế tiếp; observe-only trước, bounded user-space test nếu có lý do; không OOM/disk exhaustion. |
| 04 | IPv4/IPv6, CIDR, DNS, TCP/UDP, route, NAT, firewall | Read-only trước; không sửa SSH/firewall/network. |
| 05 | Filesystem, inode, mount, loopback storage, LVM concepts | Filesystem/inode read-only; mount/loopback chỉ khi có approval/preconditions/cleanup. LVM có thể mô phỏng bằng sơ đồ. |
| 06 | Bash, exit status, quoting, idempotency, temp files, automation | Automate diagnostics có allowlist; không lưu credentials. |

## Phase 2 — Docker

Sau Linux/network gates: compatibility và firewall review; Docker Engine/Dockerfile/Compose, image layers, volumes, networks, non-root ASP.NET Core sample. Ứng dụng bind localhost trước, truy cập qua SSH tunnel; không public port mặc định. Đánh giá firewall interaction trước package install.

## Phase 3 — containerd

Học OCI, namespaces, cgroups, containerd/CRI, `ctr`/`crictl`. Thực hiện riêng với Docker runtime lab và cleanup rõ trước khi kubeadm.

## Phase 4 — kubeadm single-node

Kubernetes là main lab: một control-plane/node duy nhất, workload rất nhẹ, API không public, không swap. Trước khi pin version phải kiểm tra OS/Kubernetes compatibility, runtime, network, cgroups, memory/disk headroom và backup/rollback. Không cài nếu VPS không còn đủ tài nguyên.

## Phase 5 — RKE2 (conditional)

Giữ trong roadmap sau kubeadm backup/cleanup và đánh giá lại requirements/compatibility tại thời điểm chạy. Không bỏ qua minimum requirements hoặc cài đồng thời kubeadm/RKE2 trên cùng host.

## Phase 6 — Rancher (deferred decision)

Chỉ sau khi xem profile/version requirements và resource budget. Nếu VPS không đủ headroom, chuyển Rancher sang máy cá nhân vào tháng sau. Không mua VPS hoặc dịch vụ trả phí; không chạy Rancher stack cùng RKE2 khi budget chưa chứng minh đủ.

## Deferred mặc định trên VPS hiện tại

Rancher management stack, Harbor, GitLab Server, Longhorn, full Prometheus/Grafana/Loki, multi-node HA, GPU, air-gap và production ingress. Các bài cần nhiều node/disk/RAM chuyển sang máy local; không dựng placeholder để đánh dấu đã hoàn thành.
