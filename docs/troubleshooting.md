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
| SSH failure | provider console, client `ssh -vv`, server auth logs | Chưa thực hành; không sửa firewall tỷ�h��춻�q�^vgs

| Symptoms | Root Cause | Investigation | Resolution | Verification | Prevention |
|---|---|---|---|---|---|
| Ubuntu `bash -n` từ chối script gần `else` | Một dòng do edit PowerShell có CRLF; Git Bash local chấp nhận, Ubuntu Bash không | Remote `bash -n` riêng từng upload script; xác định dòng CRLF bằng byte scan | Chuẩn hóa script về LF; helper kiểm tra cú pháp trên remote trước khi thực thi | `bash -n lab02-systemd.sh` PASS qua SSH helper; Lab 02 sau đó PASS | Giữ `.gitattributes` LF và kiểm tra trên target Bash, không chỉ local Windows shell |
| `Permission denied` khi validator gọi Lab 02 | `scp` upload script với mode không executable | Remote syntax check PASS nhưng validator gọi đường dẫn trực tiếp bị exit 126 | Helper `chmod 700` trên các `.sh` trong unique temp directory | Lab validator thực thi thành công; helper dọn temp directory | Không dựa vào SCP để giữ Unix execute bit; chỉ chmod file tạm do helper tạo |
| Signal check trả exit 0 sau SIGTERM; unit unload trước cleanup | Signal gửi trước khi child hoàn tất exec; transient unit có thể tự unload sau stop | Quan sát `wait` status và `systemctl show LoadState`/`ActiveState` | Chờ `/proc/<pid>/comm` xác nhận `sleep`; cleanup coi `LoadState=not-found` là đã được systemd thu hồi | SIGTERM trả `wait=143`; unit stop inactive; cleanup PASS | Chỉ signal process đã xác minh và cleanup theo unit name exact; không dùng wildcard |

## Kubernetes (sau khi đạt gate)

Pending/FailedScheduling, CrashLoopBackOff, ImagePullBackOff, OOMKilled, Evicted, FailedMount, NodeNotReady, CoreDNS/service/Ingress errors, RBAC Forbidden, certificate expiry, containerd/CNI/etcd failure. Các case cần multi-node/GPU sẽ chuyển sang môi trường phù hợp thay vì mô phỏng sai trên một VPS.
