# Runbook — SSH key-only hardening (plan, not applied)

## Phạm vi và trạng thái

Đây là kế hoạch riêng cho SSH. Chưa sửa `sshd_config`, drop-in, SSH service, firewall hay network. SSH là đường quản trị duy nhất đã được dùng để xác minh VPS; thay đổi chỉ được thực hiện sau khi preconditions hoàn tất và có explicit approval cho đúng change set này.

Không dựa vào gate này để chặn Linux labs an toàn. Public-service gate nằm riêng trong `scripts/validate.sh public-services`.

## Findings đã xác minh trực tiếp

- `sshd -t`: **PASS** ở snapshot kiểm tra.
- Effective settings với `sshd -T -C` theo SSH session hiện tại: `pubkeyauthentication yes`, `passwordauthentication yes`, `permitrootlogin yes`, `kbdinteractiveauthentication no`, `authenticationmethods any`.
- `/etc/ssh/sshd_config` có `Include` tại dòng 12; các file quan sát được trong `sshd_config.d` được xử lý theo tên: `10-topcloud-sshd.conf`, `50-cloud-init.conf`, `60-cloudimg-settings.conf`. Cả TopCloud và cloud-init drop-in đặt `passwordauthentication yes`; drop-in `60-cloudimg-settings.conf` đặt `no`, nhưng effective setting vẫn là `yes` vì directive được lấy trước đó. `10-topcloud-sshd.conf` đặt `permitrootlogin yes`.
- SSH key-only từ client đã PASS. Đây không chứng minh server đã tắt password auth.
- Provider firewall và rescue/Web Console vẫn **UNKNOWN** cho tới khi được xác minh trong TopCloud Portal.

## Candidate policy

```text
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
KbdInteractiveAuthentication no
```

Config hiện include `/etc/ssh/sshd_config.d/*.conf` ở dòng 12, trước các global directive còn lại. Nếu kiểm tra lại vẫn cho thấy đúng thứ tự, candidate có thể là drop-in mới `00-devops-lab-hardening.conf`, đứng trước `10-topcloud-sshd.conf`. Không chỉnh/xóa các file do TopCloud hoặc cloud-init quản lý. Luôn kiểm tra hiệu lực bằng `sshd -T -C`; không dựa riêng vào nội dung file mới.

## Preconditions — phải đạt trước khi apply

1. Trong TopCloud Portal, xác minh Web Console/rescue console hoạt động và tài khoản có thể truy cập. Provider firewall vẫn ghi UNKNOWN nếu chưa có bằng chứng.
2. Mở hai SSH sessions độc lập bằng alias/key hiện tại; giữ session thứ nhất làm recovery.
3. Kiểm tra key được dùng thuộc đúng tài khoản `root`; không có key/credential mới được đưa vào repo.
4. Rà soát Include, toàn bộ drop-ins, `Match` conditions và effective settings ngay trước thay đổi; nếu file/order khác snapshot này, dừng và cập nhật plan.
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
   set -- $SSH_CONNECTION
   client=$1; server=$3; port=$4
   sshd -T -C "user=root,host=$(hostname),addr=$client,laddr=$server,lport=$port" \
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

`scripts/validate.sh public-services` yêu cầu file local bị ignore `docs/evidence/public-services.env` với các status đã xác minh (không ghi địa chỉ hoặc raw output):

```text
SSH_KEY_ONLY=PASS
SSH_SERVER_AUTH=PASS
HOST_FIREWALL=PASS
PROVIDER_FIREWALL=PASS
CONSOLE_RECOVERY=PASS
```

`SSH_SERVER_AUTH=PASS` chỉ khi cả bốn effective SSH settings trên đúng connection context; Provider Firewall chỉ PASS sau khi đã xem policy trong portal. Thiếu field/UNKNOWN trả exit 2; field FAIL trả exit 1. File evidence không được commit.
