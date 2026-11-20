# Troubleshooting index

Chỉ ghi root cause sau khi có bằng chứng. Mỗi case cần đủ: Symptoms → Root Cause → Investigation → Resolution → Verification → Prevention.

## Linux / Phase 1

| Case | Thu thập ban đầu | Trạng thái |
|---|---|---|
| CPU high | `uptime`, `top`, `ps`, `vmstat`, `/proc/stat`, CPU cgroup counters | Lab 03 read-only sample PASS; không tạo CPU saturation ngoài quota nhỏ |
| Memory pressure / OOM | `free -h`, `vmstat`, `/proc/meminfo`, `memory.events`, kernel journal | Lab 03 đọc memory/cgroup PSI; OOM history NOT TESTED vì journal filter exit 1; không tạo OOM |
| Disk full / inode | `df -hT`, `df -ih`, `du` bounded | Lab 03 capacity/inode/du snapshot PASS; không xóa file |
| Disk I/O bottleneck | `/proc/diskstats`, `vmstat` | Lab 03 one-second sample PASS; không có read/write completion nên latency NOT TESTED |
| Service startup failure | `systemctl status`, `journalctl -u <unit>` | Lab 02 lifecycle PASS; chưa cố ý làm service fail |
| Process signal handling | `ps`, `kill -TERM`, Bash `wait` status | Lab 02 SIGTERM/wait=143 PASS |
| Port conflict | `ss -lntup` | Lab 04 listener/bind classes inspected; no port conflict deliberately created |
| SSH failure | provider console, client `ssh -vv`, server auth logs | Chưa thực hành; không sửa firewall từ SSH duy nhất |
| Permission denied | `namei -l`, `stat`, `getfacl` | Chưa thực hành |
| DNS/network timeout | `getent`, `dig`, `ip route`, `ss`, `curl -v` | Lab 04 bounded `getent` lookup PASS; public inbound/NAT paths remain NOT TESTED |
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
| Hosted CI báo ShellCheck findings và Windows mock job exit 1 dù bảy scenarios đã pass | Retry counter unused, duplicate forbidden-path glob, intended literal `$HOME` string unclear to ShellCheck; mock runner retained the expected non-zero child exit code after successful assertions | Run `44715339644` logged `SC2034`, `SC2016`, `SC2221`/`SC2222`; Windows log showed all cases PASS before process exit | Use a referenced arithmetic retry counter, escape the literal dollar, remove the duplicate pattern and clear `$LASTEXITCODE` after successful temp cleanup | Run `44715861942`: ShellCheck and Windows job both PASS; final run `44718620466` passed both jobs again | Keep Linux lint and Windows exit-code assertions in hosted CI; do not add SSH credentials or target the VPS from CI |
| Gitleaks history scan found `generic-api-key` in a historical runbook prose line | The detector matched ordinary prose, not a credential value | Run `44717138571` reported one finding, and its redacted metadata identified only the rule, source line, columns and eight-character match length; manually review the historical line | Add one exact fingerprint to `.gitleaksignore` with a rationale; no rule-wide or file-wide suppression; keep secret-bearing scanner output suppressed | Final run `44718620466`: Gitleaks v8.30.1 scanned 13/13 reachable commits, exit 0; GitHub Actions Linux and Windows jobs PASS | Verify the full-history count equals `git rev-list --all --count`; keep failure logs limited to non-secret location metadata |

## Lab 03 — runtime findings

| Symptoms | Root Cause | Investigation | Resolution | Verification | Prevention |
|---|---|---|---|---|---|
| Lab dừng trước diagnostics vì kiểm tra `cpu.max`/`memory.max` ở cgroup root | Host bật CPU/memory controllers nhưng root cgroup không expose per-cgroup limit files | Đọc `/sys/fs/cgroup/cgroup.controllers`, hierarchy và per-service files read-only | Gate đổi sang xác nhận controllers; limit files được kiểm tra trong transient systemd service cgroup | `cpu.max=20000 100000`, `memory.max=100663296`, `pids.max=4`; bounded run và cleanup PASS | Kiểm tra file ở đúng cgroup scope; không dùng thiếu root control file để suy luận controller unavailable |
| gawk tính CPU/resource gate báo lỗi | Tên biến `system` và `load` trùng built-in functions | Live run ghi syntax errors ngay ở `/proc/stat` delta và headroom awk | Đổi tên thành `sys_ticks` và `one_minute` | Live diagnostics tiếp tục; bounded exercise PASS | Chạy `bash -n` và ShellCheck; runtime-check awk trên target Linux |

## Kubernetes (sau khi đạt gate)

Pending/FailedScheduling, CrashLoopBackOff, ImagePullBackOff, OOMKilled, Evicted, FailedMount, NodeNotReady, CoreDNS/service/Ingress errors, RBAC Forbidden, certificate expiry, containerd/CNI/etcd failure. Các case cần multi-node/GPU sẽ chuyển sang môi trường phù hợp thay vì mô phỏng sai trên một VPS.
