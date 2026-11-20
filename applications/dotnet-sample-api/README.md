# ASP.NET Core sample API

Ứng dụng này sẽ là workload thực hành cho Docker rồi Kubernetes. Chưa tạo source/runtime image trước khi xác minh OS, Docker Engine và resource budget của VPS.

Kế hoạch: API health endpoint không chứa secret, multi-stage Dockerfile, non-root container, cấu hình qua environment, readiness/liveness probes khi đưa lên Kubernetes, image tags có version/digest. Không public endpoint cho tới khi firewall, DNS, TLS và access policy được thiết kế.
