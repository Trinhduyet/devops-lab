# Troubleshooting index

Chỉ ghi root cause sau khi có bằng chứng. Mỗi case cần đủ: Symptoms → Root Cause → Investigation → Resolution → Verification → Prevention.

## Linux / Phase 1

| Case | Thu thập ban đầu | Trạng thái |
|---|---|---|
| CPU high | `uptime`, `top`, `ps`, `pidstat` | Chưa thực hành |
| Memory pressure / OOM | `free -h`, `vmstat`, `dmesg -T`, cgroup counters | Chưa thực hành; không tạo áp lực trên production |
| Disk full / inode | `df -hT`, `df -ih`, `du -xhd1` | Chưa thực hành |
| Disk I/O bottleneck | `iostat -xz`, `iotop`, `vmstat` | Chưa thực hành |
| Service startup failure | `systemctl status`, `journalctl -u <unit>` | Chưa thực hành |
| Port conflict | `ss -lntup` | Chưa thực hành |
| SSH failure | provider console, client `ssh -vv`, server auth logs | Chưa thực hành; không sửa firewall từ SSH duy nhất |
| Permission denied | `namei -l`, `stat`, `getfacl` | Chưa thực hành |
| DNS/network timeout | `getent`, `dig`, `ip route`, `ss`, `curl -v` | Chưa thực hành |
| Certificate error | system time, chain, SNI, trust store, expiry | Chưa thực hành |

## Kubernetes (sau khi đạt gate)

Pending/FailedScheduling, CrashLoopBackOff, ImagePullBackOff, OOMKilled, Evicted, FailedMount, NodeNotReady, CoreDNS/service/Ingress errors, RBAC Forbidden, certificate expiry, containerd/CNI/etcd failure. Các case cần multi-node/GPU sẽ chuyển sang môi trường phù hợp thay vì mô phỏng sai trên một VPS.
