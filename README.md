# DevOps Infrastructure Lab

Lab học DevOps có thể tái triển khai: hiểu Linux bằng CLI, thực hành có giới hạn, xác minh output thật, troubleshoot và ghi lại cleanup/rollback. Tài liệu viết bằng tiếng Việt, giữ nguyên technical terms và command tiếng Anh.

## Kiến trúc và tiến độ

- **Môi trường:** máy cá nhân Windows dùng OpenSSH; VPS Linux một node là môi trường thực hành, không phải production.
- **Luồng công nghệ:** Linux → Docker → containerd → kubeadm single-node → RKE2 có điều kiện → Rancher nếu resource gate cho phép.
- **Phạm vi hiện tại:** Linux Labs 01–06; public-service security gate riêng để không chặn Linux exercises an toàn.
- **Tiến độ chuẩn:** [docs/progress.md](docs/progress.md) là single source of truth. Hạ tầng đã quan sát ở [docs/infrastructure.md](docs/infrastructure.md); budget và gate ở [docs/resource-budget.md](docs/resource-budget.md); kiến trúc ở [docs/architecture.md](docs/architecture.md).

## Quick start trên Windows

Yêu cầu: OpenSSH CLI trên máy cá nhân và alias `devops-lab` cấu hình sẵn bằng SSH key. Không đặt password/private key trong repo.

```powershell
ssh devops-lab
.\scripts\run-remote.ps1 -Phase phase-0
.\scripts\run-remote.ps1 -Phase lab-01
.\scripts\run-remote.ps1 -Phase lab-02
```

`run-remote.ps1` chỉ upload các Bash scripts cần thiết vào remote `mktemp` directory, chạy `bash -n` riêng từng file, gọi phase validator rồi cleanup đúng temporary directory của lần chạy.

## Current lab và next lab

- **Current:** [Lab 02 — systemd, services, processes, signals và journalctl](labs/02-linux/README.md). Đây là bounded transient service exercise; xem runtime results và `docs/progress.md` trước khi coi là PASS.
- **Next:** Lab 03 — CPU, RAM, load average, memory pressure, disk I/O và cgroups; chỉ dùng quan sát và workload có giới hạn.
- Lab 04–06 lần lượt học networking, filesystem/storage concepts và Bash automation; không tạo placeholder skills hoặc workload khi chưa bắt đầu phần tương ứng.

## Validation commands

```bash
# Trong Bash trên Linux/CI: static repository gates
./scripts/validate.sh repo

# Trên VPS qua PowerShell; phase-0 và lab checks độc lập
.\scripts\run-remote.ps1 -Phase phase-0
.\scripts\run-remote.ps1 -Phase lab-02

# Public-service gate riêng; cần evidence đã làm sạch
./scripts/validate.sh public-services
```

Exit code của validator: `0` required gates đạt; `1` required gate thất bại; `2` thiếu required evidence. `preflight.sh` và `security-baseline.sh` là inventory scripts, không phải bằng chứng deployment/security gate PASS. Optional check có thể ở trạng thái `NOT TESTED` mà không chặn lab không liên quan. CI chạy trên GitHub-hosted runner; VPS không chạy self-hosted runner.

## Resource constraints

VPS package 4 vCPU/4 GB RAM/40 GB SSD; snapshot quan sát được khoảng 3.8 GiB RAM, không swap. Ưu tiên Linux labs nhẹ. Không dùng swap để giả lập RAM Kubernetes, không tạo OOM/disk exhaustion. kubeadm chỉ cân nhắc single-node tối giản sau resource/preflight gates; RKE2 cần kiểm tra mức tối thiểu hiện hành; Rancher, monitoring stack đầy đủ, Harbor, GitLab Server, Longhorn, HA và multi-node được chuyển sang máy local nếu VPS thiếu headroom. Xem [resource budget](docs/resource-budget.md).

## Quy trình và an toàn

Đọc [AGENTS.md](AGENTS.md) và skill [vps-linux-lab](.agents/skills/vps-linux-lab/SKILL.md) trước khi làm. Quy trình là Assess → Plan → Preflight → Deploy → Verify → Troubleshoot → Document; risk levels phân biệt diagnostics, lab tạm, system config và thao tác có thể làm mất SSH/dữ liệu. SSH hardening đã chuẩn bị riêng nhưng **chưa áp dụng**: [runbook SSH hardening](docs/runbooks/ssh-hardening.md). Provider firewall vẫn UNKNOWN đến khi được xác minh trong portal.

Không commit credentials, kubeconfig, private SSH keys, raw inventory/logs, host addresses/identifiers hoặc backups. Xem [.gitignore](.gitignore) và workflow [validate.yml](.github/workflows/validate.yml).
