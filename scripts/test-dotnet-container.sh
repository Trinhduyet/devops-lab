#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
APP_DIR="$ROOT/applications/dotnet-sample-api"
TEMP_ROOT=$(cd -- "${RUNNER_TEMP:-${TMPDIR:-/tmp}}" && pwd)
TEMP_DIR=$(mktemp -d "$TEMP_ROOT/devops-dotnet-container.XXXXXXXX")
COMPOSE_JSON="$TEMP_DIR/compose.json"
INSPECT_JSON="$TEMP_DIR/container.json"
IMAGE_TAG="devops-lab-sample-api-ci:${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
CONTAINER_NAME="devops-lab-sample-api-ci-${GITHUB_RUN_ID:-local}-$$"
APP_NAME_VALUE="$CONTAINER_NAME"

cleanup() {
  local result=$?
  trap - EXIT

  if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    if ! docker rm --force "$CONTAINER_NAME" >/dev/null; then
      printf 'FAIL: named smoke container cleanup failed.\n' >&2
      result=1
    fi
  fi
  if docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    if ! docker image rm "$IMAGE_TAG" >/dev/null; then
      printf 'FAIL: unique smoke image cleanup failed.\n' >&2
      result=1
    fi
  fi
  if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    printf 'FAIL: smoke container remains after cleanup.\n' >&2
    result=1
  fi
  if docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    printf 'FAIL: smoke image remains after cleanup.\n' >&2
    result=1
  fi

  if [[ -d "$TEMP_DIR" ]]; then
    if [[ "$TEMP_DIR" == "$TEMP_ROOT"/devops-dotnet-container.* ]] && rm -f -- "$COMPOSE_JSON" "$INSPECT_JSON" && rmdir -- "$TEMP_DIR"; then
      :
    else
      printf 'FAIL: refusing or unable to clean the unique smoke directory.\n' >&2
      result=1
    fi
  fi

  if (( result == 0 )); then printf 'PASS: named container, image and temporary output cleanup verified.\n'; fi
  exit "$result"
}
trap cleanup EXIT

docker info >/dev/null
docker compose version

docker compose -f "$APP_DIR/compose.yaml" config --format json > "$COMPOSE_JSON"
python3 - "$COMPOSE_JSON" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as compose_file:
    config = json.load(compose_file)
service = config.get("services", {}).get("sample-api")
if not isinstance(service, dict):
    raise SystemExit("FAIL: Compose service sample-api is absent.")

def byte_limit(value):
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    match = re.fullmatch(r"([0-9]+)([kmgt]i?b?)", str(value).lower())
    if not match:
        return None
    scale = {"k": 1024, "kb": 1024, "kib": 1024, "m": 1024**2, "mb": 1024**2, "mib": 1024**2,
             "g": 1024**3, "gb": 1024**3, "gib": 1024**3, "t": 1024**4, "tb": 1024**4, "tib": 1024**4}
    return int(match.group(1)) * scale[match.group(2)]

ports = service.get("ports", [])
args = service.get("build", {}).get("args", {})
if len(ports) != 1 or ports[0].get("host_ip") != "127.0.0.1" or str(ports[0].get("target")) != "8080":
    raise SystemExit("FAIL: Compose must publish only container port 8080 on host loopback.")
if byte_limit(service.get("mem_limit")) != 192 * 1024**2:
    raise SystemExit("FAIL: Compose memory limit must be 192 MiB.")
if float(service.get("cpus", 0)) != 0.5 or int(service.get("pids_limit", 0)) != 64:
    raise SystemExit("FAIL: Compose CPU/PID limits differ from the reviewed budget.")
if service.get("read_only") is not True or service.get("init") is not True:
    raise SystemExit("FAIL: Compose must use a read-only root and init process.")
if "ALL" not in service.get("cap_drop", []) or "no-new-privileges:true" not in service.get("security_opt", []):
    raise SystemExit("FAIL: Compose must drop all capabilities and enable no-new-privileges.")
if args.get("DOTNET_SDK_IMAGE") != "mcr.microsoft.com/dotnet/sdk:10.0.404-noble":
    raise SystemExit("FAIL: Compose SDK image tag differs from the reviewed fixed .NET 10 tag.")
if args.get("DOTNET_ASPNET_IMAGE") != "mcr.microsoft.com/dotnet/aspnet:10.0.15-noble":
    raise SystemExit("FAIL: Compose runtime image tag differs from the reviewed fixed .NET 10 tag.")
print("PASS: Compose config keeps loopback binding, fixed .NET tags, read-only root, and bounded resources.")
PY

docker build --pull --tag "$IMAGE_TAG" --file "$APP_DIR/Dockerfile" "$APP_DIR"
image_user=$(docker image inspect --format '{{.Config.User}}' "$IMAGE_TAG")
if [[ ! "$image_user" =~ ^[1-9][0-9]*$ ]]; then
  printf 'FAIL: image runtime user is not a non-root numeric UID.\n' >&2
  exit 1
fi
printf 'PASS: image config selects non-root UID %s.\n' "$image_user"

docker run --detach --init --name "$CONTAINER_NAME" \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m \
  --memory=201326592 --cpus=0.50 --pids-limit=64 \
  --cap-drop=ALL --security-opt=no-new-privileges:true \
  --stop-timeout=15 \
  --publish 127.0.0.1::8080 \
  --env "APP_NAME=$APP_NAME_VALUE" \
  --env ASPNETCORE_ENVIRONMENT=Production \
  --env ASPNETCORE_HTTP_PORTS=8080 \
  "$IMAGE_TAG" >/dev/null

docker inspect "$CONTAINER_NAME" > "$INSPECT_JSON"
python3 - "$INSPECT_JSON" "$image_user" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as inspect_file:
    container = json.load(inspect_file)[0]
config = container["Config"]
host = container["HostConfig"]
if config["User"] != sys.argv[2] or int(config["User"]) == 0:
    raise SystemExit("FAIL: running container config is not non-root.")
if host["ReadonlyRootfs"] is not True:
    raise SystemExit("FAIL: running container root filesystem is writable.")
if host["Memory"] != 201326592 or host["NanoCpus"] != 500000000 or host["PidsLimit"] != 64:
    raise SystemExit("FAIL: running container resource limits do not match the reviewed budget.")
if host["Init"] is not True or host["CapDrop"] != ["ALL"] or "no-new-privileges:true" not in host["SecurityOpt"]:
    raise SystemExit("FAIL: running container security options differ from the Compose policy.")
bindings = host["PortBindings"].get("8080/tcp", [])
if len(bindings) != 1 or bindings[0].get("HostIp") != "127.0.0.1":
    raise SystemExit("FAIL: container port binding is not loopback-only.")
print("PASS: running container is non-root, read-only, loopback-only, and resource-bounded.")
PY

container_uid=$(docker exec "$CONTAINER_NAME" id -u)
if [[ "$container_uid" != "$image_user" || "$container_uid" == 0 ]]; then
  printf 'FAIL: main container process UID does not match the non-root image user.\n' >&2
  exit 1
fi

if docker exec --user 0 "$CONTAINER_NAME" /bin/sh -c 'touch /app/.readonly-probe' >/dev/null 2>&1; then
  printf 'FAIL: root wrote to /app despite the read-only root filesystem.\n' >&2
  exit 1
fi
docker exec "$CONTAINER_NAME" /bin/sh -c 'touch /tmp/.tmpfs-probe && rm /tmp/.tmpfs-probe'
printf 'PASS: root filesystem rejects writes while bounded /tmp tmpfs remains writable.\n'

memory_max=$(docker exec "$CONTAINER_NAME" cat /sys/fs/cgroup/memory.max)
cpu_max=$(docker exec "$CONTAINER_NAME" cat /sys/fs/cgroup/cpu.max)
pids_max=$(docker exec "$CONTAINER_NAME" cat /sys/fs/cgroup/pids.max)
if [[ "$memory_max" != 201326592 || "$cpu_max" != '50000 100000' || "$pids_max" != 64 ]]; then
  printf 'FAIL: cgroup v2 limits differ from memory/cpu/pid expectations.\n' >&2
  exit 1
fi
printf 'PASS: cgroup v2 enforces memory, CPU quota and PID limits.\n'

published=$(docker port "$CONTAINER_NAME" 8080/tcp)
if [[ ! "$published" =~ ^127\.0\.0\.1:([0-9]{1,5})$ ]]; then
  printf 'FAIL: Docker did not allocate a loopback-only ephemeral host port.\n' >&2
  exit 1
fi
BASE_URL="http://127.0.0.1:${BASH_REMATCH[1]}"
ready=0
for _ in {1..30}; do
  if curl --fail --silent --max-time 2 "$BASE_URL/health/ready" >/dev/null 2>&1; then ready=1; break; fi
  if [[ $(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME") != true ]]; then break; fi
  sleep 1
done
if (( ready != 1 )); then
  printf 'FAIL: container did not become ready on its unique loopback port.\n' >&2
  docker logs "$CONTAINER_NAME" 2>&1 | tail -n 12 >&2 || true
  exit 1
fi

root_payload=$(curl --fail --silent --show-error --max-time 5 "$BASE_URL/")
if [[ "$root_payload" != *"\"service\":\"$APP_NAME_VALUE\""* || "$root_payload" != *'"status":"ok"'* ]]; then
  printf 'FAIL: container root endpoint did not respond as this unique smoke instance.\n' >&2
  exit 1
fi
live_payload=$(curl --fail --silent --show-error --max-time 5 "$BASE_URL/health/live")
ready_payload=$(curl --fail --silent --show-error --max-time 5 "$BASE_URL/health/ready")
if [[ "$live_payload" != *'"status":"live"'* || "$ready_payload" != *'"status":"ready"'* ]]; then
  printf 'FAIL: container health endpoint payloads were unexpected.\n' >&2
  exit 1
fi
printf 'PASS: container root, liveness and readiness endpoints responded.\n'

docker stop --time 15 "$CONTAINER_NAME" >/dev/null
exit_code=$(docker inspect --format '{{.State.ExitCode}}' "$CONTAINER_NAME")
oom_killed=$(docker inspect --format '{{.State.OOMKilled}}' "$CONTAINER_NAME")
container_logs=$(docker logs "$CONTAINER_NAME" 2>&1)
if [[ "$exit_code" != 0 || "$oom_killed" != false ]] \
  || ! grep -Fq 'Application stopping; readiness withdrawn' <<< "$container_logs" \
  || ! grep -Fq 'Application shutdown completed gracefully' <<< "$container_logs"; then
  printf 'FAIL: container did not shut down gracefully within its bounded stop period.\n' >&2
  exit 1
fi
printf 'PASS: Docker stop delivered graceful shutdown; exit=0 and no OOM.\n'
