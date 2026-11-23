#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

IMAGE_REF='busybox:1.36.1'
CONTAINER_NAME="devops-lab-lab07-$(date -u +%Y%m%dT%H%M%SZ)-$$"
WATCHDOG_UNIT="devops-lab-lab07-stop-$(date +%s)-$$"
IMAGE_PULLED=0
IMAGE_ID=''
WATCHDOG_ARMED=0
CONTAINER_CREATE_ATTEMPTED=0
CLEANUP_FAILED=0

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }

cleanup() {
  local result=$? watchdog_state=not-created
  trap - EXIT
  set +e

  if (( CONTAINER_CREATE_ATTEMPTED == 1 )) && docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker stop --time=5 "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || CLEANUP_FAILED=1
  fi

  if (( WATCHDOG_ARMED == 1 )); then
    systemctl stop "$WATCHDOG_UNIT.timer" >/dev/null 2>&1 || true
    watchdog_state=$(systemctl is-active "$WATCHDOG_UNIT.timer" 2>/dev/null || true)
    if [[ "$watchdog_state" == active ]]; then CLEANUP_FAILED=1; fi
    [[ -n "$watchdog_state" ]] || watchdog_state=not-found
  fi

  if (( IMAGE_PULLED == 1 )) && [[ -n "$IMAGE_ID" ]]; then
    if [[ -n "$(docker ps -aq --filter "ancestor=$IMAGE_ID" 2>/dev/null)" ]]; then
      CLEANUP_FAILED=1
    else
      docker image rm "$IMAGE_REF" >/dev/null 2>&1 || CLEANUP_FAILED=1
    fi
  fi

  if (( CONTAINER_CREATE_ATTEMPTED == 1 )) && docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then CLEANUP_FAILED=1; fi
  if (( CLEANUP_FAILED == 0 )); then
    printf 'LAB07_CLEANUP=PASS container=%s watchdog=%s image=%s\n' "$([[ $CONTAINER_CREATE_ATTEMPTED == 1 ]] && echo removed || echo not-created)" "$watchdog_state" "$([[ $IMAGE_PULLED == 1 ]] && echo removed || echo preexisting-or-not-created)"
  else
    printf 'LAB07_CLEANUP=FAIL inspect only the named Lab 07 resources\n' >&2
    result=1
  fi
  exit "$result"
}
trap cleanup EXIT

[[ "$EUID" -eq 0 ]] || fail 'run through the key-only root SSH helper.'
[[ "$(stat -fc %T /sys/fs/cgroup)" == cgroup2fs ]] || fail 'cgroup v2 is not mounted.'
[[ "$(systemctl is-active docker.service 2>/dev/null)" == active ]] || fail 'Docker service is not active.'
[[ "$(systemctl is-active devops-lab-docker-rollback.timer 2>/dev/null || true)" != active ]] || fail 'the installation stop timer is still active.'

mem_available_kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
root_free_kib=$(df -Pk / | awk 'NR == 2 {print $4}')
cpu_count=$(getconf _NPROCESSORS_ONLN)
load_one=$(awk '{print $1}' /proc/loadavg)
awk -v value="$mem_available_kib" 'BEGIN {exit !(value >= 1048576)}' || fail 'MemAvailable is below 1 GiB.'
awk -v value="$root_free_kib" 'BEGIN {exit !(value >= 5242880)}' || fail 'root filesystem has less than 5 GiB free.'
awk -v average="$load_one" -v cpus="$cpu_count" 'BEGIN {exit !(average < cpus)}' || fail 'one-minute load is not below online CPU count.'
pass "workload resource gate (MemAvailable=${mem_available_kib}KiB, root-free=${root_free_kib}KiB, load=${load_one}/${cpu_count})"

if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then fail 'generated Lab 07 container name already exists; refusing to touch it.'; fi
if docker image inspect "$IMAGE_REF" >/dev/null 2>&1; then
  printf 'IMAGE_WAS_PRESENT=yes\n'
else
  command -v timeout >/dev/null 2>&1 || fail 'GNU timeout is unavailable for a bounded image pull.'
  timeout --signal=TERM --kill-after=5s 60s docker pull "$IMAGE_REF"
  IMAGE_PULLED=1
  printf 'IMAGE_PULLED=yes\n'
fi
IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$IMAGE_REF")
[[ -n "$IMAGE_ID" ]] || fail 'image ID was not returned.'
printf 'IMAGE_ID=%s\n' "$IMAGE_ID"

systemd-run --collect --quiet --unit="$WATCHDOG_UNIT" --on-active=90s --timer-property=AccuracySec=1s /usr/bin/docker stop --time=5 "$CONTAINER_NAME"
WATCHDOG_ARMED=1
[[ "$(systemctl is-active "$WATCHDOG_UNIT.timer" 2>/dev/null)" == active ]] || fail '90-second container stop watchdog is not active.'
pass '90-second container stop watchdog is active'

CONTAINER_CREATE_ATTEMPTED=1
timeout --signal=TERM --kill-after=5s 20s docker run --detach \
  --name "$CONTAINER_NAME" \
  --network bridge \
  --memory=64m --memory-swap=64m --cpus=0.25 --pids-limit=16 \
  --read-only --tmpfs /tmp:rw,nosuid,nodev,noexec,size=4m,mode=1777 \
  --cap-drop=ALL --security-opt=no-new-privileges --user 10001:10001 \
  --health-cmd='wget -q -O /dev/null http://127.0.0.1:8080/health' \
  --health-interval=2s --health-timeout=2s --health-retries=3 --health-start-period=1s \
  --stop-timeout=5 "$IMAGE_REF" \
  sh -c 'mkdir -p /tmp/www && printf healthy > /tmp/www/health && exec busybox httpd -f -p 8080 -h /tmp/www' >/dev/null

health=''
for _ in $(seq 1 15); do
  health=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)
  [[ "$health" == healthy ]] && break
  [[ "$health" == unhealthy ]] && fail 'container health check reported unhealthy.'
  sleep 1
done
[[ "$health" == healthy ]] || fail 'container did not become healthy within 15 seconds.'
pass 'bounded container health endpoint is healthy'

http_body=$(timeout 5s docker exec "$CONTAINER_NAME" wget -q -O - http://127.0.0.1:8080/health)
[[ "$http_body" == healthy ]] || fail 'HTTP health endpoint returned unexpected content.'
pass 'HTTP /health endpoint returned expected response'

timeout 5s docker exec "$CONTAINER_NAME" busybox nslookup registry-1.docker.io >/dev/null 2>&1 || fail 'container DNS lookup failed.'
pass 'container DNS lookup succeeded'

container_config=$(docker inspect --format '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}} {{.HostConfig.PidsLimit}} {{.HostConfig.ReadonlyRootfs}} {{.Config.User}} {{json .HostConfig.PortBindings}} {{json .HostConfig.CapDrop}} {{json .HostConfig.SecurityOpt}}' "$CONTAINER_NAME")
read -r memory_bytes nano_cpus pids_limit readonly_root run_as port_bindings cap_drop security_opts <<< "$container_config"
[[ "$memory_bytes" == 67108864 && "$nano_cpus" == 250000000 && "$pids_limit" == 16 && "$readonly_root" == true && "$run_as" == '10001:10001' ]] || fail 'container resource/user settings differ from the requested bounds.'
[[ "$port_bindings" == '{}' || "$port_bindings" == null ]] || fail 'container has a host port binding.'
[[ "$cap_drop" == '["ALL"]' && ( "$security_opts" == '["no-new-privileges"]' || "$security_opts" == '["no-new-privileges:true"]' ) ]] || fail 'container capabilities/security options differ from the requested bounds.'
printf 'CONTAINER_LIMITS=memory:67108864B cpu:0.25 pids:16 readonly:true user:10001:10001 ports:none caps:drop-all\n'

container_pid=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER_NAME")
cgroup_path=$(awk -F: '$1 == "0" {print $3}' "/proc/$container_pid/cgroup")
[[ -n "$cgroup_path" && -r "/sys/fs/cgroup${cgroup_path}/cpu.max" ]] || fail 'container cgroup files are unavailable.'
printf 'CGROUP_CPU_MAX=%s\n' "$(cat "/sys/fs/cgroup${cgroup_path}/cpu.max")"
printf 'CGROUP_MEMORY_MAX=%s\n' "$(cat "/sys/fs/cgroup${cgroup_path}/memory.max")"
printf 'CGROUP_PIDS_MAX=%s\n' "$(cat "/sys/fs/cgroup${cgroup_path}/pids.max")"

started_ns=$(date +%s%N)
docker stop --time=5 "$CONTAINER_NAME" >/dev/null
finished_ns=$(date +%s%N)
stop_ms=$(((finished_ns - started_ns) / 1000000))
state=$(docker inspect --format '{{.State.Status}} {{.State.OOMKilled}}' "$CONTAINER_NAME")
[[ "$state" == 'exited false' && "$stop_ms" -le 6000 ]] || fail 'container did not stop cleanly within the five-second grace period.'
printf 'GRACEFUL_STOP=PASS duration_ms=%s oom_killed=false\n' "$stop_ms"

exit 0
