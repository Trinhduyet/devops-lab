# DevOps Infrastructure Lab

Repository học và thực hành DevOps trên VPS Linux, theo từng phase có kiểm tra điều kiện đầu vào. Nội dung giải thích bằng tiếng Việt, giữ nguyên technical terms tiếng Anh.

## Trạng thái hiện tại

- Phase 0.1 xác nhận SSH non-interactive bằng ED25519 key. `sshd` vẫn cho phép root login và password authentication; chưa đổi cấu hình.
- Host firewall chưa sẵn sàng cho dịch vụ public: `ufw status` inactive, IPv4/IPv6 INPUT policy ACCEPT. Provider firewall là UNKNOWN.
- Lab 01 Linux Fundamentals đã chạy qua SSH, gồm inventory read-only và phép thử permission trong thư mục tạm tự dọn.
- ACL exercise chưa chạy vì VPS không có `getfacl`/`setfacl`; không cài package trong phase này.
- Chưa cài hoặc đổi cấu hình dịch vụ, SSH, firewall hoặc network trên VPS.
- Chưa cài Docker, Kubernetes, RKE2 hay Rancher trên VPS.
- Chưa lưu hostname, địa chỉ IP, password, token, SSH key hay kubeconfig trong repository.

## Bắt đầu

1. Đọc [AGENTS.md](AGENTS.md) và [docs/progress.md](docs/progress.md).
2. Đọc [Lab 01 — Linux Fundamentals](labs/01-linux/README.md).
3. Đọc [runbook Phase 0](docs/runbooks/phase-0-preflight.md); kiểm tra Provider Firewall trong TopCloud Portal và chuẩn bị SSH recovery trước mọi thay đổi firewall.
4. Chỉ cài Docker sau khi hiểu UFW/iptables path và xác nhận console/rollback.
5. Xem [resource budget](docs/resource-budget.md) trước khi chọn lab Kubernetes.

## Quy tắc

- Mỗi phase: Assess → Plan → Preflight → Deploy → Verify → Troubleshoot → Document.
- Dùng read-only diagnostics trước. Không thay đổi SSH, firewall, disk, OS, network hoặc cluster khi chưa có backup, rollback plan và xác nhận rõ ràng.
- Không dùng Swap để bù cho thiếu RAM của Kubernetes.
- VPS một node là môi trường lab, không phải production HA.
- Không lưu credentials hoặc host-specific secrets trong Git.

## Cấu trúc

```text
.
├── AGENTS.md
├── .gitattributes
├── .agents/skills/vps-linux-lab/SKILL.md
├── docs/
│   ├── architecture.md
│   ├── infrastructure.md
│   ├── progress.md
│   ├── resource-budget.md
│   ├── roadmap.md
│   ├── troubleshooting.md
│   └── runbooks/phase-0-preflight.md
├── labs/01-linux/README.md
├── scripts/
│   ├── preflight.sh
│   ├── security-baseline.sh
│   └── lab01-readonly.sh
└── applications/dotnet-sample-api/README.md
```

Các thư mục lab còn lại sẽ được bổ sung cùng nội dung thực hành tương ứng, tránh tạo placeholder không có giá trị.
