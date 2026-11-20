# Tiến độ — nguồn trạng thái chuẩn

Cập nhật lần cuối: 2026-11-20. Các số liệu là snapshot theo lần quan sát; không đại diện production readiness.

| Phase/gate | Trạng thái | Bằng chứng thực tế |
|---|---|---|
| Repository harness | PASS | `scripts/validate.sh repo` PASS tại Windows Git Bash. GitHub Actions run `44703911448` trên commit `de2c1e1` PASS: docs/Bash/path gates, pinned ShellCheck install, ShellCheck và Gitleaks history scan. Run đầu `44703366474` bắt được `SC2034` và `SC2221/SC2222`; đã sửa và workflow sau đó xanh. ShellCheck không cài trên Windows local. |
| Phase 0 — infrastructure inventory | PASS (inventory collection) | Chạy lại qua Windows OpenSSH helper; `preflight.sh` và `security-baseline.sh` trả `INVENTORY STATUS=COLLECTED`; từng script `bash -n` PASS. Inventory không phải security/deployment gate. |
| Phase 0 — optional kernel evidence | NOT TESTED | `net.bridge.bridge-nf-call-iptables` không được kernel expose (`/proc/sys/net/bridge/...` vắng mặt); diagnostic được ghi rõ, không coi output rỗng là PASS. Kernel module/network config không đổi. |
| Phase 0.1 — SSH authentication | WARNING; hardening deferred | `sshd -t` PASS; live `sshd -T -C` vẫn `pubkeyauthentication yes`, `passwordauthentication yes`, `permitrootlogin yes`, `kbdinteractiveauthentication no`. Config `Include`/drop-ins đã được xem; hardening runbook riêng, chưa apply. |
| Phase 0.1 — firewall/public ingress | NOT READY / UNKNOWN | `ufw` inactive, IPv4/IPv6 INPUT ACCEPT theo snapshot; Provider firewall và rescue console chưa được xác minh trong portal. Không đổi firewall/network. |
| Lab 01 — Linux Fundamentals | PASS; ACL NOT TESTED | Re-run bằng validator qua VPS: `umask 077` → mode `600`; `chmod 640` → mode `640`; file/directory tạm cleanup PASS. ACL tools absent; không cài package. |
| Lab 02 — systemd/services/processes/signals/journalctl | PASS | systemd 255, manager running, 0 failed units, journal 8.0 MB, process count snapshot 143. Transient unit active/inactive; marker journal observed; `MemoryCurrent=266240` bytes, `CPUUsageNSec=9058000`; SIGTERM `wait=143`; service/process/helper cleanup PASS. Chi tiết tại [Lab 02](../labs/02-linux/README.md). |
| Lab 03 — CPU/RAM/I/O/cgroups | NEXT | Chưa chạy; bắt đầu read-only rồi chọn workload bounded theo budget. |
| Lab 04–06 — networking/filesystem/Bash | DEFERRED | Theo thứ tự Linux roadmap; không đổi firewall hoặc mount tùy tiện. |
| Docker/containerd | DEFERRED | Chờ Phase 1 và host/provider ingress/resource gates; không package install. |
| kubeadm | NOT STARTED | Main Kubernetes lab là single-node; chờ Phase 1, compatibility, resource và backup gate. |
| RKE2 | DEFERRED DECISION | Chỉ sau kubeadm backup/cleanup và kiểm tra minimum requirements hiện hành. |
| Rancher/large stacks | DEFERRED | Chuyển sang máy local nếu VPS 4 GB không đủ headroom; không mua thêm dịch vụ. |

## Quy tắc đọc evidence

- Local `bash -n`, documentation gate hoặc GitHub CI không thay thế runtime proof trên VPS.
- VPS runtime PASS chỉ áp dụng cho lệnh/lab đã quan sát ở thời điểm trên; không đồng nghĩa provider ingress, public reachability hay production readiness.
- SSH key-only ở client đã PASS; server vẫn cho phép password/root login. Không thực hiện SSH/firewall/network changes trong lần cập nhật này.
- `docs/infrastructure.md` giữ snapshot hạ tầng đã làm sạch; `docs/resource-budget.md` là nguồn budget/gates; README chỉ dẫn tới các nguồn chuẩn này.

## Lỗi gặp và xử lý

- Remote bash từ chối một dòng CRLF sau khi local Git Bash chấp nhận syntax. Đã chuẩn hóa LF và yêu cầu helper kiểm tra `bash -n` trên đúng Linux target trước khi chạy.
- `scp` không giữ executable bit trên remote upload. Helper đặt mode 0700 trong unique temp directory; không thay đổi mode trên host.
- Lần signal đầu gửi trước khi child hoàn thành `exec`, và transient unit tự unload sau stop. Lab giờ chờ xác minh `/proc/<pid>/comm`; cleanup kiểm tra LoadState và lần chạy lại đã PASS.
- Phase 0 ban đầu đánh lỗi khi bridge netfilter sysctl không tồn tại. Preflight nay phân loại đúng là optional `NOT TESTED`, vẫn in diagnostic/exit status; lần rerun inventory PASS.
