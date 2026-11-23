# Roadmap học DevOps

Không chuyển phase theo lịch nếu gate hoặc evidence còn thiếu. Mỗi lab phải được chạy, xác minh, troubleshoot và dọn trước khi ghi PASS trong `docs/progress.md`.

## Phase 1 — Linux foundation

| Lab | Nội dung | Trạng thái/điều kiện |
|---|---|---|
| 01 | Linux filesystem, users, permissions, process/thread, package manager | Hoàn tất; ACL NOT TESTED vì utility chưa cài. |
| 02 | systemd, transient service, process, signals, journalctl | Hoàn tất; transient units/process/helper files cleanup PASS. |
| 03 | CPU, RAM, load average, memory pressure, disk I/O, cgroups | Hoàn tất; bounded CPU/memory/task cgroup workload PASS; không OOM/disk exhaustion. |
| 04 | IPv4/IPv6, CIDR, DNS, TCP/UDP, route, NAT, firewall | Hoàn tất read-only; DNS/NSS query bounded; không sửa SSH/firewall/network. |
| 05 | Filesystem, inode, mount, storage counters, LVM concepts | Hoàn tất read-only; không mount, partition, format hay cấu hình disk. LVM được giải thích, không tạo PV/VG/LV. |
| 06 | Bash, exit status, quoting, idempotency, temp files, automation | Hoàn tất: private temporary files, idempotency, explicit exit status và exact cleanup PASS. |

## Phase 2 — Docker và ứng dụng

| Lab | Nội dung | Trạng thái/điều kiện |
|---|---|---|
| 07 | Docker Engine, CLI/API, containerd/runc, OCI, OverlayFS, namespaces/cgroups | Tài liệu sẵn sàng; install BLOCKED tới khi live public-service/resource gates đạt và Docker host/network side effects được approve. |
| 08 | Bridge, veth, DNS, NAT, port publishing, SSH tunnel | BLOCKED; chỉ localhost binding, không mở public app ports. |
| 09 | Image layers, writable layer, named volumes, bind mounts, disk metrics | BLOCKED; bounded marker data; không prune hoặc format. |
| 10 | Non-root ASP.NET Core, health, JSON logs, resource limits, Compose | Source build và local HTTP smoke PASS; image/container local và VPS NOT TESTED. |

Đọc từng lab trong `labs/07-docker-engine` tới `labs/10-dotnet-api`. Docker chỉ được cài từ repo chính thức, với exact package versions đã kiểm tra tại thời điểm deploy. Đánh giá firewall/IP forwarding tác động trước; ứng dụng bind localhost và dùng SSH tunnel.

## Phase 3 — containerd

Lab 11 học containerd đi kèm `containerd.io`, OCI, namespaces, snapshots, `ctr` và CRI. Không cài standalone containerd cạnh Docker, không cài kubelet trong lab này. Xem [`labs/11-containerd`](../labs/11-containerd/README.md).

## Phase 4 — kubeadm single-node

Kubernetes là main lab: một control-plane/node duy nhất, workload rất nhẹ, API không public, không swap. Trước khi pin version phải kiểm tra OS/Kubernetes compatibility, runtime, network, cgroups, memory/disk headroom và backup/rollback. Không cài nếu VPS không còn đủ tài nguyên.

## Phase 5 — RKE2 (conditional)

Giữ trong roadmap sau kubeadm backup/cleanup và đánh giá lại requirements/compatibility tại thời điểm chạy. Không bỏ qua minimum requirements hoặc cài đồng thời kubeadm/RKE2 trên cùng host.

## Phase 6 — Rancher (deferred decision)

Chỉ sau khi xem profile/version requirements và resource budget. Nếu VPS không đủ headroom, chuyển Rancher sang máy cá nhân vào tháng sau. Không mua VPS hoặc dịch vụ trả phí; không chạy Rancher stack cùng RKE2 khi budget chưa chứng minh đủ.

## Deferred mặc định trên VPS hiện tại

Rancher management stack, Harbor, GitLab Server, Longhorn, full Prometheus/Grafana/Loki, multi-node HA, GPU, air-gap và production ingress. Các bài cần nhiều node/disk/RAM chuyển sang máy local; không dựng placeholder để đánh dấu đã hoàn thành.
