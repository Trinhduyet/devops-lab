# Lab 10 — ASP.NET Core API trong container

## Mục tiêu và trạng thái

Tạo API ít phụ thuộc để luyện multi-stage build, non-root image, health probes, resource limits, logs, localhost-only publish và SSH tunnel. Source build và Windows/local HTTP smoke đã chạy PASS. Docker image/container trên local daemon và VPS **NOT TESTED**; triển khai VPS đang chờ public-service gate và approval riêng.

Source: [`applications/dotnet-sample-api`](../../applications/dotnet-sample-api/README.md).

## Lý thuyết

- Multi-stage Dockerfile giữ SDK/build artifacts khỏi runtime image.
- Non-root user, read-only filesystem, dropped capabilities và `no-new-privileges` thu hẹp quyền process.
- Liveness hỏi process còn sống; readiness hỏi nó có thể nhận traffic chưa. Readiness rút về false khi shutdown bắt đầu để caller ngừng gửi request.
- Compose `cpus` cài CPU quota cgroup; `mem_limit` cài memory cgroup; `pids_limit` cài task limit. Kubernetes requests dùng scheduler admission; limits map tới enforcement behavior khác nhau (CPU throttling, memory OOM kill).
- Compose health/resource settings không tự chứng minh host capacity hoặc production readiness.

## Kiến trúc

```text
SDK stage -> dotnet publish -> ASP.NET runtime image (UID app)
                                 | :8080
                                 `-- Docker loopback publish 127.0.0.1:8080
                                      `-- SSH tunnel -> Windows local client
```

## Commands

Local source build/smoke:

```powershell
dotnet build .\applications\dotnet-sample-api\DevOpsLab.SampleApi.csproj -c Release
$env:APP_NAME = 'devops-lab-local'
$env:ASPNETCORE_URLS = 'http://127.0.0.1:5080'
dotnet run --project .\applications\dotnet-sample-api\DevOpsLab.SampleApi.csproj -c Release --no-launch-profile
```

Terminal thứ hai gọi `pwsh -File .\applications\dotnet-sample-api\tests\smoke.ps1 -BaseUri http://127.0.0.1:5080 -ExpectedService devops-lab-local`.

Docker/Compose chỉ sau gate:

```powershell
docker compose -f .\applications\dotnet-sample-api\compose.yaml config --quiet
docker compose -f .\applications\dotnet-sample-api\compose.yaml up --build --detach
pwsh -File .\applications\dotnet-sample-api\tests\smoke.ps1
docker inspect --format '{{.Config.User}} {{.HostConfig.ReadonlyRootfs}} {{.HostConfig.Memory}} {{.HostConfig.NanoCpus}} {{json .HostConfig.PortBindings}}' <container>
docker compose -f .\applications\dotnet-sample-api\compose.yaml down --remove-orphans
```

VPS access chỉ bằng `ssh -N -L 8080:127.0.0.1:8080 devops-lab`; không mở public app port.

## Runtime results hiện có

| Scope | Result |
|---|---|
| .NET 10 Release source build | PASS, zero warnings/errors, isolated NuGet config/cache |
| Local HTTP | PASS: `/`, `/health/live`, `/health/ready`; service name config được đọc |
| Windows graceful SIGTERM | NOT TESTED; lần test process dừng bằng force cleanup sau khi Ctrl+C từ PTY không dừng |
| Linux CI smoke/shutdown | PENDING CI run |
| Compose YAML parse | PASS (`docker compose ... config --quiet`) |
| Docker image/container local | NOT TESTED; Docker daemon không khả dụng |
| VPS deployment | BLOCKED; host public-service gate chưa đạt |
| Test process cleanup | PASS; exact listener process dừng và test port đóng |

## Troubleshooting

- SDK missing: dùng .NET 10 SDK theo pin CI; kiểm tra `dotnet --info`.
- NuGet restore tries user config: dùng ephemeral `APPDATA`/`DOTNET_CLI_HOME`/`NUGET_PACKAGES` trong build automation; không thêm user NuGet config vào Git.
- Container unhealthy: đọc app JSON logs và kiểm tra `curl` từ container/host scope; phân biệt liveness/readiness.
- Container exits on start: kiểm tra UID/permissions, HTTP port 8080, read-only rootfs và log; API không cần writable persistent path.
- Host publish không loopback: dừng chính Compose project, kiểm tra rendered Compose và bindings; không mở firewall.

## Security và rollback

Image ghim .NET SDK/runtime patches đã kiểm tra theo official tags ngày 2026-11-23; refresh trước rebuild release. Compose giới hạn RAM 192 MiB, CPU 0.50, PIDs 64, filesystem read-only, `/tmp` 16 MiB, bỏ toàn bộ capabilities, `no-new-privileges`, và graceful stop 15 giây. Không dùng `docker compose down -v`; service không tạo named volume.

Rollback container là dừng đúng Compose project và xóa container/network của project. Không gỡ Docker Engine trong app rollback.

## Verification

Source verification quan sát đủ ba HTTP routes, cấu hình service name, graceful shutdown marker trên Linux CI, process exit `0`, và exact temp cleanup. Container verification cần inspect non-root user, read-only filesystem, limits và loopback mapping. VPS verification cần thêm `ssh -L` smoke; các bước container/VPS hiện chưa chạy.

## Cleanup

Local script dừng process bằng SIGTERM trong tối đa 10 giây, kiểm tra exit status và log, rồi xóa unique temporary directory. Compose cleanup dùng `docker compose down --remove-orphans`; xác minh không còn API process/container/network/listener. Không dùng `docker compose down -v`; service không tạo named volume.

## Interview Q&A

1. **Liveness khác readiness?** Liveness khởi động lại process khi hỏng; readiness điều khiển nhận traffic.
2. **Kubernetes CPU request khác limit?** Request ảnh hưởng scheduling/QoS; limit tạo quota/throttling. CPU request không dành riêng CPU theo nghĩa pin core mặc định.
3. **Container vượt memory limit thì sao?** Kernel cgroup OOM có thể kill container process; Kubernetes báo `OOMKilled` nếu container bị kill vì memory limit.
4. **Vì sao chạy non-root?** Giảm quyền khi app bị exploit, nhưng cần kết hợp filesystem/capability/namespace controls.
5. **`EXPOSE 8080` có publish port không?** Không; chỉ metadata. Compose `ports` tạo host mapping.

## References

- [.NET releases and support](https://learn.microsoft.com/en-us/dotnet/core/releases-and-support)
- [.NET container guidance](https://learn.microsoft.com/en-us/dotnet/core/docker/)
- [Docker Compose resources](https://docs.docker.com/compose/how-tos/resource-constraints/)
