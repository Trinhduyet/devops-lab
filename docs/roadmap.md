# Roadmap 30 ngày

Mỗi ngày có thể kéo dài nếu gate kiểm tra chưa đạt. Không chuyển sang Kubernetes vì lịch; chuyển khi Linux, networking và container runtime đã được kiểm chứng.

| Ngày | Chủ đề | Kết quả/điều kiện |
|---|---|---|
| 1 | VPS assessment, OS, CPU, RAM, disk, kernel | Preflight baseline và resource budget |
| 2 | Users/groups, SSH, sudo, permissions, ACL | Thực hành không khóa quyền truy cập |
| 3 | Filesystem, inode, mounts, storage concepts | Đo disk; LVM/RAID/NFS/iSCSI là mô phỏng hoặc deferred nếu VPS không phù hợp |
| 4 | IPv4/IPv6, CIDR, DNS, routes, NAT | Vẽ đường SSH và luồng outbound |
| 5 | systemd, journal, processes, signals, CPU/RAM/OOM | Chẩn đoán lỗi có kiểm soát trong user space |
| 6 | Docker image/container, Dockerfile, Compose, volumes/network | Chạy ASP.NET Core API không public tùy tiện |
| 7 | OCI, namespaces, cgroups, containerd/CRI | Phase 1 verification gate; dọn workload thử nghiệm |
| 8 | kubeadm architecture, prerequisites, packages | Chỉ cài sau OS/resource/network gate |
| 9 | kubeadm single-node bootstrap | Control plane Ready, ghi phiên bản và snapshot/backup plan |
| 10 | API, scheduler, controller, kubelet, etcd | Quan sát reconciliation và events |
| 11 | Pod, ReplicaSet, Deployment, rollout/rollback | Workload và self-healing |
| 12 | Service, EndpointSlice, CoreDNS, CNI, Ingress | Kiểm tra luồng network; Ingress controller chọn theo compatibility/EOL |
| 13 | ConfigMap, Secret, probes, volumes, PVC | Dữ liệu thử nghiệm và storage boundaries |
| 14 | RBAC, ServiceAccount, securityContext, PSS, NetworkPolicy | Least privilege và policy verification |
| 15 | Requests/limits, QoS, quota, taints/affinity, HPA | Resource behavior; VPA/GPU/multi-node nếu thiếu node thì deferred |
| 16 | Helm, Kustomize, chart pinning | Install/upgrade/rollback app test |
| 17 | Pending, CrashLoop, ImagePull, DNS, mount, RBAC labs | Troubleshooting runbook + etcd backup verification |
| 18 | kubeadm phase review, backup/restore plan, cleanup prep | Gate: evidence/backup check trước khi rời phase |
| 19 | RKE2 architecture, compatibility, config, registries | Chỉ sau khi kubeadm cleanup/backup hoàn tất |
| 20 | RKE2 single-node install | Service/containerd/CNI checks |
| 21 | kubectl, manifests, auto-deploy, networking | RKE2 workload and service checks |
| 22 | Registry mirrors, certificates, security | Private registry nếu tài nguyên và network cho phép |
| 23 | Etcd snapshots, restore procedure | Tạo và kiểm chứng snapshot; restore trên lab disposable |
| 24 | Upgrade/rollback, troubleshooting, cleanup | RKE2 phase verification gate |
| 25 | Rancher architecture, compatibility, resource assessment | Quyết định triển khai hoặc deferred; không cài mù |
| 26 | Rancher UI/RBAC/projects/workloads | Chỉ khi management cluster/tài nguyên sẵn sàng |
| 27 | Multi-cluster/Fleet/backup/restore | Nếu VPS không đáp ứng, chuyển tháng 2 |
| 28 | Bash/Ansible automation, idempotency | Automate read-only checks và config có thể lặp |
| 29 | Security/troubleshooting/backup review | Khắc phục findings và kiểm thử restore |
| 30 | Tài liệu, Git cleanup, local multi-node plan | README, deferred labs và resource map cho PC cá nhân |

## Deferred Labs mặc định

Multi-node HA, GPU Operator, Longhorn trên nhiều disk/node, Harbor, GitLab Server, full Prometheus/Grafana/Loki, Fleet/GitOps production, air-gap, iSCSI/RAID thực tế. Chuyển sang tháng 2 khi biết cấu hình máy cá nhân; không giả định sẵn đủ RAM.
