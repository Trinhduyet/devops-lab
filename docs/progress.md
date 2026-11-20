# Tiến độ

Ngày bắt đầu theo client context: 2026-11-20.

| Phase | Trạng thái | Bằng chứng |
|---|---|---|
| Repository setup | Hoàn tất bước đầu | Tài liệu, `.gitignore`, Lab 01 và ba script read-only trong workspace |
| Phase 0 — VPS assessment | Hardware baseline PASS; security gates đang tách theo phạm vi | SSH trực tiếp: Ubuntu 24.04.5, KVM, 4 vCPU, 3.8 GiB RAM, disk 40 GB, cgroup v2 |
| Phase 0.1 — Security baseline | SSH connectivity/authentication PASS; host firewall NOT READY; provider firewall UNKNOWN | ED25519 accepted trong BatchMode; server vẫn cho phép password/root login; UFW inactive/0 rules; IPv4/IPv6 INPUT ACCEPT |
| Phase 1 — Linux Fundamentals | Lab 01 read-only baseline và temporary permission exercise PASS; ACL NOT TESTED | 143 process rows/178 thread rows tại thời điểm đo; umask 077 tạo mode 600, chmod 640 tạo mode 640; ACL tools absent; không đổi package/config |
| Phase 1 — Networking/Docker/containerd | Network inventory read-only done; deploy DEFERRED | IPv4 default route qua interface IPv4, IPv6 default route qua interface IPv6; Docker/containerd/kubectl absent; provider ingress và WARP source stability UNKNOWN |
| Phase 2 — kubeadm | Chưa bắt đầu | Chờ Phase 1 và resource gate |
| Phase 3 — RKE2 | Chưa bắt đầu | Cần kubeadm backup/cleanup và resource gate |
| Phase 4 — Rancher | Deferred decision | Cần compatibility/resource assessment; không chạy chung với RKE2 khi thiếu tài nguyên |
| Phase 5 — consolidation | Chưa bắt đầu | Sau các phase khả thi |

## Ranh giới xác minh

- **Đã làm trong workspace:** tạo repository, tài liệu và script preflight chỉ đọc; kiểm tra cú pháp script.
- **SSH key:** Client debug xác nhận ED25519 key offer, server accept và `publickey` authentication thành công trong BatchMode; không dùng password.
- **SSH server policy:** `pubkeyauthentication yes`, `passwordauthentication yes`, `permitrootlogin yes`, `kbdinteractiveauthentication no`; không thay đổi config.
- **Firewall:** `ufw status inactive`, UFW user rules = 0, IPv4/IPv6 INPUT policy ACCEPT; `/etc/default/ufw`: `IPV6=yes`, input DROP, output ACCEPT, forward DROP. `systemd.ufw_unit=active` không đồng nghĩa firewall đang bật.
- **Network/listeners:** SSH session peer IPv6; IPv4 default route qua interface riêng, IPv6 default route qua interface IPv6 global. Listener: 22/TCP wildcard; 53/TCP và 53/UDP loopback. Addresses không lưu. Provider firewall UNKNOWN.
- **Linux Fundamentals:** kernel 6.8.0-142-generic, x86_64/64-bit, 4 vCPU; root ext4 ~38 GB/~36 GB free; root UID/GID 0; `/tmp` mode 1777; Bash 5.2.21, apt 2.8.4, dpkg architecture amd64.
- **Permissions exercise:** umask 077 tạo file mode 600; chmod 640 cho mode 640; file tạm được dọn khi script kết thúc. ACL chưa test vì `getfacl`/`setfacl` không có; không cài package.
- **Chưa chứng minh:** provider ingress firewall, WARP egress stability, external inbound IPv6, NAT/egress, module runtime behavior, disk I/O hoặc khả năng chịu tải Kubernetes.

## Bước kế tiếp

Kiểm tra Provider Firewall trong TopCloud Portal; xử lý password-based root SSH theo kế hoạch riêng có backup/recovery; sau đó review UFW plan và xác nhận rõ ràng trước khi enable. Chưa cài Docker hoặc mở dịch vụ public.
