# Hướng dẫn làm việc trong DevOps Infrastructure Lab

## Mục tiêu

Xây dựng lab tái tạo được, ưu tiên hiểu nguyên lý, quan sát bằng CLI, troubleshoot, backup và rollback. Viết tài liệu tiếng Việt; giữ nguyên technical terms, command và API names bằng tiếng Anh.

## Quy trình bắt buộc

1. **Assess:** phân biệt dữ liệu đã xác minh với dữ liệu người dùng cung cấp hoặc còn thiếu.
2. **Plan:** xác định tác động, resource budget, dependencies và rollback.
3. **Preflight:** chạy kiểm tra chỉ đọc và lưu kết quả đã làm sạch.
4. **Deploy:** thay đổi phạm vi nhỏ nhất, ghim phiên bản và giải thích lệnh quan trọng.
5. **Verify:** cung cấp lệnh kiểm tra cùng expected output; chỉ ghi PASS khi có output thực tế.
6. **Troubleshoot:** nêu symptom, root cause, investigation, resolution, verification và prevention.
7. **Document:** cập nhật runbook/progress trước khi sang phase sau.

## An toàn

- Không đưa password, token, SSH private key, kubeconfig, Terraform state hay dữ liệu nhận dạng máy chủ vào Git.
- Không dùng lại credentials được dán trong hội thoại hoặc ảnh; nếu credential đã lộ, khuyến nghị thu hồi/đổi credential.
- Không chạy lệnh phá hủy hoặc có thể làm mất SSH/network (OS reinstall, cluster reset, format, xóa volume, đổi SSH/firewall, restore etcd) nếu chưa giải thích ảnh hưởng, kiểm tra backup, có rollback và được người dùng xác nhận.
- Không tắt firewall, SELinux hoặc AppArmor để né lỗi cài đặt.
- Không expose Kubernetes API, etcd hoặc kubelet ra Internet không cần thiết.
- Không dùng Swap để thay cho RAM của Kubernetes.
- Không triển khai Rancher đồng thời với RKE2 trên cùng VPS khi resource budget chưa chứng minh đủ.
- Mặc định chọn diagnostics read-only. Khi thiếu quyền/kết nối, cung cấp lệnh để người dùng chạy và không giả định kết quả.

## Tiêu chuẩn kỹ thuật

- Kiểm tra OS/Kubernetes/RKE2/Rancher compatibility matrix và tài liệu chính thức ngay trước khi ghim phiên bản.
- Ưu tiên script idempotent, Bash an toàn (`set -euo pipefail` khi phù hợp), log rõ nhưng không chứa secrets.
- Manifests phải dùng least privilege, resource requests/limits phù hợp và probes khi áp dụng được.
- Mỗi bài lab có mục tiêu, lý thuyết, kiến trúc, điều kiện, triển khai, expected output, verification, metrics, lỗi thường gặp, security, backup/rollback, cleanup, câu hỏi và checklist.
- Tách kết quả local, lab, VPS runtime và production readiness. Không coi build/test/local success là production proof.

## Git

- Kiểm tra `.gitignore` trước khi thêm artifacts.
- Không commit output preflight có public/private IP hoặc hostname nếu repository public.
- Trước khi publish, rà soát toàn bộ tree để tìm secrets và thông tin hạ tầng riêng.
