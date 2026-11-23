# Lab 11 — containerd và OCI runtime

## Mục tiêu và trạng thái

Phân biệt Docker Engine, containerd, CRI, OCI image và `runc`; đọc containerd namespaces, plugins và snapshots. Lab này chưa chạy. Docker Engine cũng chưa được cài trên VPS; không cài package standalone containerd song song hoặc cấu hình kubelet trong lab này.

## Lý thuyết

- `dockerd` là Docker management API/control plane; containerd quản lý image/content/snapshots/task lifecycle; `runc` tạo container process theo OCI Runtime Specification.
- containerd namespaces như `moby` phân tách metadata; chúng không phải Linux network/PID namespaces và không tạo security boundary mạnh giữa người dùng có quyền socket.
- Kubernetes dùng CRI gRPC interface. `ctr` là công cụ debug containerd, còn `crictl` nói chuyện với CRI plugin; hai CLI không thể thay thế nhau.
- Docker đóng gói `containerd.io`; cấu hình/plugin CRI ở package đó phải được inspect trước khi kết luận Kubernetes có thể dùng trực tiếp.
- OCI image layers và snapshots ánh xạ image content sang filesystem; `runc` dùng kernel namespaces, cgroups, capabilities và seccomp.

## Architecture

```text
docker CLI -> dockerd -> containerd API -> containerd snapshotter -> OCI bundle -> runc -> Linux process
Kubernetes kubelet -> CRI gRPC -> CRI plugin -> containerd -> OCI runtime
```

## Điều kiện và commands

Chỉ sau Lab 07–10 cleanup, package/runtime versions đã xác minh và memory/disk gates fresh. Containerd sẽ đến từ Docker `containerd.io`; không cài distro `containerd` hoặc package thứ hai.

```bash
systemctl show docker containerd --property=LoadState,ActiveState,MemoryCurrent
containerd --version
ctr version
sudo ctr namespaces list
sudo ctr plugins list
sudo ctr -n moby containers list
sudo ctr -n moby tasks list
sudo ss -lx | grep -E 'containerd|docker'
```

`crictl info` chỉ chạy nếu CRI endpoint/plugin được thấy trong current config và người vận hành xác nhận endpoint. Không sửa `/etc/containerd/config.toml` chỉ để lệnh chạy.

## Hands-on và expected output

1. So sánh `docker version` với `containerd --version`/`ctr version`.
2. Liệt kê containerd namespaces và nhận ra `moby` metadata là Docker-owned.
3. So sánh `docker ps` với `ctr -n moby containers list` và tasks; Docker API vẫn là source of truth cho Docker objects.
4. Xem plugin types/status; ghi riêng `io.containerd.grpc.v1.cri` availability; không suy ra kubelet readiness từ `ctr`.
5. Cleanup Docker workload trước inspect; không xóa snapshots/content manually.

Actual VPS result: **NOT TESTED**; package/service chưa có.

## Troubleshooting

- `ctr` not found: xác minh Docker `containerd.io` package/version; không tự cài package mới.
- Permission denied: dùng `sudo` cho read-only inspection, không nới socket mode.
- CRI plugin unavailable: đây có thể là cấu hình Docker-bundled runtime; chỉ đọc config/logs, không sửa để mô phỏng kubelet.
- `ctr` không thấy Docker container: kiểm tra namespace (`moby` thường được Docker dùng) và socket endpoint; không xóa metadata.

## Security, backup và cleanup

Lab chỉ đọc Docker-owned resources sau khi app lab đã cleanup. Không start arbitrary OCI bundle, không mount host socket vào container, không xóa content/snapshots, không restart runtime. Không cài kubelet/Kubernetes trong Lab 11.

## Interview Q&A

1. **containerd là gì?** Container lifecycle/image/snapshot daemon; Docker và Kubernetes có thể giao tiếp qua các interface khác nhau.
2. **CRI khác OCI?** CRI là Kubernetes node runtime gRPC contract; OCI chuẩn hóa image/runtime specifications.
3. **`ctr` khác `crictl`?** `ctr` là containerd debug CLI; `crictl` là CRI client.
4. **containerd namespace là Linux namespace?** Không; đó là metadata partition bên trong containerd.
5. **Docker containerd có đồng nghĩa Kubernetes-ready?** Không; phải xác minh CRI plugin, socket/config, cgroups, kubelet compatibility và host gates.

## Verification và cleanup record

- containerd runtime inspection: **NOT TESTED**.
- Cleanup: không có artifacts/runtime changes.
- References: [containerd documentation](https://containerd.io/docs/), [CRI](https://kubernetes.io/docs/concepts/containers/cri/), [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec).
