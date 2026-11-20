# Troubleshooting index

Chỉ ghi root cause sau khi có bằng chứng. Mỗi case cần đủ: Symptoms → Root Cause → Investigation → Resolution → Verification → Prevention.

## Linux / Phase 1

| Case | Thu thập ban đầu | Trạng thái |
|---|---|---|
| CPU high | `uptime`, `top`, `ps`, `pidstat` | Chưa thực hành |
| Memory pressure / OOM | `free -h`, `vmstat`, `dmesg -T`, cgroup counters | Chưa thực hành; không tạo áp lực trên production |
| Disk full / inode | `df -hT`, `df -ih`, `du -xhd1` | Chưa thực hành |
| Disk I/O bottleneck | `iostat -xz`, `iotop`, `vmstat` | Chưa thực hành |
| Service startup failure | `systemctl status`, `journalctl -u <unit>` | Lab 02 lifecycle PASS; chưa cố ý làm service fail |
| Process signal handling | `ps`, `kill -TERM`, Bash `wait` status | Lab 02 SIGTERM/wait=143 PASS |
| Port conflict | `ss -lntup` | Chưa thực hành |
| SSH failure | provider console, client `ssh -vv`, server auth logs | Chưa thực hành; không sửa firewall từ SSH duy nhất |
| Permission denied | `namei -l`, `stat`, `getfacl` | Chưa thực hành |
| DNS/network timeout | `getent`, `dig`, `ip route`, `ss`, `curl -v` | Chưa thực hành |
| Certificate error | system time, chain, SNI, trust store, expiry | Chưa thực hành |

## Phase 0 — runtime finding

| Symptoms | Root Cause | Investigation | Resolution | Verification | Prevention |
|---|---|---|---|---|---|
| `sysctl net.bridge.bridge-nf-call-iptables` trả exit 1 và `/proc/sys/net/bridge/...` không tồn tại | Kernel hiện tại không expose bridge netfilter sysctl; đó là optional container-network evidence, không phải lỗi của cả inventory | Đọc diagnostic của sysctl và đối chiếu kernel module/sysctl facts; không che stderr | Preflight ghi diagnostic/exit status thành `NOT TESTED` khi key không tồn tại; không cài package/nạp module | Rerun `validate.sh phase-0`: preflight/security inventory collected; validator exit 0 | Tách từng optional kernel key khỏi required inventory; giữ exit status và không coi output rỗng là PASS |

## Lab 02 — runtime findings

| Symptoms | Root Cause | Investigation | Resolution | Verification | Prevention |
|---|---|---|---|---|---|
| Ubuntu `bash -n` từ chối script gần `else` | Một dòng do edit PowerShell có CRLF; Git Bash local chấp nhận, Ubuntu Bash không | Remote `bash -n` riêng từng upload script; xác định dòng CRLF bằng byte scan | Chuẩn hóa script về LF; helper kiểm tra cú pháp trên remote trước khi thực thi | `bash -n lab02-systemd.sh` PASS qua SSH helper; Lab 02 sau đó PASS | Giữ `.gitattributes` LF và kiểm tra trên target Bash, không chỉ local Windows shell |
| `Permission denied` khi validator gọi Lab 02 | `scp` upload script với mode không executable | Remote syntax check PASS nhưng validator gọi đường dẫn trực tiếp bị exit 126 | Helper `chmod 700` trên các `.sh` trong unique temp directory | Lab validator thực thi thành công; helper dọn temp directory | Không dựa vào SCP để giữ Unix execute bit; chỉ chmod file tạm do helper tạo |
| Signal check trả exit 0 sau SIGTERM; unit unload trước cleanup | Signal gửi trước khi child hoàn tất exec; transient unit có thể tự unload sau stop | Quan sát `wait` status và `systemctl show LoadState`/`ActiveState` | Chờ `/proc/<pid>/comm` xác nhận `sleep`; cleanup coi `LoadState=not-found` là đã được systemd thu hồi | SIGTERM trả `wait=143`; unit stop inactive; cleanup PASS | Chỉ signal process đã xác minh và cleanup theo unit name exact; không dùng wildcard |

## CI — repository validation

| Symptoms | Root Cause | Investigation | Resolution | Verification | Prevention |
|---|---|---|---|---|---|
| GitHub Actions `Required documentation, Bash syntax and tracked-path gates` thất bại khi gọi ShellCheck | ShellCheck cảnh báo biến retry không được đọc (`SC2034`) và pattern `crash.log` bị bao phủ bởi `*.log` (`SC2221`/`SC2222`) | Tải job log của run `44703366474`; các docs, Bash syntax, executable bits và tracked-path guard đã PASS trước khi ShellCheck chặn bước sau | Dùng bộ đếm retry có đọc trong điều kiện vòng lặp; bỏ case thừa và helper validator không sử dụng; làm rõ escaping DNS | Local `validate.sh repo` PASS sau sửa; ShellCheck local chưa cài, đợi GitHub Actions rerun để có bằng chứng CI cuối | Giữ ShellCheck trong validator/CI để lỗi lint chặn sớm; chỉ ghi CI PASS sau workflow xanh thực tế |

## Kubernetes (sau khi đạt gate)

Pending/FailedScheduling, CrashLoopBackOff, ImagePullBackOff, OOMKilled, Evicted, FailedMount, NodeNotReady, CoreDNS/service/Ingress errors, RBAC Forbidden, certificate expiry, containerd/CNI/etcd failure. Các case cần multi-node/GPU sẽ chuyển sang môi trường phù hợp thay vì mô phỏng sai trên một VPS.
