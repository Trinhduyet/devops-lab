# Lab 08 — Docker networking

## Mục tiêu và trạng thái

Quan sát bridge, veth, embedded DNS, NAT và port publishing. Lab đang **BLOCKED / NOT TESTED** vì Docker Engine chưa được cài. Cài runtime cần `host-change` gate và approval; chỉ một bài tập mở ingress Internet mới cần `public-services`. Không cấu hình host networking/firewall trong lab.

## Lý thuyết

- Default bridge tạo L2 segment ảo trên host; mỗi container có network namespace và veth pair nối vào bridge.
- User-defined bridge cung cấp DNS discovery theo container/service name. Container outbound thường dùng masquerade/SNAT; port publishing cài host-to-container forwarding/DNAT.
- `127.0.0.1:HOST:CONTAINER` giới hạn listener ở loopback; `HOST:CONTAINER` có thể bind trên mọi host interface. Docker quản lý packet filtering rules và có thể bypass cách UFW xử lý traffic INPUT thông thường.
- Docker network không mã hóa traffic trong bridge và không thay thế authentication giữa services.

## Kiến trúc

```text
127.0.0.1:8080 -> host netfilter/NAT -> docker bridge -> container:8080
                                           | veth
                                      network namespace
```

## Điều kiện và commands

Đọc [Lab 07](../07-docker-engine/README.md), skill container runtime và firewall runbook. Chỉ chạy sau Docker gate. Dùng image từ Lab 10 đã được pin tag/digest; bounded API workload limits: 192 MiB RAM, 0.50 CPU, 64 PIDs, thời lượng tối đa 10 phút.

```bash
docker network ls
docker network inspect bridge
docker compose -f applications/dotnet-sample-api/compose.yaml config
docker compose -f applications/dotnet-sample-api/compose.yaml up --build --detach
container_id="$(docker compose -f applications/dotnet-sample-api/compose.yaml ps -q sample-api)"
test -n "$container_id"
docker inspect --format '{{json .NetworkSettings.Networks}}' "$container_id"
docker port "$container_id"
sudo ss -lnt
```

Compose host binding dự kiến chỉ là `127.0.0.1:8080`; xác minh bằng `docker compose ps`, `docker port`, `docker inspect` và `ss`. Sau đó chạy API smoke test từ VPS loopback và từ Windows qua SSH tunnel. Không thử Internet/public access.

## Hands-on và expected output

1. Ghi network driver, subnet/gateway đã cấp runtime-local; không công bố host routes/IPs.
2. Xác minh app container và gateway cùng network namespace policy như khai báo.
3. Xác minh `docker port` chỉ trả loopback binding.
4. Tạo SSH tunnel `ssh -N -L 8080:127.0.0.1:8080 devops-lab` trong terminal riêng, gọi smoke test từ local, rồi đóng tunnel.
5. So sánh app reachability local loopback với không có public listener.

Actual runtime result: **NOT TESTED**; chưa có network/container nào được tạo.

## Troubleshooting

- DNS service name không resolve: so sánh `docker network inspect` và container attachments; không dùng container IP cố định.
- Local API không phản hồi: xác minh container health/logs, host port binding, listener và tunnel destination.
- Port bind bị từ chối: host port có thể đang dùng; chọn port local khác, vẫn giới hạn `127.0.0.1`.
- Firewall behavior không như mong đợi: dừng lab service, quan sát ruleset; không sửa UFW/nftables để né lỗi.

## Security, rollback, cleanup

- Không `--network host`; không publish IPv4/IPv6 public port; không mở provider port.
- Cleanup bằng `docker compose down --remove-orphans` đúng project. Không dùng `down -v` trừ khi đã xác nhận volume thuộc lab và không chứa dữ liệu; lab này không cần volume.
- Xác minh không còn app container, network mới, listener hoặc SSH tunnel process.
- Backup không áp dụng vì lab chỉ tạo network/container tạm và không sửa host network config; rollback là dừng đúng Compose project và tunnel.

## Interview Q&A

1. **Bridge và host network khác gì?** Bridge dùng network namespace/veth; host mode chia sẻ network stack host và giảm cách ly.
2. **Port publishing làm gì?** Tạo forwarding/NAT mapping từ host address/port đến container port.
3. **Tại sao localhost binding quan trọng?** Nó tránh tạo listener trên các interface public; vẫn phải xác minh runtime mapping và provider policy.
4. **Docker DNS hoạt động ở đâu?** User-defined Docker networks cung cấp DNS theo service/container identity trong phạm vi network.
5. **Network isolation có thay auth không?** Không; network membership chỉ giảm reachability, không xác thực caller.

## Verification và cleanup record

- VPS Docker networking: **BLOCKED / NOT TESTED**.
- Cleanup: **NOT APPLICABLE**, chưa tạo object nào.
- Official reference: [Docker networking](https://docs.docker.com/engine/network/), [packet filtering/firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/).
