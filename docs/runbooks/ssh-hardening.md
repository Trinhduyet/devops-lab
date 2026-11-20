# Runbook — SSH key-only hardening (plan, not applied)

## Phạm vi và trạng thái

Đây là kế hoạch riêng cho SSH. Chưa sửa `sshd_config`, drop-in, SSH service, firewall hay network. Giữ policy ở trạng thái chưa apply cho tới khi preconditions hoàn tất và change set cụ thể được xác nhận.

Không dựa vào gate này để chặn Linux labs an toàn. Public-service gate nằm riêng trong `scripts/validate.sh public-services`.

## Assessment method

`sshd -t` kiểm tra syntax; `sshd -T -C` là canonical effective output sau khi OpenSSH áp dụng Include, source ordering, global first-obtained settings, `Match` blocks và connection context. Một dòng cấu hình trong file riêng lẻ không chứng minh effective policy.

`scripts/security-baseline.sh` lấy bốn trường từ chính SSH session hiện hành (`SSH_CONNECTION`): client address/port và server address/port. Với `UseDNS yes`, client hostname được phân giải theo reverse lookup; với `UseDNS no`, client address được dùng làm host value. Không bao giờ dùng hostname của server làm client `host`. Script kiểm tra syntax, đếm đúng một canonical output cho từng auth directive, rồi đọc Include/Match sources theo OpenSSH order. Parse lỗi, context thiếu hoặc output trùng/thiếu được báo `UNKNOWN`/failure, không suy luận an toàn từ output rỗng.

Client key-only success là một phép thử riêng; nó không chứng minh server đã tắt password authentication. Detailed live snapshot/config source paths được giữ local-only, không đưa vào repository công khai.

## Candidate policy

```text
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
KbdInteractiveAuthentication no
```

Trước khi chọn vị trí candidate, kiểm tra `Include` ordering và mọi `Match` block trong cấu hình đang chạy. Chỉ dùng drop-in khi `sshd -T -C` chứng minh candidate thắng precedence trong context thật; không sửa file do OS image, cloud-init hoặc provider quản lý. Luôn kiểm tra effective output sau khi chuẩn bị candidate; không suy ra precedence chỉ từ filename.

## Preconditions — phải đạt trước khi apply

1. Trong provider portal, xác minh Web Console/rescue console hoạt động và tài khoản có thể truy cập. Provider firewall/recovery evidence vẫn UNKNOWN nếu chưa được xác minh trực tiếp.
2. Mở hai SSH sessions độc lập bằng alias/key hiện tại; giữ session thứ nhất làm recovery.
3. Kiểm tra key được dùng thuộc đúng tài khoản `root`; không có key/credential mới được đưa vào repo.
4. Rà soát Include, mọi file được include, từng `Match` block và effective settings ngay trước thay đổi. Nếu source order hoặc context khác lần assessment trước, cập nhật plan. Global directives thường dùng first-obtained value; Match values phải được kiểm tra bằng đúng connection context, không suy ra từ file cuối cùng.
5. Tạo archive root-only, kiểm tra archive liệt kê đúng cấu hình trước khi sửa:

   ```bash
   install -d -m 700 /root/ssh-backups
   backup="/root/ssh-backups/sshd-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
   umask 077
   tar -C / -czf "$backup" etc/ssh
   chmod 600 "$backup"
   tar -tzf "$backup" | sed -n '1,40p'
   ```

6. Xác nhận backup có `etc/ssh/sshd_config` và các drop-ins hiện hành; ghi lại đúng archive path trong terminal riêng, không lưu vào Git.

Nếu thiếu console, session thứ hai, backup đọc được hoặc đúng key login, **không apply**.

## Apply sequence — chưa chạy

Chỉ sau explicit approval cho chính sequence bên dưới. Các lệnh này hiện là runbook text, chưa được thực thi:

1. Từ precondition đã hoàn tất, giữ shell variables `$backup` và `$rollback_script` trỏ đúng archive đã verify và một path mới dưới `/root/ssh-backups`. Tạo rollback helper:

   ```bash
   rollback_script="/root/ssh-backups/rollback-ssh-$(date -u +%Y%m%dT%H%M%SZ).sh"
   cat > "$rollback_script" <<EOF
   #!/usr/bin/env bash
   set -euo pipefail
   rm -f -- /etc/ssh/sshd_config.d/00-devops-lab-hardening.conf
   tar -C / -xzf "$backup" etc/ssh
   /usr/sbin/sshd -t
   /usr/bin/systemctl reload ssh.service
   EOF
   chmod 700 "$rollback_script"
   bash -n "$rollback_script"
   ```

   Kiểm tra lại literal archive path bên trong helper; path phải là archive root-only vừa verify.
2. Arm rollback 5 phút trước khi sửa config và xác nhận timer active:

   ```bash
   timer_unit="devops-ssh-hardening-rollback-$(date +%s)"
   systemd-run --unit="$timer_unit" --on-active=5m --timer-property=AccuracySec=1s "$rollback_script"
   systemctl is-active "$timer_unit.timer"
   ```

   Chỉ tiếp tục khi state là `active`; session hiện tại vẫn được giữ nguyên.
3. Tạo candidate drop-in `/etc/ssh/sshd_config.d/00-devops-lab-hardening.conf`:

   ```bash
   cat > /etc/ssh/sshd_config.d/00-devops-lab-hardening.conf <<'EOF'
   PubkeyAuthentication yes
   PasswordAuthentication no
   PermitRootLogin prohibit-password
   KbdInteractiveAuthentication no
   EOF
   chmod 644 /etc/ssh/sshd_config.d/00-devops-lab-hardening.conf
   ```

4. Chạy `sshd -t`. Nếu fail, không reload; chạy chính `$rollback_script`, rồi kiểm tra lại `sshd -t` và dừng timer sau khi restore đã xác nhận.
5. Dùng chính SSH connection hiện hành để dựng `-C` context; không ghi địa chỉ vào tài liệu:

   ```bash
   read -r client_address _ server_address server_port <<< "$SSH_CONNECTION"
   usedns=$(sshd -T | awk '$1 == "usedns" {print $2; count++} END {if (count != 1) exit 1}')
   client_host=$client_address
   if [[ "$usedns" == yes ]]; then client_host=$(getent hosts "$client_address" | awk 'NF >= 2 {print $2; exit}'); fi
   sshd -T -C "user=$(id -un),host=$client_host,addr=$client_address,laddr=$server_address,lport=$server_port" \
     | grep -E '^(pubkeyauthentication|passwordauthentication|permitrootlogin|kbdinteractiveauthentication) '
   ```

   Required effective output: `pubkeyauthentication yes`, `passwordauthentication no`, `permitrootlogin prohibit-password`, `kbdinteractiveauthentication no`.
6. Nếu effective values đúng, kiểm tra `systemctl is-active ssh.service`, rồi `systemctl reload ssh.service`; không restart host.
7. Giữ session cũ và từ một terminal Windows mới kiểm tra key-only:

   ```powershell
   ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no devops-lab "printf 'SSH_HARDENED_KEY_OK\n'"
   ```

8. Chỉ khi session mới nhận marker và `sshd -T -C` cho đúng bốn effective values mới hủy timer: `systemctl stop "$timer_unit.timer"`, rồi xác minh `systemctl show --property=ActiveState --value "$timer_unit.timer"` là `inactive`. Nếu không, giữ session cũ và chờ timer hoặc dùng console đã xác minh để rollback.

## Rollback

Rollback phải dùng đúng archive đã verify: xóa riêng candidate `00-devops-lab-hardening.conf`, giải nén archive về `/`, chạy `sshd -t`, rồi `systemctl reload ssh.service`. Không `rm -rf /etc/ssh`, không restore archive không rõ nguồn, không đóng session quản trị đang hoạt động cho tới khi key login mới được kiểm chứng.

## Verification và đóng gate

- `sshd -t` trả exit 0.
- Effective settings khớp candidate trong connection context thật.
- Session SSH thứ hai qua ED25519 key thành công khi client password fallback bị tắt.
- Rollback timer đã bị hủy sau verification; SSH service active.
- Cập nhật `docs/progress.md` và evidence đã làm sạch. Không ghi IP, hostname đầy đủ, key fingerprint, archive contents ngoài tên file, hay credentials.

`run-remote.ps1 -Phase public-services` thực hiện lại SSH key-only client check và đọc host policy trực tiếp trên VPS trong session hiện hành. `sshd -T -C` dùng client address/hostname, server address và port từ `SSH_CONNECTION`; không dùng hostname của server làm client hostname. OpenSSH phân giải `Include` và `Match`. Output phải có đúng một canonical value cho mỗi directive:

```text
pubkeyauthentication yes
passwordauthentication no
permitrootlogin prohibit-password
kbdinteractiveauthentication no
```

UFW được truy vấn trực tiếp trên VPS ở mỗi lần chạy. Host state không lấy từ file evidence cũ.

File local bị ignore `docs/evidence/public-services.env` chỉ giữ hai mục không thể kiểm chứng từ host. Mỗi dòng theo schema `KEY=STATUS,SOURCE,OBSERVED_AT_UTC`:

```text
PROVIDER_FIREWALL=PASS,MANUAL,2026-11-20T08:00:00Z
CONSOLE_RECOVERY=PASS,MANUAL,2026-11-20T08:00:00Z
```

`Provider/console evidence` phải được kiểm tra trong portal trong vòng 24 giờ, không duplicate/malformed và `SOURCE=MANUAL`. Thiếu hoặc stale trả exit 2; duplicate, malformed, sai provenance hoặc `FAIL` trả exit 1. SSH key auth, effective SSH policy và firewall state là live checks; không chép chúng vào file evidence. File evidence không được commit.
