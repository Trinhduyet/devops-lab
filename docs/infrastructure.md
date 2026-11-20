# Hạ tầng lab

## Inventory đã quan sát

Nguồn chính là preflight trực tiếp qua Windows OpenSSH alias `devops-lab`; các output người dùng gửi trước đó được dùng để đối chiếu. Snapshot trực tiếp mới nhất được ưu tiên khi có khác biệt. Hostname, machine/boot ID, địa chỉ đầy đủ và fingerprint không được lưu tại đây.

| Hạng mục | Quan sát | Đánh giá |
|---|---|---|
| OS/kernel | Ubuntu 24.04.5 LTS, x86-64, kernel 6.8.0-142-generic | Phù hợp làm Linux lab; xác minh compatibility theo bản runtime trước khi cài |
| CPU | 4 vCPU | Đạt ngưỡng kubeadm và CPU khuyến nghị của RKE2 |
| RAM/swap | 3.8 GiB total, 3.3 GiB available tại lúc đo, không có swap | Đủ cho Linux lab; Kubernetes workload phải rất nhẹ; RKE2 ở sát mức RAM tối thiểu |
| Disk | Disk 40 GB; root ext4 khoảng 37.7 GiB, 35.4 GiB available lúc đo; `ROTA=0` | Tạm đủ cho lab nhỏ; thuộc tính thiết bị ảo không chứng minh media vật lý |
| Virtualization/cgroups | KVM, cgroup v2; controllers `cpu`, `memory`, `io`, `pids` có mặt | Thuận lợi cho runtime; cần kiểm tra overlay/bridge modules trước Docker |
| Network | IPv6 global trên một interface, IPv4 trên interface riêng; IPv4 và IPv6 đều có default route qua interface tương ứng; không thấy overlay interface | Không thấy public IPv4 trực tiếp; NAT/egress chưa kiểm tra. Địa chỉ/gateway không lưu trong repo |
| SSH/auth | Non-interactive ED25519 key được offer/accept; session peer IPv6, port 22. `sshd -t` PASS; `sshd -T -C` effective values: `pubkeyauthentication yes`, `passwordauthentication yes`, `permitrootlogin yes`, `kbdinteractiveauthentication no` | Key auth PASS; password authentication/root login vẫn được phép theo server config. Chưa đổi SSH; source address không lưu |
| WARP/Tailscale | `warp-svc` và `tailscaled` inactive; `warp-cli` không có trên VPS | Không có WARP/Tailscale interface ở snapshot hiện tại; không có thay đổi WARP nào được thực hiện |
| Firewall | `ufw status` **inactive**, 0 saved/numbered user rules; IPv4/IPv6 `INPUT` policy `ACCEPT`. `/etc/default/ufw`: `IPV6=yes`, input `DROP`, output `ACCEPT`, forward `DROP`; nftables tables/chains hiện diện | `systemd.ufw_unit=active` không có nghĩa firewall bật. Nếu enable trước khi thêm SSH allow rule, SSH có thể bị chặn; provider firewall chưa xác minh |
| DNS/listeners | Resolver hoạt động trong snapshot trước; 22/TCP bind wildcard, 53/TCP và 53/UDP bind loopback | Addresses cụ thể không lưu. Public DNS authoritative chưa xác minh |
| Forwarding/kernel modules | `net.ipv4.ip_forward=0`; bridge sysctl không tồn tại; `overlay`/`br_netfilter` có trong kernel package nhưng chưa nạp | Module availability PASS; Docker/Kubernetes runtime chưa sẵn sàng |
| Runtime | Không tìm thấy Docker, Compose, containerd, ctr hoặc crictl | Chưa cài runtime |
| Host health | systemd running, không có failed units, clock synchronized | PASS cho snapshot thời điểm đo |
| Provider/package/hạn sử dụng | Chưa rõ | Xác minh từ provider panel |

## Network và bảo mật

- SSH config inspection đã xác nhận `/etc/ssh/sshd_config` include `sshd_config.d/*.conf`; các drop-ins có auth directive gồm `10-topcloud-sshd.conf`, `50-cloud-init.conf` và `60-cloudimg-settings.conf`. Effective `PasswordAuthentication` vẫn `yes`; chi tiết và candidate hardening nằm trong [SSH hardening runbook](runbooks/ssh-hardening.md). Không thay đổi SSH.

- Read-only assessment và Linux Fundamentals được chạy trực tiếp bằng Windows OpenSSH từ runtime hiện tại. Mọi số liệu là snapshot theo thời điểm, không phải giám sát liên tục.
- Chưa đo public IPv4 egress/NAT, inbound IPv6 từ mạng ngoài, DNS authoritative, disk I/O hoặc firewall ở provider.
- `ufw` thực tế đang inactive, không có user rules đã lưu, và active INPUT policy là ACCEPT. Config UFW đặt input DROP; bật mà chưa có SSH allow rule có thể cắt SSH IPv6 hiện tại. `sshd` nghe mọi interface; server policy còn cho phép root login và password authentication. Nếu provider firewall không chặn, SSH có thể nhận kết nối qua IPv6.
- Một output cũ do người dùng chạy có Tailscale interface/rules; snapshot trực tiếp mới nhất không có interface/rules đó và `tailscaled` inactive. Không dựa vào Tailscale làm đường firewall hiện tại.
- SSH session trực tiếp hiện tại dùng IPv6. Client dùng WARP theo thông tin người dùng; chưa xác minh egress/source ổn định để tạo allowlist. Không bật UFW nếu chưa có rule đúng path, console rollback, rollback timer và SSH session thứ hai.
- Docker bridge port publishing có thể bypass UFW; firewall host/provider và cách bind port phải được thiết kế cùng nhau trước khi chạy container.
- IPv4 forwarding đang tắt và modules chưa được xác minh. Không tự bật sysctl/nạp module trước khi chọn Docker/Kubernetes và hiểu mục đích từng thay đổi.
- Cloudflare WARP được nêu là trên execution client; service WARP trên VPS hiện inactive. Không tắt WARP trên client. Không mở Kubernetes API, etcd, kubelet hoặc NodePort ra Internet mặc định.
- Bản output gốc chứa thông tin định danh và địa chỉ mạng; không commit raw output vào Git.

## Kết luận hiện tại

Có thể tiếp tục Linux và networking labs chỉ đọc. Docker/kubeadm/RKE2 cần qua firewall và runtime compatibility checks. Rancher cùng các stack nặng được hoãn do giới hạn RAM. Không dùng Swap để bù RAM.
