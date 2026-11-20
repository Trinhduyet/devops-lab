# Tiến độ — nguồn trạng thái chuẩn

Cập nhật lần cuối: 2026-11-20. Các số liệu là snapshot theo lần quan sát; không đại diện production readiness.

| Phase/gate | Trạng thái | Bằng chứng thực tế |
|---|---|---|
| Repository harness | LOCAL PASS; CI PENDING | `scripts/validate.sh repo` PASS sau targeted fixes; required files phải non-empty, tracked forbidden-path violation không in PASS; `.gitignore` samples và nested rules khớp. PowerShell parser và 7 SSH/SCP/remote-exit/cleanup mock scenarios PASS. Evidence mock scenarios PASS cho fresh manual, duplicate, malformed, stale, wrong provenance và live-state override. ShellCheck local NOT TESTED; workflow run mới đang chờ sau push. |
| Gitleaks full history | PENDING CI | Workflow đã pin Gitleaks v8.30.1, verify official release SHA-256, fetch full history, scan `--all --full-history --diff-merges=first-parent`, redact output, yêu cầu scanned commit count khớp `git rev-list --all --count`. Chưa có log CI mới chứng minh số lượng; run `44704136448` chỉ ghi `--log-opts=-1` / 1 commit và không được coi là history proof. |
| Phase 0 — infrastructure inventory | PASS (inventory collection) | Re-run trực tiếp qua Windows OpenSSH helper ngày 2026-11-20; `preflight.sh` và `security-baseline.sh` trả `INVENTORY STATUS=COLLECTED`, remote `bash -n` PASS và upload-temp cleanup PASS. Inventory không phải security/deployment gate. |
| Phase 0 — optional kernel evidence | NOT TESTED | `net.bridge.bridge-nf-call-iptables` không được kernel expose (`/proc/sys/net/bridge/...` vắng mặt); diagnostic được ghi rõ, không coi output rỗng là PASS. Kernel module/network config không đổi. |
| Phase 0.1 — SSH authentication | INVENTORY COLLECTED; hardening deferred | Live `sshd -t` and `sshd -T -C` were checked using the actual client/server connection context; Include ordering and Match directives were inspected. Current policy/source values are kept local-only. Hardening chưa apply. |
| Phase 0.1 — firewall/public ingress | GATE NOT CLEARED | No firewall/network change. Provider ingress and verified out-of-band recovery must be reviewed with fresh evidence before any public service or firewall change. Detailed host posture is kept local-only. |
| Lab 01 — Linux Fundamentals | PASS; ACL NOT TESTED | Re-run bằng validator qua VPS: `umask 077` → mode `600`; `chmod 640` → mode `640`; file/directory tạm cleanup PASS. ACL tools absent; không cài package. |
| Lab 02 — systemd/services/processes/signals/journalctl | PASS | systemd 255, manager running, 0 failed units, journal 8.0 MB, process count snapshot 143. Transient unit active/inactive; marker journal observed; `MemoryCurrent=266240` bytes, `CPUUsageNSec=9058000`; SIGTERM `wait=143`; service/process/helper cleanup PASS. Chi tiết tại [Lab 02](../labs/02-linux/README.md). |
| Lab 03 — CPU/RAM/I/O/cgroups | PASS | Final VPS run 2026-11-20 09:41 UTC: 4 vCPU, load 0.00/0.00/0.00, sampled CPU `0.0% user / 0.2% system / 99.8% idle / 0.0% iowait / 0.0% steal`; MemAvailable `3,495,916 kB`, no swap; root fs `6%`, inode `3%`; one-second disk sample idle, I/O latency NOT TESTED. PSI CPU/memory/I/O averages 0 at this snapshot. Bounded unit: `cpu.max=20000 100000`, `memory.max=100663296` bytes, `pids.max=4`, post-allocation `memory.current=29396992` bytes, process peak RSS `35072 KiB`, `nr_throttled=25`; stopped/inactive, process absent, cgroup removed, upload temp removed. No OOM or storage stress. |
| Lab 04 — Networking | PASS (read-only) | 2026-11-20: IPv4/IPv6 route and interface summaries, bounded system resolver lookup (4 unique results), resolver service, socket summary and local listeners inspected. Host-specific route, listener and firewall details are kept local-only. No network/firewall change; upload temp cleanup PASS. |
| Lab 05 — Storage | PASS (read-only) | 2026-11-20: virtual disk reports 40 GB and ROTA=0; root ext4 6% blocks/3% inodes; bounded `du` of `/var/log`, `/var/cache`, `/tmp`; one-second sample had 0 reads/1 write, latency NOT TESTED (<10 ops). LVM tools exist but volume query was NOT TESTED. No disk/filesystem mutation. Upload temp cleanup PASS. |
| Lab 06 — Bash Automation | PASS | 2026-11-20: private `/tmp` directory mode 700; fixed file mode 600; atomic repeat-write hashes matched; shell metacharacter argument preserved literally; child exit 7 handled; exact files/directory and remote upload temp cleanup PASS. |
| Docker/containerd | DEFERRED | Chờ Phase 1 và host/provider ingress/resource gates; không package install. |
| kubeadm | NOT STARTED | Main Kubernetes lab là single-node; chờ Phase 1, compatibility, resource và backup gate. |
| RKE2 | DEFERRED DECISION | Chỉ sau kubeadm backup/cleanup và kiểm tra minimum requirements hiện hành. |
| Rancher/large stacks | DEFERRED | Chuyển sang máy local nếu VPS 4 GB không đủ headroom; không mua thêm dịch vụ. |

## Quy tắc đọc evidence

- Local `bash -n`, documentation gate hoặc GitHub CI không thay thế runtime proof trên VPS.
- VPS runtime PASS chỉ áp dụng cho lệnh/lab đã quan sát ở thời điểm trên; không đồng nghĩa provider ingress, public reachability hay production readiness.
- SSH key-only client proof and live SSH/firewall inventories are separate checks; detailed host posture is kept local-only. No SSH/firewall/network/disk configuration changes were made.
- `docs/infrastructure.md` contains a sanitized runtime summary; `docs/resource-budget.md` is the source for resource gates; README links to these canonical documents.

## Lỗi gặp và xử lý

- Remote bash từ chối một dòng CRLF sau khi local Git Bash chấp nhận syntax. Đã chuẩn hóa LF và yêu cầu helper kiểm tra `bash -n` trên đúng Linux target trước khi chạy.
- `scp` không giữ executable bit trên remote upload. Helper đặt mode 0700 trong unique temp directory; không thay đổi mode trên host.
- Lần signal đầu gửi trước khi child hoàn thành `exec`, và transient unit tự unload sau stop. Lab giờ chờ xác minh `/proc/<pid>/comm`; cleanup kiểm tra LoadState và lần chạy lại đã PASS.
- Phase 0 ban đầu đánh lỗi khi bridge netfilter sysctl không tồn tại. Preflight nay phân loại đúng là optional `NOT TESTED`, vẫn in diagnostic/exit status; lần rerun inventory PASS.
