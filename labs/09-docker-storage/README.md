# Lab 09 — Docker storage

## Mục tiêu và trạng thái

Học image layers, OverlayFS, writable container layer, bind mounts và named volumes; quan sát disk usage và cleanup đúng object. Lab đang **BLOCKED / NOT TESTED** vì Docker Engine chưa cài. Không sửa partition/mount host và không chạy prune.

## Lý thuyết

- Image layers immutable và có thể dùng chung giữa image/container. OverlayFS ghép lower layers read-only với upper writable layer.
- Writable layer là ephemeral. Named volume có vòng đời độc lập với container và phù hợp hơn cho container-managed persistent data.
- Bind mount ánh xạ path host cụ thể vào container; nó trao cho container quyền truy cập tới host path và cần scope hẹp, read-only khi có thể.
- Container storage quota/host free disk là hai góc nhìn khác. Docker image cache, container logs, volumes và build cache cùng sử dụng host filesystem.

## Architecture

```text
image manifest -> shared read-only layers -> OverlayFS lowerdir
container write -> OverlayFS upperdir -> deleted with container
named volume -> Docker-managed host directory -> survives container removal
bind mount -> chosen host path -> direct host/container shared files
```

## Điều kiện và commands

Chỉ chạy sau Lab 07 gate và khi `df -h`, inode usage, `docker system df` có đủ headroom. Chọn giới hạn data tối đa 1 MiB và tổng thời lượng 2 phút. Image test phải được resolve thành tag + digest từ nguồn chính thức trong lần thực thi; không dùng `latest`. Chọn image tối giản đã xác minh có `sh` và `cat`.

```bash
docker image inspect <approved-image>@sha256:<verified-digest>
docker history <approved-image>@sha256:<verified-digest>
docker system df -v
docker volume create devops-lab-storage
docker volume inspect devops-lab-storage
docker run --rm --memory=64m --cpus=0.25 --pids-limit=32 \
  --mount type=volume,source=devops-lab-storage,target=/labdata \
  <approved-image>@sha256:<verified-digest> sh -c 'printf lab-data > /labdata/marker; cat /labdata/marker'
docker run --rm --memory=64m --cpus=0.25 --pids-limit=32 \
  --mount type=volume,source=devops-lab-storage,target=/labdata,readonly \
  <approved-image>@sha256:<verified-digest> cat /labdata/marker
```

Lần đầu chứng minh file còn sau khi container kết thúc; lần sau đọc-only xác minh persistence. Digest/image/volume chưa được chọn hoặc tạo.

## Hands-on và expected output

1. So sánh `docker image inspect` size/digest với `docker history` layer sizes.
2. Tạo duy nhất volume `devops-lab-storage`; kiểm tra `Mountpoint` không xuất bản.
3. Ghi marker nhỏ, container đầu exit 0; container thứ hai in `lab-data`.
4. So sánh `docker system df -v` trước/sau; disk growth phải nhỏ và giải thích được.
5. Xóa đúng named volume sau khi xác minh thuộc lab.

Runtime evidence: **NOT TESTED**.

## Troubleshooting

- Read-only mount ngăn write: đây là kỳ vọng; container ghi test phải dùng mount writable riêng.
- `volume is in use`: tìm container exact name/ID; dừng/xóa đúng container, không force-remove mọi object.
- `no space left`: dừng ngay, ghi nhận `df`, `du` giới hạn, xóa chỉ artifacts đã xác định của lab; không tiếp tục tải image.
- Marker biến mất: kiểm tra mount source/destination và volume name; writable container layer không phải persistent storage.

## Security, backup và cleanup

- Lab chỉ lưu marker giả, không có dữ liệu cần backup. Không mount `/`, `/etc`, `/var/run/docker.sock` hoặc host home.
- Không `docker system prune`, `docker volume prune`, `rm -rf` mountpoint hoặc format filesystem.
- Cleanup theo thứ tự: remove exact test container, `docker volume inspect devops-lab-storage`, rồi `docker volume rm devops-lab-storage`; xác minh volume không tồn tại và disk metrics trở về gần baseline.

## Interview Q&A

1. **Writable layer biến mất khi nào?** Khi container bị xóa; image layers vẫn được chia sẻ.
2. **Volume khác bind mount thế nào?** Volume do Docker quản lý; bind mount trỏ path host do operator chọn.
3. **Image layer immutable nghĩa gì?** Container không sửa layer image gốc; writes được lưu ở upper layer riêng.
4. **Có nên backup writable layer?** Không; dữ liệu quan trọng nên nằm ở storage có backup/restore design đã kiểm thử.
5. **Vì sao tránh global prune?** Nó có thể xóa cache, image, network hay volumes ngoài phạm vi lab.

## Verification và cleanup record

- Storage exercise trên VPS: **BLOCKED / NOT TESTED**.
- Object/volume phát sinh: none; cleanup **NOT APPLICABLE**.
- References: [Docker storage](https://docs.docker.com/engine/storage/), [OverlayFS storage driver](https://docs.docker.com/engine/storage/drivers/overlayfs-driver/).
