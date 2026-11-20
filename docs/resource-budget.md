# Resource budget

## Nguyên tắc

Không dùng thông số gói VPS trên trang bán hàng thay cho dữ liệu runtime. Đo CPU, RAM khả dụng, disk/IO, swap và mức tải trước khi phân bổ. Không dùng Swap để đáp ứng yêu cầu RAM của Kubernetes.

## Ngưỡng tham khảo chính thức

| Công nghệ | Ngưỡng tài liệu hiện tại | Cách dùng cho lab |
|---|---|---|
| kubeadm control plane | Kubernetes yêu cầu tối thiểu 2 CPU và 2 GB RAM/máy; tài liệu lưu ý thấp hơn sẽ còn ít chỗ cho ứng dụng. | Đây là floor cài đặt, không phải khuyến nghị chạy nhiều workload. Dùng tối thiểu 2 CPU/2 GB làm gate ban đầu, rồi quyết định theo `MemAvailable`, disk và workload. |
| RKE2 | Tối thiểu 2 CPU/4 GB RAM; khuyến nghị ít nhất 4 CPU/8 GB; SSD được khuyến nghị do embedded etcd ghi disk. | Dưới mức này hoãn RKE2. Mức 4/8 vẫn là lab một node, không phải HA. |
| Rancher trên Docker | Tài liệu Rancher v2.14 nêu 1 vCPU/4 GB cho cỡ Small; Docker installation chỉ dành cho development/testing, không phải production. | Chỉ thử sau khi quyết định tạm dừng/xóa môi trường RKE2 theo runbook và backup đã xác minh. |
| Rancher trên upstream RKE2 | Profile Small của tài liệu nêu 4 vCPU/16 GB mỗi node; production yêu cầu ít nhất 3 node HA. | Không gộp Rancher và RKE2 vào VPS nhỏ. Ưu tiên deferred lab trên máy local đủ tài nguyên. |

Nguồn: [Kubernetes kubeadm requirements](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/), [RKE2 requirements](https://docs.rke2.io/install/requirements), [Rancher v2.14 requirements](https://ranchermanager.docs.rancher.com/v2.14/getting-started/installation-and-upgrade/installation-requirements/).

Ubuntu 24.04 xuất hiện trong [Rancher Manager v2.14.3 support matrix](https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-14-3/) cho các cấu hình RKE2 được liệt kê. Đây là xác nhận OS ở mức matrix; phiên bản Kubernetes/RKE2 cụ thể vẫn phải được pin theo compatibility matrix tại ngày triển khai.

## Tạm phân loại sau khi có output

- **Dưới 2 vCPU hoặc 2 GB RAM:** Linux, network, filesystem, shell và Docker basics; hoãn Kubernetes.
- **Ít nhất 2 vCPU/2 GB:** chỉ cân nhắc kubeadm single-node theo tài liệu; giới hạn workload và theo dõi memory pressure.
- **Ít nhất 2 vCPU/4 GB:** RKE2 ở mức tối thiểu nếu OS/network/disk phù hợp; lab nhẹ, không thêm Rancher/monitoring stack.
- **Ít nhất 4 vCPU/8 GB và SSD:** phù hợp hơn cho RKE2 lab single-node với workload nhỏ; vẫn không phải HA.
- **Rancher:** quyết định riêng theo profile, không cài chồng lên RKE2 khi chưa chứng minh đủ RAM/disk. Với một VPS nhỏ, chuyển Rancher sang tháng 2.

Các ngưỡng này là planning gates. Chốt budget sau khi xem preflight và compatibility matrix tại thời điểm cài.

## Kết quả cho VPS hiện tại

Preflight ngày 2026-11-20 qua SSH và Lab 03 ghi nhận 4 guest-visible vCPU, `MemTotal=4,009,132 kB` (3.8 GiB), `MemAvailable` khoảng 3.5 triệu kB (3.3 GiB), không swap, root ext4 khoảng 37.7 GiB với 35.4 GiB còn trống, KVM và cgroup v2. Đây là snapshot thời điểm chạy, không phải capacity guarantee của physical host.

- **Linux và networking:** có thể tiếp tục ngay với diagnostics và bài học không thay đổi cấu hình.
- **Docker/ASP.NET Core:** chỉ cân nhắc API lab nhỏ sau khi host/provider ingress, SSH recovery path và Docker firewall behavior được review. Docker tạo firewall/NAT rules; port publishing có thể đi theo đường khác với UFW. API lab đầu tiên nên bind localhost và truy cập bằng SSH tunnel.
- **kubeadm:** CPU đạt; RAM cao hơn mức tối thiểu nhưng chỉ 4 GiB tổng. Chỉ cân nhắc một cluster single-node tối giản sau khi Phase 1 đạt gate; không chạy observability stack hay nhiều workloads.
- **RKE2:** 4 GiB đạt floor tài liệu nhưng thấp hơn khuyến nghị 8 GiB. Chưa khuyến nghị cài trên VPS này cùng API workload và OS.
- **Rancher:** deferred sang máy local có thêm RAM. Rancher trên upstream Kubernetes không phù hợp với VPS 4 GiB; Docker-based Rancher 4 GiB là sizing development/testing và gần như không có headroom cho host.
- **Harbor, GitLab server, Longhorn, Prometheus/Grafana/Loki, HA, multi-node, GPU:** deferred.

Thứ tự thực hành giữ riêng kubeadm và RKE2; trước khi chuyển runtime phải backup, xác minh backup và cleanup theo runbook. Các con số RAM là snapshot tại một thời điểm, không thay thế việc theo dõi usage khi chạy workload.

## Gate bảo mật và kernel còn mở

- Không cài Docker hoặc expose API cho tới khi host/provider ingress firewall và management recovery path được kiểm soát.
- Không bật firewall hoặc thay đổi SSH/network trước khi ingress path, verified provider console/out-of-band access, backup, rollback timer và SSH session thứ hai đã được kiểm chứng. Đây là các thay đổi có thể ngắt kết nối và cần xác nhận rõ ràng.
- `ip_forward=0`, bridge sysctl thiếu và overlay/br_netfilter chưa thấy được nạp. Trước khi cài Docker, xác nhận `modinfo overlay`/`modinfo br_netfilter`, rồi chọn thay đổi đúng cho Docker; kubeadm/RKE2 sẽ có preflight riêng.
- Docker Engine tự quản lý firewall cho bridge network; tài liệu Docker cảnh báo port publish có thể bypass UFW. Không dùng UFW làm lớp kiểm soát duy nhất cho public container ports; lab đầu bind `127.0.0.1`, public exposure cần thiết kế riêng theo Docker `DOCKER-USER`/backend tương ứng.

## Budget cho Linux labs

- Lab 02 chỉ chạy một transient `sleep` service tối đa 40 giây và một child process bị kết thúc ngay bằng SIGTERM; không stress CPU/RAM/disk. Journal marker nhỏ là evidence có chủ đích.
- Lab 03 final read-only sample cho load `0.00/0.00/0.00`, CPU khoảng `0.0% user / 0.2% system / 99.8% idle`, `0.0% iowait/steal`, không swap, root fs `6%`, inode `3%`; PSI avg10/60/300 đều zero trong snapshot. Một giây không có disk operations nên I/O latency là `NOT TESTED`.
- Lab 03 transient workload đã chạy với `CPUQuota=20%` (`cpu.max=20000 100000`), `MemoryMax=96M` (`memory.max=100663296`), `TasksMax=4` (`pids.max=4`) và `RuntimeMaxSec=10s`; cấp phát/touch 24 MiB, peak RSS `35072 KiB`, cgroup current `29396992` bytes, throttle count `25`. Memory dùng nhỏ hơn hard cap; không thử chạm giới hạn hoặc kích hoạt OOM. Unit, process, cgroup và remote upload temp đều cleanup PASS.
- Cgroup root liệt kê CPU/memory controllers nhưng không expose `cpu.max`/`memory.max` cho root hierarchy. Bounded service cgroup có đủ control files và là nơi đọc effective quota/usage; không dùng thiếu root control file để kết luận controller không khả dụng.
- Host firewall/provider SSH security là gate riêng cho public services. Nó không chặn Phase 1 Linux exercises mà không mở port hay sửa host configuration.
