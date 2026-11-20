# Runbook — Phase 0 và Phase 0.1

## Mục tiêu và nguồn dữ liệu

Thu thập trạng thái thực tế trước khi cài package hoặc mở port. `scripts/preflight.sh` và `scripts/security-baseline.sh` chỉ đọc cấu hình; `scripts/lab01-readonly.sh` có thể chạy một demo tạo file trong `/tmp` nếu được truyền `--permissions-demo`.

Thông tin trong `docs/infrastructure.md` là snapshot SSH trực tiếp đã được làm sạch. Provider Firewall vẫn UNKNOWN cho tới khi kiểm tra TopCloud Portal. Không commit output gốc, IP, hostname đầy đủ, fingerprint, user list hay environment dump.

## Kiểm tra SSH key-only từ Windows

Từ PowerShell ở thư mục repo:

```powershell
ssh -vv -o BatchMode=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no devops-lab "printf 'SSH_KEY_ONLY_OK\n'"
```

PASS khi client debug có ED25519 public key offer, server accept, dòng `Authenticated ... using "publickey"`, và nhận marker `SSH_KEY_ONLY_OK`. `BatchMode` cùng các lựa chọn auth ngăn fallback sang password ở client; vì thế đây là bằng chứng key auth thật, không chỉ là một phiên SSH thành công.

Không lưu toàn bộ `ssh -vv` output vì có thể chứa username, địa chỉ hoặc đường dẫn local key. Rà soát server policy riêng bằng script phía dưới. Trên snapshot hiện tại key login thành công nhưng `sshd -T` cho biết root login và password authentication vẫn được bật.

## Chạy các inventory scripts

Từ PowerShell tại repository root:

```powershell
.\scripts\run-remote.ps1 -Phase phase-0
```

Helper tạo remote `mktemp -d`, upload đúng `preflight.sh`, `security-baseline.sh` và `validate.sh`, chạy `bash -n` riêng cho từng script, chạy validator rồi xóa các file `.sh` trong đúng temporary directory. Không còn dùng file `/tmp` cố định. Exit code inventory không phải security gate: `preflight.sh`/`security-baseline.sh` in rõ `INVENTORY STATUS`; `validate.sh` phân biệt required failure (`1`) với thiếu required evidence (`2`).

Chạy thủ công trong Linux checkout cũng được:

```bash
bash -n scripts/preflight.sh
bash -n scripts/security-baseline.sh
./scripts/preflight.sh
./scripts/security-baseline.sh
```

Script `security-baseline.sh` tóm tắt effective SSH authentication settings và nguồn config/include, family/scope của interface, default routes, UFW status/default config, iptables/ip6tables policy và actions, nft table/chain names, listening port/bind class, cùng relevant systemd unit states. Nó cố ý bỏ addresses và firewall match conditions. Nếu probe lỗi/empty output, script đánh dấu `UNKNOWN` và trả lỗi thay vì coi output rỗng là kết quả an toàn.

`systemd.ufw_unit=active` chỉ mô tả unit state. Dùng `ufw status` để xác định firewall runtime. `ufw show raw` đầy đủ có thể lộ IP/rules; chỉ chạy cục bộ để điều tra và redact trước khi chia sẻ.

## Phase 0.1 — trạng thái đã xác minh

| Gate | Kết quả | Bằng chứng/giới hạn |
|---|---|---|
| SSH connectivity | PASS | SSH alias kết nối được; phiên trực tiếp peer IPv6 tới port 22 |
| SSH key authentication | PASS | ED25519 offer/accept và `publickey` thành công với BatchMode, password fallback tắt ở client |
| SSH server policy | WARNING | `pubkeyauthentication yes`; `passwordauthentication yes`; `permitrootlogin yes`; `kbdinteractiveauthentication no` |
| Host firewall | NOT READY | `ufw status inactive`, 0 user rules; IPv4/IPv6 INPUT ACCEPT; config default input DROP khi UFW bật |
| Provider firewall | UNKNOWN | Chưa truy cập/kiểm tra TopCloud Portal; người dùng cần xác minh ingress IPv4/IPv6 và console rescue |
| Container network security | NOT TESTED | Docker/containerd chưa cài; chưa publish port |
| Kubernetes network security | NOT TESTED | Kubernetes chưa cài; API/etcd/kubelet ports chưa mở |

Snapshot network cũng cho thấy IPv4 route qua interface private và IPv6 default route qua interface IPv6 global. WARP trên Windows do người dùng báo; server chỉ chứng minh SSH peer IPv6, chưa chứng minh source egress ổn định. WARP/Tailscale services trên VPS inactive. Listener ports quan sát được là 22/TCP, 53/TCP, 53/UDP; bind addresses được giữ ngoài Git.

### Lệnh read-only kiểm tra bổ sung

```bash
sudo ufw status verbose
sudo ufw show added
sudo grep -E '^(IPV6|DEFAULT_INPUT_POLICY|DEFAULT_OUTPUT_POLICY|DEFAULT_FORWARD_POLICY)=' /etc/default/ufw
sudo iptables -S
sudo ip6tables -S
sudo nft list ruleset
sudo ss -lntup
sudo grep -nEi 'icmpv6|ipv6-icmp' /etc/ufw/before6.rules
```

Rule dumps có thể chứa interface/IP/source networks; giữ raw output tại VPS/local terminal và redact trước khi chia sẻ. `ufw status` chỉ bao gồm rules UFW-managed; `ufw show raw` và rules files cho complete state. Ubuntu Noble UFW documents describe `--dry-run`, SSH rule ordering, IPv4/IPv6 handling and built-in ICMP rules: [ufw(8)](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html), [ufw-framework(8)](https://manpages.ubuntu.com/manpages/noble/man8/ufw-framework.8.html).

## Security gate trước khi có dịch vụ public

1. Người dùng xác minh trong TopCloud Portal: ingress policy riêng cho IPv4/IPv6, hiện có rule nào cho SSH, và Web Terminal/VNC/rescue console có hoạt động không. Ghi UNKNOWN cho mục nào chưa nhìn thấy.
2. Quyết định riêng về root/password SSH. Hiện password authentication và root login được bật; thay đổi `sshd` cần backup config, validate `sshd -t`, reload có kiểm soát, giữ session cũ và thử session mới. Không thay đổi trong runbook này.
3. Không whitelist cố định một WARP source IPv6 cho tới khi ổn định được xác minh. Không tắt WARP hoặc IPv6.
4. Chỉ xem xét UFW sau khi có provider/out-of-band recovery, rule SSH đúng path, backup và rollback timer. Giữ ICMPv6 rules mặc định của UFW; không sửa `before6.rules` để né lỗi.
5. Docker/Kubernetes services vẫn bị hoãn cho tới khi host/provider ingress rules và binding/SSH tunnel policy được review.

## Firewall plan — chuẩn bị, chưa thực thi

Lệnh dưới đây sẽ đổi default input policy và kích hoạt filtering. UFW `enable` reloads firewall chains và có thể làm rơi connection hiện tại, dù rule cho port 22 đã được thêm; lệnh này chưa chạy. `ufw allow 22/tcp` áp dụng cho cả IPv4 và IPv6 khi `IPV6=yes`, nhưng cho phép mọi source ở lớp host. Với `permitrootlogin yes` và `passwordauthentication yes`, không bật cho tới khi server login risk và Provider Firewall được review.

### Preconditions

- Provider IPv4/IPv6 ingress và rescue/Web Terminal đã được kiểm tra.
- Có SSH session thứ hai độc lập, cùng key login đã xác minh.
- Quyết định password/root SSH đã được xử lý hoặc chấp nhận rõ ràng.
- Kiểm tra `IPV6=yes` và các ICMPv6 rules trong `/etc/ufw/before6.rules`.
- Sao lưu `/etc/ufw` root-only, không đưa backup vào Git:

```bash
sudo install -d -m 700 /root/ufw-backups
sudo sh -c 'umask 077; tar -C /etc -czf "/root/ufw-backups/ufw-$(date -u +%Y%m%dT%H%M%SZ).tar.gz" ufw'
```

### Candidate commands and expected effect

Trước khi enable, đặt policy và thêm SSH rule:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH management'
sudo ufw status verbose
sudo ufw status numbered
```

Expected rules: incoming denied by default, outgoing allowed, SSH TCP 22 allowed for IPv4 and IPv6. Không thêm Kubernetes API, etcd, kubelet, NodePort hoặc app ports. Nếu cần source restriction, xác minh source/path và thay candidate trước khi áp dụng; không cố định WARP IP chưa xác minh.

Sau khi review rules, chạy `sudo ufw --dry-run --force enable` để xem thay đổi. Trước khi bật firewall, arm rollback tự động 5 phút:

```bash
sudo systemd-run --unit=devops-lab-ufw-rollback --on-active=5m --timer-property=AccuracySec=1s /usr/sbin/ufw --force disable
sudo systemctl status devops-lab-ufw-rollback.timer --no-pager
```

Chỉ khi timer hiện active mới chạy lệnh thay đổi:

```bash
sudo ufw --force enable
sudo ufw status verbose
```

Từ một terminal/SSH session mới trên Windows, xác minh lại key-only login:

```powershell
ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no devops-lab "printf 'NEW_SSH_OK\n'"
```

Chỉ sau khi marker `NEW_SSH_OK` nhận được và firewall status đúng, hủy timer:

```bash
sudo systemctl stop devops-lab-ufw-rollback.timer
sudo systemctl is-active devops-lab-ufw-rollback.timer
```

Expected timer state sau khi stop là `inactive` vì one-shot timer đã bị hủy. Verify `ufw status verbose` vẫn active và rule IPv4/IPv6 port 22 còn có hiệu lực. `systemd-run --on-active` tạo transient timer/service; cú pháp dựa theo [systemd-run(1), systemd 255](https://www.freedesktop.org/software/systemd/man/255/systemd-run.html). Timer command chưa chạy/thử trong Phase 0.1.

### Rollback

- Nếu mất SSH, chờ timer 5 phút để lệnh `ufw --force disable` chạy; hoặc dùng verified provider console:

```bash
sudo ufw disable
sudo ufw status verbose
```

- Nếu config bị thay ngoài dự kiến, trước tiên kiểm tra đúng backup bằng `sudo tar -tzf /root/ufw-backups/<backup-file>.tar.gz`. Restore chỉ từ file đã kiểm tra, rồi disable UFW:

```bash
sudo tar -C /etc -xzf /root/ufw-backups/<backup-file>.tar.gz ufw
sudo ufw disable
```

- Không xóa backup cho tới khi kết nối mới, IPv4/IPv6 policy và console recovery được xác nhận.

Chỉ yêu cầu xác nhận thực thi khi preconditions đã xong và đúng bộ lệnh cụ thể này đã được người dùng review.

## Kết quả và bước sau

- **PASS:** direct SSH key authentication; read-only Linux inventory; Linux Fundamentals mode/umask demo.
- **WARNING:** server still allows root password authentication.
- **NOT READY:** host firewall/security baseline for public service deployment.
- **UNKNOWN:** provider firewall and WARP source stability.
- **NOT TESTED:** ACL mutation, external inbound IPv6, NAT egress, container or Kubernetes networking.

Không cài Docker hoặc mở port public cho tới khi Security Gate phù hợp phạm vi đạt yêu cầu. Docker published ports có thể bypass UFW; xem [Docker firewall behavior](https://docs.docker.com/engine/network/packet-filtering-firewalls/).
