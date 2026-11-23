# DevOps Infrastructure Lab

Lab học DevOps có thể tái triển khai: hiểu Linux bằng CLI, thực hành có giới hạn, xác minh output thật, troubleshoot và ghi lại cleanup/rollback. Tài liệu viết bằng tiếng Việt, giữ nguyên technical terms và command tiếng Anh.

## Kiến trúc và tiến độ

- **Môi trường:** máy cá nhân Windows dùng OpenSSH; VPS Linux một node là môi trường thực hành, không phải production.
- **Luồng công nghệ:** Linux → Docker → containerd → kubeadm single-node → RKE2 có điều kiện → Rancher nếu resource gate cho phép.
- **Phạm vi học:** Linux Labs 01–06; Docker Labs 07–09; ASP.NET Core Lab 10; containerd Lab 11. Lab 07–11 có runbooks; Docker/host deployment chưa chạy cho tới khi security/resource gates đạt.
- **Tiến độ chuẩn:** [docs/progress.md](docs/progress.md) là single source of truth. Hạ tầng đã quan sát ở [docs/infrastructure.md](docs/infrastructure.md); budget và gate ở [docs/resource-budget.md](docs/resource-budget.md); kiến trúc ở [docs/architecture.md](docs/architecture.md).

## Quick start trên Windows

Yêu cầu: OpenSSH CLI trên máy cá nhân và alias `devops-lab` cấu hình sẵn bằng SSH key. Không đặt password/private key trong repo.

```powershell
ssh devops-lab
.\scripts\run-remote.ps1 -Phase phase-0
.\scripts\run-remote.ps1 -Phase lab-01
.\scripts\run-remote.ps1 -Phase lab-02
.\scripts\run-remote.ps1 -Phase lab-03
.\scripts\run-remote.ps1 -Phase lab-04
.\scripts\run-remote.ps1 -Phase lab-05
.\scripts\run-remote.ps1 -Phase lab-06
.\scripts\run-remote.ps1 -Phase host-change
```

`run-remote.ps1` chỉ upload các Bash scripts cần thiết vào remote `mktemp` directory, chạy `bash -n` riêng từng file, gọi phase validator rồi cleanup đúng temporary directory của lần chạy.

## Current lab và next lab

- **Linux Labs 01–06:** đã chạy và ghi runtime evidence trong [docs/progress.md](docs/progress.md). Networking/storage chỉ quan sát; Lab 03 dùng transient cgroup bounded workload; Lab 06 sample files được cleanup chính xác.
- **Docker Labs 07–09, API Lab 10, containerd Lab 11:** học liệu và runbooks đã chuẩn bị. Docker build/container smoke và API Linux integration PASS trên GitHub-hosted runner; Docker trên local engine và VPS runtime chưa được kiểm chứng. Xem [roadmap](docs/roadmap.md) và [progress](docs/progress.md).

## Validation commands

```bash
# Trong Bash trên Linux/CI: static repository gates
./scripts/validate.sh repo

# Trên VPS qua PowerShell; phase-0 và lab checks độc lập
.\scripts\run-remote.ps1 -Phase phase-0
.\scripts\run-remote.ps1 -Phase lab-02
.\scripts\run-remote.ps1 -Phase lab-03
.\scripts\run-remote.ps1 -Phase lab-04
.\scripts\run-remote.ps1 -Phase lab-05
.\scripts\run-remote.ps1 -Phase lab-06

# Docker installation gate; read-only, no package changes
.\scripts\run-remote.ps1 -Phase host-change

# Public-exposure gate; only for a service reachable from the Internet
./scripts/validate.sh public-services
```

Exit code của validator: `0` required gates đạt; `1` required gate thất bại; `2` thiếu required evidence. `preflight.sh` và `security-baseline.sh` là inventory scripts, không phải bằng chứng deployment/security gate PASS. Optional check có thể ở trạng thái `NOT TESTED` mà không chặn lab không liên quan. Gitleaks scan chạy trên reachable Git history đã fetch; CI log xác nhận số commits scanned và chỉ in kết quả đã redact. GitHub Actions chạy Docker integration trên GitHub-hosted runner, không dùng VPS làm runner. Gate cài host Docker (`host-change`) khác gate mở dịch vụ Internet (`public-services`); Compose localhost-only vẫn cần host-change và approval cài package, nhưng không bị phân loại là public service. Chưa cài Docker trên VPS.

## Resource constraints

VPS package 4 vCPU/4 GB RAM/40 GB SSD; snapshot quan sát được khoảng 3.8 GiB RAM, không swap. Ưu tiên Linux labs nhẹ. Không dùng swap để giả lập RAM Kubernetes, không tạo OOM/disk exhaustion. kubeadm chỉ cân nhắc single-node tối giản sau resource/preflight gates; RKE2 cần kiểm tra mức tối thiểu hiện hành; Rancher, monitoring stack đầy đủ, Harbor, GitLab Server, Longhorn, HA và multi-node được chuyển sang máy local nếu VPS thiếu headroom. Xem [resource budget](docs/resource-budget.md).

## Quy trình và an toàn

Đọc [AGENTS.md](AGENTS.md) và skill [vps-linux-lab](.agents/skills/vps-linux-lab/SKILL.md) trước khi làm. Với Docker/containerd, dùng skill riêng [container-runtime-lab](.agents/skills/container-runtime-lab/SKILL.md). Quy trình là Assess → Plan → Preflight → Deploy → Verify → Troubleshoot → Document; risk levels phân biệt diagnostics, lab tạm, system config và thao tác có thể làm mất SSH/dữ liệu. SSH hardening đã chuẩn bị riêng nhưng **chưa áp dụng**: [runbook SSH hardening](docs/runbooks/ssh-hardening.md). Docker install, SSH và firewall là các thay đổi riêng, cần preconditions và approval cụ thể.

Không commit credentials, kubeconfig, private SSH keys, raw inventory/logs, host addresses/identifiers hoặc backups. Xem [.gitignore](.gitignore) và workflow [validate.yml](.github/workflows/validate.yml).
