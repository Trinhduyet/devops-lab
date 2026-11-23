# Tiến độ — nguồn trạng thái chuẩn

Cập nhật lần cuối: 2026-11-23. Các số liệu là snapshot theo lần quan sát; không đại diện production readiness. Host-specific security details và provider evidence ở local-only evidence, không publish.

| Phase/gate | Trạng thái | Bằng chứng thực tế |
|---|---|---|
| Repository harness | Previous hosted CI PASS; current changes pending validation | Last hosted run [44718620466](https://github.com/Trinhduyet/devops-lab/actions/runs/44718620466) passed Linux and Windows jobs, including ShellCheck 0.9.0. Current changes add Labs 07–11, container skill and API files to the non-empty `required_file` gate; PowerShell parser also includes the API smoke script. ShellCheck is not installed locally. |
| Gitleaks full history | Previous PASS — 13/13 commits; current tree pending CI | Workflow pins Gitleaks v8.30.1 and verifies release SHA-256; checkout fetches full history; `--all --full-history --diff-merges=first-parent` completed with 13 scanned/reachable commits in [44718620466](https://github.com/Trinhduyet/devops-lab/actions/runs/44718620466). Secret values are redacted. Current additions need a new hosted scan to prove the updated full-history count. Earlier run `44704136448` scanned only 1 commit and is not history proof. |
| Phase 0 — infrastructure inventory | PASS (inventory collection) | Re-run trực tiếp qua Windows OpenSSH helper ngày 2026-11-20; `preflight.sh` và `security-baseline.sh` trả `INVENTORY STATUS=COLLECTED`, remote `bash -n` PASS và upload-temp cleanup PASS. Inventory không phải security/deployment gate. |
| Phase 0 — optional kernel evidence | NOT TESTED | `net.bridge.bridge-nf-call-iptables` không được kernel expose (`/proc/sys/net/bridge/...` vắng mặt); diagnostic được ghi rõ, không coi output rỗng là PASS. Kernel module/network config không đổi. |
| Phase 0.1 — SSH authentication | INVENTORY COLLECTED; hardening deferred | Live `sshd -t` and `sshd -T -C` were checked using the actual client/server connection context; Include ordering and Match directives were inspected. Current policy/source values are kept local-only. Hardening chưa apply. |
| Phase 0.1 — firewall/public ingress | GATE NOT CLEARED | User supplied provider firewall and rescue-console evidence on 2026-11-23; evidence is stored locally and excluded from Git. The public-service gate remains uncleared. No SSH/firewall/network change; host-specific status stays local-only. |
| Lab 01 — Linux Fundamentals | PASS; ACL NOT TESTED | Re-run bằng validator qua VPS: `umask 077` → mode `600`; `chmod 640` → mode `640`; file/directory tạm cleanup PASS. ACL tools absent; không cài package. |
| Lab 02 — systemd/services/processes/signals/journalctl | PASS | systemd 255, manager running, 0 failed units, journal 8.0 MB, process count snapshot 143. Transient unit active/inactive; marker journal observed; `MemoryCurrent=266240` bytes, `CPUUsageNSec=9058000`; SIGTERM `wait=143`; service/process/helper cleanup PASS. Chi tiết tại [Lab 02](../labs/02-linux/README.md). |
| Lab 03 — CPU/RAM/I/O/cgroups | PASS | VPS rerun 2026-11-20 after ShellCheck fix: 4 vCPU, load `0.07/0.02/0.00`, one-second CPU sample `0.0% user / 0.0% system / 100% idle / 0.0% iowait / 0.0% steal`; `MemAvailable=3,497,480 kB`, no swap; root fs `6%`, inode `3%`; no disk I/O completed, latency NOT TESTED. PSI CPU/memory/I/O averages 0 at sample. Bounded unit: `cpu.max=20000 100000`, `memory.max=100663296` bytes, `pids.max=4`, post-allocation `memory.current=29577216` bytes, process RSS `35256 KiB`, `nr_throttled=23`; service inactive, process absent, cgroup and upload temp removed. No OOM or storage stress. |
| Lab 04 — Networking | PASS (read-only) | 2026-11-20: IPv4/IPv6 route and interface summaries, bounded system resolver lookup (4 unique results), resolver service, socket summary and local listeners inspected. Host-specific route, listener and firewall details are kept local-only. No network/firewall change; upload temp cleanup PASS. |
| Lab 05 — Storage | PASS (read-only) | 2026-11-20: virtual disk reports 40 GB and ROTA=0; root ext4 6% blocks/3% inodes; bounded `du` of `/var/log`, `/var/cache`, `/tmp`; one-second sample had 0 reads/1 write, latency NOT TESTED (<10 ops). LVM tools exist but volume query was NOT TESTED. No disk/filesystem mutation. Upload temp cleanup PASS. |
| Lab 06 — Bash Automation | PASS | VPS rerun 2026-11-20 after ShellCheck fix: private `/tmp` directory mode 700; fixed file mode 600; atomic repeat-write hashes matched; `*` and literal `$HOME` preserved; child exit 7 handled; exact files/directory and remote upload temp cleanup PASS. |
| Lab 07 — Docker Engine | BLOCKED / NOT TESTED | Ubuntu compatibility and official Docker documentation reviewed. Live public-service gate still fails; no package install, daemon, sysctl, firewall or network changes. |
| Lab 08 — Docker networking | BLOCKED / NOT TESTED | No container networks/listeners created. Public ports remain out of scope; future app binding is loopback-only. |
| Lab 09 — Docker storage | BLOCKED / NOT TESTED | No images, volumes or container storage objects created; no prune/disk changes. |
| Lab 10 — ASP.NET Core API | Source/local PASS; container/VPS NOT TESTED | .NET 10 Release source build succeeded with zero warnings/errors; local HTTP smoke verified `/`, `/health/live`, `/health/ready`, and exact test process cleanup. Windows graceful SIGTERM NOT TESTED; Compose YAML parsed; Docker daemon unavailable, so image/container and VPS deploy remain untested. CI Linux smoke pending. |
| Lab 11 — containerd | NOT STARTED | Docker/containerd package absent at last read-only inventory; no standalone package installed. |
| kubeadm | NOT STARTED | Main Kubernetes lab là single-node; chờ Phase 1, compatibility, resource và backup gate. |
| RKE2 | DEFERRED DECISION | Chỉ sau kubeadm backup/cleanup và kiểm tra minimum requirements hiện hành. |
| Rancher/large stacks | DEFERRED | Chuyển sang máy local nếu VPS 4 GB không đủ headroom; không mua thêm dịch vụ. |

## Quy tắc đọc evidence

- Local `bash -n`, documentation gate hoặc GitHub CI không thay thế runtime proof trên VPS. Final hosted CI run [44718620466](https://github.com/Trinhduyet/devops-lab/actions/runs/44718620466) passed Linux and Windows jobs; Gitleaks logged 13/13 reachable commits.
- VPS runtime PASS chỉ áp dụng cho lệnh/lab đã quan sát ở thời điểm trên; không đồng nghĩa provider ingress, public reachability hay production readiness.
- SSH key-only client proof and live SSH/firewall inventories are separate checks; provider/rescue evidence is manual, not live host proof. Detailed posture and evidence are kept local-only. No SSH/firewall/network/disk configuration changes were made.
- `docs/infrastructure.md` contains a sanitized runtime summary; `docs/resource-budget.md` is the source for resource gates; README links to these canonical documents.

## Lỗi gặp và xử lý

- Remote bash từ chối một dòng CRLF sau khi local Git Bash chấp nhận syntax. Đã chuẩn hóa LF và yêu cầu helper kiểm tra `bash -n` trên đúng Linux target trước khi chạy.
- `scp` không giữ executable bit trên remote upload. Helper đặt mode 0700 trong unique temp directory; không thay đổi mode trên host.
- Lần signal đầu gửi trước khi child hoàn thành `exec`, và transient unit tự unload sau stop. Lab giờ chờ xác minh `/proc/<pid>/comm`; cleanup kiểm tra LoadState và lần chạy lại đã PASS.
- Phase 0 ban đầu đánh lỗi khi bridge netfilter sysctl không tồn tại. Preflight nay phân loại đúng là optional `NOT TESTED`, vẫn in diagnostic/exit status; lần rerun inventory PASS.
