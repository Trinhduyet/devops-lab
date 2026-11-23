# Lab 07 — Docker Engine và container runtime

## Mục tiêu và trạng thái

Hiểu đường đi từ Docker CLI tới kernel, cài Docker Engine qua repository chính thức khi các gate đạt, xác minh phiên bản và chạy workload có giới hạn. Lab này chưa được cài trên VPS: public-service gate hiện chưa đạt do live host SSH/UFW checks; không thay đổi host trong lần đánh giá này.

## Lý thuyết

- Docker CLI gửi API request qua Unix socket `/var/run/docker.sock` tới `dockerd`. Quyền truy cập socket gần tương đương quyền root trên host; không publish API TCP và không thêm user vào group `docker` như cách né quyền.
- `dockerd` quản lý image, network, volume và gọi `containerd`; containerd quản lý image/content/snapshot và gọi OCI runtime như `runc` để tạo container process.
- OCI image là manifest/config/layers. Kernel dùng namespaces để tách process, mount, network và IPC; cgroups v2 theo dõi/giới hạn CPU, memory và PIDs. Container vẫn dùng chung kernel host.
- `overlay2`/OverlayFS ghép các image layers read-only với writable container layer. File ghi vào writable layer mất khi container bị xóa; dữ liệu cần lưu phải đặt trên volume hoặc bind mount có kế hoạch.
- Docker có thể tự cấu hình forwarding và firewall rules. Published ports có thể đi ngoài đường xử lý UFW thông thường; vì vậy cài daemon là thay đổi network/security của host.

## Kiến trúc

```text
docker CLI --Unix socket/API--> dockerd --> containerd --> runc --> Linux kernel
                                      |                    |-- namespaces
                                      |                    |-- cgroups v2
                                      |                    `-- capabilities/seccomp
                                      |-- image layers / OverlayFS
                                      |-- bridge / NAT / packet filtering
                                      `-- volumes
```

## Điều kiện và resource gates

- Đọc [resource budget](../../docs/resource-budget.md), [SSH runbook](../../docs/runbooks/ssh-hardening.md), [UFW runbook](../../docs/runbooks/phase-0-preflight.md), skill [container-runtime-lab](../../.agents/skills/container-runtime-lab/SKILL.md).
- Trước khi cài: chạy lại phase-0 và `public-services`; có provider/rescue evidence còn fresh; xem `MemAvailable`, disk free, cgroup v2, `overlay`, `br_netfilter`, forwarding, UFW/nftables, packages và services.
- Ubuntu 24.04 amd64 được Docker Engine hỗ trợ theo tài liệu chính thức đã kiểm tra ngày 2026-11-23. Trước khi ghim package, lấy phiên bản hiện hành bằng `apt-cache madison docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`; chưa có package version nào được phê duyệt trong lab này.
- Chỉ cài sau explicit approval cho package cài đặt và side effect Docker lên packet filtering/IP forwarding. Không đồng thời thay đổi SSH/UFW. Không expose port/API.
- Gate workload tối thiểu: VPS vẫn có ít nhất 1 GiB `MemAvailable`, tối thiểu 5 GiB disk trống, không có `memory`/`io` PSI pressure tăng bất thường trong quan sát liên tiếp. Đây là ngưỡng bảo thủ cho lab, không phải sizing production.

## Commands

### Read-only inventory trước cài

```bash
cat /etc/os-release
uname -m
free -h
df -h /
stat -fc %T /sys/fs/cgroup
grep -E '^(MemTotal|MemAvailable|SwapTotal):' /proc/meminfo
cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io
lsmod | grep -E '^(overlay|br_netfilter) ' || true
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
sudo ufw status verbose
sudo nft list ruleset
dpkg-query -W docker-ce docker-ce-cli containerd.io docker.io containerd runc 2>/dev/null || true
systemctl show docker containerd --property=LoadState,ActiveState,MemoryCurrent
```

Lệnh `sudo nft list ruleset` và SSH/firewall output chỉ đọc tại terminal; không commit raw values.

### Sau khi gate đạt và package version được duyệt

Theo đúng hướng dẫn [Docker Engine trên Ubuntu](https://docs.docker.com/engine/install/ubuntu/): cấu hình keyring/repository chính thức, inspect candidate versions rồi cài đúng versions đã ghi nhận. Không copy lệnh cài `latest` vào script tự động.

```bash
docker version
docker info --format '{{.ServerVersion}} {{.Driver}} {{.CgroupVersion}}'
systemctl show docker containerd --property=LoadState,ActiveState,MemoryCurrent
docker context ls
sudo ss -lntup
```

Chạy sample workload chỉ sau khi có image tag và digest được verify, với `--memory`, `--cpus`, `--pids-limit`, `--read-only`, `--cap-drop ALL`, `--security-opt no-new-privileges` và thời lượng tối đa 60 giây. Dùng Compose Lab 10 để chạy API loopback-bound; không chạy `docker run -p 8080:8080`.

## Hands-on và expected output

| Exercise | Quan sát | Expected |
|---|---|---|
| CLI/server relationship | `docker version` | Có Client và Server; version server khớp package đã pin. |
| Driver/cgroups | `docker info` | cgroup v2, storage driver được kernel/daemon hỗ trợ; ghi lại giá trị đã thấy. |
| Process ownership | `systemctl show docker containerd` và `ps -eo pid,ppid,comm,cgroup` | daemon và runtime process thuộc service manager; container workload gắn cgroup. |
| OCI runtime | `docker inspect <lab-container>` | Image digest, user, state, caps/security options và resource limits khớp khai báo. |
| API exposure | `sudo ss -lntup` | Docker API chỉ qua Unix socket; không có TCP API listener. |

Commands thực thi qua `scripts/run-remote.ps1` chỉ sau gate/approval. Runtime evidence: **NOT TESTED** trên VPS; Docker package và service chưa được cài.

## Troubleshooting

- `Cannot connect to the Docker daemon`: kiểm tra `systemctl status docker`, journal, socket permissions; không thêm user vào `docker` group.
- `overlay`/cgroup error: kiểm tra kernel/fs/cgroup và `docker info`; không tự load module hay đổi sysctl nếu chưa được approve.
- Container start nhưng API không truy cập: kiểm tra `docker inspect` port mapping, `ss`, Compose binding và SSH tunnel; đừng mở public firewall.
- Host port xuất hiện public: dừng chính service lab và xác minh binding trước khi làm thêm thay đổi; Docker published ports có thể bypass UFW path.

## Security, backup/rollback và cleanup

- Docker daemon package/service là host change, không phải reversible app-only test. Trước khi cài: ghi package versions, kiểm tra backup/rollback và đánh giá forwarding/filter changes. Approval cho install không đồng nghĩa approval cho UFW hay SSH edits.
- Không có persistent app data trong Lab 07. Không dùng `docker system prune`, `docker volume prune` hoặc xóa objects không thuộc lab.
- Dừng/xóa đúng Compose project đã tạo; kiểm tra `docker ps -a`, `docker network ls`, `docker volume ls`, `systemctl show docker containerd` và listener. Giữ Docker Engine cài giữa các lab sau, trừ khi rollback uninstall được phê duyệt riêng.

## Interview Q&A

1. **Container có phải VM không?** Không; container process dùng chung host kernel và được cô lập bằng namespaces/cgroups.
2. **Docker socket vì sao nhạy cảm?** Docker API có thể mount host filesystem và tạo privileged workload, nên quyền socket thường tương đương root.
3. **CPU quota khác CPU request của Kubernetes thế nào?** Cgroup quota giới hạn thời gian CPU được dùng; Kubernetes request dùng cho scheduling và không tự tạo quota tương đương.
4. **Vì sao `-p` nguy hiểm với UFW?** Docker thiết lập forwarding/NAT rules riêng nên traffic có thể không đi qua UFW INPUT path dự kiến.
5. **Writable layer có bền không?** Không; xóa container sẽ xóa writable layer. Dữ liệu bền cần volume hoặc bind mount được quản lý.

## Verification và cleanup record

- Docker Engine/VPS deployment: **BLOCKED / NOT TESTED**.
- Không có temporary workload/container/network/volume tạo trong lần đánh giá này; cleanup: **NOT APPLICABLE**.
- Chỉ chuyển PASS sau khi cài được duyệt, live verification, bounded exercise và exact cleanup đều có output thật.

## Tài liệu chính thức

- [Docker Engine install — Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker packet filtering and firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
- [Docker Engine security](https://docs.docker.com/engine/security/)
- [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec)
