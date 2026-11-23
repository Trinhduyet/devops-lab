# ASP.NET Core sample API — Lab 10

Ứng dụng tối giản cho Docker/Kubernetes labs. Target framework `net10.0`; .NET 10 là LTS và được hỗ trợ đến tháng 11-2028. SDK/runtime images hiện được ghim ở SDK `10.0.404` và ASP.NET runtime `10.0.15`, Ubuntu Noble. Kiểm tra servicing patches trước mỗi lần phát hành image.

## Endpoints và cấu hình

- `GET /` trả service name, assembly version và trạng thái; `APP_NAME` có thể đổi service name.
- `GET /health/live` kiểm tra process có phản hồi.
- `GET /health/ready` chỉ trả `ready` sau khi hosted lifecycle service chạy; khi shutdown bắt đầu, readiness chuyển về false.
- Logging dùng JSON console với timestamp UTC và message template; không ghi environment dump, request headers hoặc credentials.
- `SIGTERM` kích hoạt graceful shutdown; log có marker xác minh để test.

Không có database, cache, external NuGet dependency hoặc ghi dữ liệu ứng dụng lên filesystem.

## Build và test trên máy local

```powershell
dotnet --info
dotnet build .\applications\dotnet-sample-api\DevOpsLab.SampleApi.csproj --configuration Release
```

Integration smoke test dùng Bash, `curl` và .NET SDK; process chỉ bind loopback và script tự dừng nó bằng `SIGTERM`, kiểm tra graceful shutdown rồi xóa chính xác thư mục tạm:

```bash
./scripts/test-dotnet-api.sh
```

Chạy app trong terminal PowerShell thứ nhất:

```powershell
$env:APP_NAME = 'devops-lab-local'
$env:ASPNETCORE_URLS = 'http://127.0.0.1:5080'
dotnet run --project .\applications\dotnet-sample-api\DevOpsLab.SampleApi.csproj `
  --configuration Release --no-restore --no-launch-profile
```

Rồi trong terminal thứ hai:

```powershell
pwsh -File .\applications\dotnet-sample-api\tests\smoke.ps1 `
  -BaseUri http://127.0.0.1:5080 -ExpectedService devops-lab-local
```

Dừng ứng dụng bằng Ctrl+C và kiểm tra JSON log `Application shutdown completed gracefully`.

## Container image

Dockerfile dùng multi-stage build; build image ghim riêng SDK/runtime patch. Runtime chạy bằng built-in non-root `app` UID, port `8080`, filesystem read-only, và không cần write volume.

```powershell
docker compose -f .\applications\dotnet-sample-api\compose.yaml config --quiet
docker compose -f .\applications\dotnet-sample-api\compose.yaml up --build --detach
pwsh -File .\applications\dotnet-sample-api\tests\smoke.ps1 `
  -BaseUri http://127.0.0.1:8080
docker compose -f .\applications\dotnet-sample-api\compose.yaml logs --tail 20
docker compose -f .\applications\dotnet-sample-api\compose.yaml down --remove-orphans
```

Compose chỉ publish `127.0.0.1:8080`, giới hạn `192 MiB`, `0.50 CPU`, `64 PIDs`, bỏ capabilities, bật `no-new-privileges`, và cho 15 giây graceful shutdown. `EXPOSE` trong Dockerfile chỉ là metadata; `ports` trong Compose mới tạo host mapping.

VPS deployment đang chờ security gate, explicit approval cho từng host change và Docker package compatibility check. Không dùng `docker run -p 8080:8080` trên VPS hoặc mở IPv4/IPv6 application ingress. Sau khi VPS triển khai, chỉ truy cập bằng loopback binding và SSH tunnel.

## Troubleshooting

- `/health/ready` chưa trả 200: đọc JSON logs, kiểm tra app startup và hosted lifecycle; không biến readiness thành liveness.
- Container không start dưới non-root: kiểm tra permissions của mounted paths; API này không cần mount có quyền ghi.
- Docker image build lỗi tag: đối chiếu tag SDK/runtime đang được Microsoft publish; không đổi sang `latest` tùy tiện.
- Port bận: đổi `API_PORT` cho script local hoặc host-side port trong Compose; vẫn bind `127.0.0.1`.
- Docker Desktop engine unavailable: image build/container smoke là `NOT TESTED`; .NET source build không chứng minh Docker runtime.

## Verification và cleanup

`scripts/test-dotnet-api.sh` phải quan sát đủ ba endpoint, environment configuration, JSON shutdown event, process exit `0` và cleanup PASS. Container test bổ sung `docker inspect` để xác nhận non-root user, read-only root filesystem, resource limits và host binding loopback. Cleanup chỉ gỡ service/network thuộc Compose project này; không dùng prune toàn cục.

## Liên hệ Kubernetes

- `GET /health/live` có thể làm liveness probe; `GET /health/ready` có thể làm readiness probe.
- Compose CPU/RAM limits là runtime cgroups; khi chuyển Kubernetes, khai báo tương ứng trong `resources.limits`. Scheduler requests cần quyết định riêng và không suy ra từ CPU quota.
- Process non-root và read-only filesystem giảm quyền ghi, nhưng không thay thế `securityContext`, namespace isolation, seccomp hoặc node-level ingress controls.

## Kết quả

| Evidence class | Status |
|---|---|
| Source implementation | PASS — .NET 10 project builds with zero warnings |
| Windows/local HTTP smoke | PASS — `/`, `/health/live`, `/health/ready` |
| Linux graceful shutdown integration | PASS — hosted CI observed SIGTERM shutdown log, process exit `0` and exact temporary cleanup |
| Windows graceful shutdown | NOT TESTED — Windows test process required force cleanup after Ctrl+C did not stop it |
| Docker image/container on local engine | NOT TESTED — local Docker daemon unavailable at assessment |
| VPS Docker deployment | BLOCKED — live SSH/UFW security gate failed and each host change needs separate approval |
| Production readiness | Not claimed |

## Official references checked 2026-11-23

- [.NET release support policy](https://learn.microsoft.com/en-us/dotnet/core/releases-and-support) and [.NET 10 downloads](https://dotnet.microsoft.com/en-us/download/dotnet/10.0): .NET 10 is LTS; the current listed servicing patch is 10.0.15 and SDK 10.0.404.
- [Official .NET container tag policies](https://github.com/dotnet/dotnet-docker/blob/main/documentation/supported-tags.md): fixed Noble tags exist for SDK 10.0.404 and ASP.NET runtime 10.0.15. These pin .NET patches while Ubuntu base layers receive updates; record image digests when publishing a deployment image.
- [.NET container port and non-root guidance](https://learn.microsoft.com/en-us/dotnet/core/docker/): ASP.NET images use non-privileged port 8080 and include the `app` non-root user.
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) and [Docker packet filtering/firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/): Ubuntu 24.04 amd64 is supported; Docker-published ports can bypass UFW's normal filtering path.
