#!/usr/bin/env bash
# Lab 03: read-only Linux performance diagnostics plus a bounded transient cgroup exercise.
set -uo pipefail
export LC_ALL=C

ERRORS=0
MISSING=0
UNIT=''
UNIT_STARTED=0
SERVICE_PID=''
CONTROL_GROUP=''

section() { printf '\n===== %s =====\n' "$1"; }
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; ERRORS=$((ERRORS + 1)); }
missing() { printf 'UNKNOWN: %s\n' "$1"; MISSING=$((MISSING + 1)); }
not_tested() { printf 'NOT TESTED: %s\n' "$1"; }

cleanup() {
  local cleanup_errors=0 load_state active_state status
  if [[ "$UNIT_STARTED" == 1 && -n "$UNIT" ]]; then
    if load_state=$(systemctl show --property=LoadState --value "$UNIT"); then
      if [[ "$load_state" != not-found ]]; then
        if ! timeout 10s systemctl stop "$UNIT"; then
          printf 'CLEANUP FAILED: could not stop transient service.\n' >&2
          cleanup_errors=$((cleanup_errors + 1))
        fi
        if active_state=$(systemctl show --property=ActiveState --value "$UNIT"); then
          if [[ "$active_state" != inactive && "$active_state" != failed ]]; then
            printf 'CLEANUP FAILED: transient service state is %s after stop.\n' "${active_state:-unknown}" >&2
            cleanup_errors=$((cleanup_errors + 1))
          fi
        else
          status=$?
          printf 'CLEANUP FAILED: could not verify transient service state (exit=%s).\n' "$status" >&2
          cleanup_errors=$((cleanup_errors + 1))
        fi
      fi
    else
      status=$?
      printf 'CLEANUP FAILED: could not inspect transient service (exit=%s).\n' "$status" >&2
      cleanup_errors=$((cleanup_errors + 1))
    fi
    if [[ -n "$SERVICE_PID" ]] && kill -0 "$SERVICE_PID" 2>/dev/null; then
      printf 'CLEANUP FAILED: service process is still present after stop.\n' >&2
      cleanup_errors=$((cleanup_errors + 1))
    fi
    if [[ -n "$CONTROL_GROUP" && -e "/sys/fs/cgroup$CONTROL_GROUP" ]]; then
      printf 'CLEANUP FAILED: transient cgroup still exists after stop.\n' >&2
      cleanup_errors=$((cleanup_errors + 1))
    fi
    UNIT_STARTED=0
  fi
  return "$cleanup_errors"
}
trap 'cleanup || ERRORS=$((ERRORS + 1))' EXIT

section 'Read-only performance prerequisites'
for command_name in uptime lscpu top ps free vmstat df systemctl systemd-run journalctl python3 awk grep sleep timeout date; do
  if command -v "$command_name" >/dev/null 2>&1; then printf 'AVAILABLE: %s\n' "$command_name"; else printf 'NOT TESTED: required lab command %s is unavailable.\n' "$command_name"; MISSING=$((MISSING + 1)); fi
done
for path in /proc/stat /proc/meminfo /proc/diskstats /proc/pressure/cpu /sys/fs/cgroup/cgroup.controllers; do
  if [[ -r "$path" ]]; then printf 'AVAILABLE: %s\n' "${path##*/}"; else not_tested "required runtime file is unavailable: ${path##*/}"; MISSING=$((MISSING + 1)); fi
done
if (( MISSING > 0 )); then printf 'LAB 03 STATUS=UNKNOWN; required read-only evidence is missing (exit=2).\n'; exit 2; fi
if [[ "$(id -u)" != 0 ]]; then missing 'bounded transient system service requires the authorized root SSH session.'; printf 'LAB 03 STATUS=UNKNOWN; system manager access is missing (exit=2).\n'; exit 2; fi
cgroup_controllers=$(cat /sys/fs/cgroup/cgroup.controllers)
if ! grep -qw cpu <<< "$cgroup_controllers" || ! grep -qw memory <<< "$cgroup_controllers"; then missing 'cgroup v2 does not expose both CPU and memory controllers.'; printf 'LAB 03 STATUS=UNKNOWN; cgroup v2 CPU and memory controllers are required for the limit exercise (exit=2).\n'; exit 2; fi

section 'CPU, load average, scheduler and process states'
if uptime_output=$(uptime); then printf '%s\n' "$uptime_output"; else status=$?; missing "uptime query failed (exit=$status)."; fi
if cpu_topology=$(lscpu); then
  awk -F: '$1 ~ /^[[:space:]]*(Architecture|CPU\(s\)|On-line CPU\(s\) list|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|Hypervisor vendor|Virtualization type)$/ {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $1 ": " $2}' <<< "$cpu_topology"
  printf 'Guest-visible logical CPUs are vCPU capacity; the VPS guest cannot establish the physical host core count.\n'
else status=$?; missing "lscpu failed (exit=$status)."; fi
if top_summary=$(top -b -n 1); then awk 'NR <= 5 {print}' <<< "$top_summary"; else status=$?; missing "top snapshot failed (exit=$status)."; fi
if process_states=$(ps -eo stat=); then
  awk '{state=substr($1,1,1); count[state]++} END {for (state in count) printf "process state %s: %d\n", state, count[state]}' <<< "$process_states" | sort
else status=$?; missing "ps process-state inventory failed (exit=$status)."; fi
if vmstat_sample=$(vmstat 1 2); then printf '%s\n' "$vmstat_sample"; else status=$?; missing "vmstat sample failed (exit=$status)."; fi

section 'CPU time counters: user, system, idle, iowait and steal'
cpu_ticks() { awk '$1 == "cpu" {printf "%s %s %s %s %s %s %s %s\n", $2,$3,$4,$5,$6,$7,$8,$9; found=1} END {if (!found) exit 1}' /proc/stat; }
if cpu_before=$(cpu_ticks); then
  sleep 1
  if cpu_after=$(cpu_ticks); then
    awk -v before="$cpu_before" -v after="$cpu_after" 'BEGIN {split(before,b); split(after,a); user=(a[1]-b[1])+(a[2]-b[2]); sys_ticks=(a[3]-b[3])+(a[6]-b[6])+(a[7]-b[7]); idle=a[4]-b[4]; iowait=a[5]-b[5]; steal=a[8]-b[8]; total=user+sys_ticks+idle+iowait+steal; if(total<=0) {print "UNKNOWN: /proc/stat CPU delta was empty."; exit 1} printf "sampled CPU: user=%.1f%% system=%.1f%% idle=%.1f%% iowait=%.1f%% steal=%.1f%%\n",100*user/total,100*sys_ticks/total,100*idle/total,100*iowait/total,100*steal/total}' || ERRORS=$((ERRORS + 1))
  else status=$?; missing "second /proc/stat sample failed (exit=$status)."; fi
else status=$?; missing "first /proc/stat sample failed (exit=$status)."; fi
if loadavg=$(cat /proc/loadavg); then awk '{printf "load average 1/5/15 min: %s %s %s\nrunnable/total processes: %s\n",$1,$2,$3,$4}' <<< "$loadavg"; else status=$?; missing "load average read failed (exit=$status)."; fi
if systemd_limits=$(systemctl show --property=DefaultCPUAccounting --property=DefaultMemoryAccounting --property=DefaultTasksAccounting --property=DefaultLimitNOFILE); then printf '%s\n' "$systemd_limits"; else status=$?; not_tested "systemd manager defaults unavailable (exit=$status)."; fi

section 'Memory allocation, page cache, virtual memory and swap'
if free_output=$(free -h); then printf '%s\n' "$free_output"; else status=$?; missing "free query failed (exit=$status)."; fi
if meminfo=$(awk '/^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SReclaimable|Shmem|Dirty|Writeback|SwapTotal|SwapFree|CommitLimit|Committed_AS|PageTables|Slab):/ {print}' /proc/meminfo); then printf '%s\n' "$meminfo"; else status=$?; missing "/proc/meminfo read failed (exit=$status)."; fi
if [[ -r /proc/swaps ]]; then
  awk 'NR > 1 {count++; total+=$3; used+=$4} END {printf "swap devices=%d total=%d KiB used=%d KiB\n",count,total,used}' /proc/swaps
else not_tested '/proc/swaps is unavailable.'; fi
if oom_records=$(journalctl --kernel --since '7 days ago' --grep='out of memory|oom-kill|Killed process' --no-pager --output=cat 2>/dev/null | wc -l); then printf 'matching OOM kernel log records in the last 7 days: %s (journal retention is not proof of no prior OOM)\n' "${oom_records//[[:space:]]/}"; else status=$?; not_tested "kernel OOM log search unavailable (exit=$status)."; fi

section 'Disk capacity and I/O counters'
if df_output=$(df -hT /) && inode_output=$(df -ih /); then printf '%s\n%s\n' "$df_output" "$inode_output"; else status=$?; missing "filesystem capacity/inode query failed (exit=$status)."; fi
if command -v du >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  if du_output=$(timeout 10s du -x -s /var/log /var/cache /tmp 2>/dev/null); then awk '{printf "directory usage: %s %s\n",$1,$2}' <<< "$du_output"; else status=$?; not_tested "bounded du sample unavailable or exceeded 10s (exit=$status)."; fi
else not_tested 'du/timeout unavailable for the bounded directory-size sample.'; fi

disk_counters() {
  local name reads sectors_read read_ms writes sectors_write write_ms io_ms
  while read -r _ _ name reads _ sectors_read read_ms writes _ sectors_write write_ms _ io_ms _; do
    [[ -e "/sys/block/$name" ]] || continue
    case "$name" in loop*|ram*|dm-*) continue ;; esac
    printf '%s %s %s %s %s %s %s\n' "$reads" "$sectors_read" "$read_ms" "$writes" "$sectors_write" "$write_ms" "$io_ms"
  done < /proc/diskstats
}
disk_before=$(disk_counters)
if [[ -z "$disk_before" ]]; then not_tested 'no whole block-device counters were exposed by /proc/diskstats.'; else
  sleep 1
  disk_after=$(disk_counters)
  if [[ -n "$disk_after" ]]; then
    awk -v before="$disk_before" -v after="$disk_after" 'BEGIN {nb=split(before,b,"\n"); n=split(after,a,"\n"); if(nb<n)n=nb; for(i=1;i<=n;i++){split(b[i],x); split(a[i],y); reads+=y[1]-x[1]; rsec+=y[2]-x[2]; rms+=y[3]-x[3]; writes+=y[4]-x[4]; wsec+=y[5]-x[5]; wms+=y[6]-x[6]; busy+=y[7]-x[7]} printf "whole-device sample (about 1s): read IOPS=%.1f write IOPS=%.1f read MB/s=%.3f write MB/s=%.3f\n",reads,writes,rsec*512/1000000,wsec*512/1000000; if(reads>=10) printf "mean completed-read time in this sample: %.3f ms\n",rms/reads; else print "read latency: NOT TESTED (<10 completed reads; too few operations)"; if(writes>=10) printf "mean completed-write time in this sample: %.3f ms\n",wms/writes; else print "write latency: NOT TESTED (<10 completed writes; too few operations)"; printf "device busy-counter delta: %d ms (multi-device sum; not a normalized utilization percent)\n",busy}'
  else missing 'second /proc/diskstats sample was empty.'; fi
fi
printf 'Diskstats latency is averaged only over operations completed during this short sample; zero operations means no latency measurement.\n'

section 'File descriptors, cgroup v2 and pressure stall information'
printf 'shell ulimit -n: '; ulimit -n
if file_nr=$(cat /proc/sys/fs/file-nr); then awk '{printf "host file handles allocated=%s unused=%s kernel maximum=%s\n",$1,$2,$3}' <<< "$file_nr"; else status=$?; missing "/proc/sys/fs/file-nr read failed (exit=$status)."; fi
printf 'cgroup v2 controllers: '; tr ' ' ',' < /sys/fs/cgroup/cgroup.controllers; printf '\n'
for property in cpu.stat memory.stat; do
  if [[ -r "/sys/fs/cgroup/$property" ]]; then printf 'root cgroup %s: ' "$property"; tr '\n' ';' < "/sys/fs/cgroup/$property"; printf '\n'; else not_tested "root cgroup property $property unavailable."; fi
done
for pressure in cpu memory io; do
  if [[ -r "/proc/pressure/$pressure" ]]; then printf 'PSI %s: ' "$pressure"; tr '\n' ';' < "/proc/pressure/$pressure"; printf '\n'; else not_tested "PSI $pressure unavailable."; fi
done

available_kb=$(awk '$1 == "MemAvailable:" {print $2}' /proc/meminfo)
load_one=$(awk '{print $1}' /proc/loadavg)
if [[ ! "$available_kb" =~ ^[0-9]+$ || ! "$load_one" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  missing 'resource headroom could not be read; bounded workload was not started.'
  printf 'LAB 03 STATUS=UNKNOWN; resource headroom missing (exit=2).\n'
  exit 2
fi
if awk -v avail="$available_kb" -v one_minute="$load_one" 'BEGIN {exit !(avail >= 1048576 && one_minute < 2.0)}'; then
  pass 'preflight headroom: at least 1 GiB MemAvailable and one-minute load below 2 on this 4-vCPU guest.'
else
  missing 'host headroom is below the lab threshold; bounded workload skipped.'
  printf 'LAB 03 STATUS=UNKNOWN; retry when host load is lower and at least 1 GiB is available (exit=2).\n'
  exit 2
fi

section 'Bounded systemd CPU and memory cgroup exercise'
UNIT="devops-lab03-performance-$$.service"
case "$UNIT" in devops-lab03-performance-[0-9]*.service) ;; *) fail 'generated unit name is outside the expected prefix.'; exit 1 ;; esac
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
workload_code='import time,resource; data=bytearray(24*1024*1024); [data.__setitem__(i,1) for i in range(0,len(data),4096)]; print("DEVOPS_LAB03_MEMORY_ALLOCATED=25165824",flush=True); print("DEVOPS_LAB03_MEMORY_RSS_KIB=%d" % resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,flush=True); deadline=time.monotonic()+2; value=0
while time.monotonic()<deadline: value=(value+1)%1000003
print("DEVOPS_LAB03_CPU_SAMPLE_DONE",flush=True); time.sleep(8)'
if systemd-run --quiet --no-block --unit="$UNIT" --property=CPUQuota=20% --property=MemoryMax=96M --property=TasksMax=4 --property=RuntimeMaxSec=10s /usr/bin/python3 -c "$workload_code"; then
  UNIT_STARTED=1
  pass 'temporary service accepted with CPUQuota=20%, MemoryMax=96M, TasksMax=4 and RuntimeMaxSec=10s.'
else status=$?; fail "systemd-run rejected bounded cgroup service (exit=$status)."; fi

if [[ "$UNIT_STARTED" == 1 ]]; then
  active_state=''
  for attempt in {1..30}; do
    if active_state=$(systemctl show --property=ActiveState --value "$UNIT"); then [[ "$active_state" == active ]] && break; else status=$?; fail "systemctl could not inspect the temporary service (exit=$status)."; break; fi
    sleep 0.1
  done
  if [[ "$active_state" == active ]]; then
    SERVICE_PID=$(systemctl show --property=MainPID --value "$UNIT")
    control_group=$(systemctl show --property=ControlGroup --value "$UNIT")
    CONTROL_GROUP=$control_group
    if [[ "$SERVICE_PID" =~ ^[1-9][0-9]*$ && "$control_group" == "/system.slice/$UNIT" ]]; then
      pass 'transient service active with an exact system.slice cgroup path.'
    else
      fail 'transient service PID or cgroup path did not match the generated unit.'
    fi
    cgroup_dir="/sys/fs/cgroup$control_group"
    if [[ -r "$cgroup_dir/cpu.max" && -r "$cgroup_dir/memory.max" && -r "$cgroup_dir/cpu.stat" && -r "$cgroup_dir/pids.max" && -r "$cgroup_dir/pids.current" ]]; then
      cpu_max=$(cat "$cgroup_dir/cpu.max")
      memory_max=$(cat "$cgroup_dir/memory.max")
      pids_max=$(cat "$cgroup_dir/pids.max")
    else
      missing 'transient cgroup cpu.max/memory.max/cpu.stat files were not available.'
    fi
    ready_seen=0
    for attempt in {1..30}; do
      if service_log=$(journalctl --unit="$UNIT" --since="$started_at" --no-pager --output=cat 2>/dev/null); then
        if grep -Fqx 'DEVOPS_LAB03_CPU_SAMPLE_DONE' <<< "$service_log"; then ready_seen=1; break; fi
      fi
      sleep 0.1
    done
    if [[ "$ready_seen" == 1 ]]; then pass 'journal recorded the bounded allocation and CPU sampling markers.'; else fail 'bounded workload completion marker was not observed in the unit journal.'; fi
    memory_rss_kib=$(awk -F= '$1 == "DEVOPS_LAB03_MEMORY_RSS_KIB" {print $2; exit}' <<< "${service_log:-}")
    memory_allocated=$(awk -F= '$1 == "DEVOPS_LAB03_MEMORY_ALLOCATED" {print $2; exit}' <<< "${service_log:-}")
    if [[ "$memory_allocated" == 25165824 && "$memory_rss_kib" =~ ^[0-9]+$ ]] && (( memory_rss_kib >= 20480 )); then pass "workload touched 24 MiB; Python peak RSS=${memory_rss_kib} KiB."; else fail 'journal did not verify the bounded 24 MiB allocation and resident-set marker.'; fi
    if [[ -r "$cgroup_dir/memory.current" && -r "$cgroup_dir/memory.stat" && -r "$cgroup_dir/pids.current" ]]; then
      memory_current=$(cat "$cgroup_dir/memory.current")
      pids_current=$(cat "$cgroup_dir/pids.current")
      process_rss_kib=$(awk '$1 == "VmRSS:" {print $2}' "/proc/$SERVICE_PID/status")
      memory_detail=$(awk '$1 == "anon" || $1 == "file" || $1 == "kernel" {printf "%s=%s ", $1, $2}' "$cgroup_dir/memory.stat")
      cpu_usage=$(systemctl show --property=CPUUsageNSec --value "$UNIT")
      cpu_throttled=$(awk '$1 == "nr_throttled" {print $2}' "$cgroup_dir/cpu.stat")
      printf 'transient cgroup cpu.max=%s; memory.current=%s bytes; memory.max=%s bytes; memory.stat{%s}; process VmRSS=%s KiB; pids.current=%s; pids.max=%s; CPUUsageNSec=%s; throttled periods=%s\n' "$cpu_max" "$memory_current" "$memory_max" "$memory_detail" "$process_rss_kib" "$pids_current" "$pids_max" "$cpu_usage" "${cpu_throttled:-0}"
      if [[ "$cpu_max" == '20000 100000' && "$memory_max" == 100663296 && "$memory_current" =~ ^[0-9]+$ && "$process_rss_kib" =~ ^[0-9]+$ && "$pids_max" == 4 && "$pids_current" =~ ^[0-9]+$ ]] && (( memory_current > 0 && memory_current < memory_max && process_rss_kib < 98304 && pids_current > 0 && pids_current <= pids_max )) && [[ "$cpu_usage" =~ ^[0-9]+$ ]]; then
        pass 'cgroup v2 applied the configured CPU quota and memory ceiling; post-allocation usage stayed below both limits.'
      else
        fail 'post-allocation cgroup values did not match the requested bounded limits.'
      fi
      if [[ "${cpu_throttled:-0}" =~ ^[0-9]+$ ]] && (( cpu_throttled > 0 )); then pass 'CFS reported throttled periods for the CPU-limited process.'; else fail 'CPU quota did not report any throttled period during the bounded sample.'; fi
    else
      missing 'post-allocation cgroup memory/pids counters were unavailable.'
    fi
    if timeout 10s systemctl stop "$UNIT"; then pass 'systemctl stopped the bounded transient service.'; else status=$?; fail "systemctl stop failed or timed out (exit=$status)."; fi
    if stopped_state=$(systemctl show --property=ActiveState --value "$UNIT"); then
      if [[ "$stopped_state" == inactive || "$stopped_state" == failed ]]; then pass "transient service reached $stopped_state after stop."; else fail "transient service state after stop was ${stopped_state:-empty}."; fi
    else status=$?; fail "could not verify transient service stop (exit=$status)."; fi
    if [[ -n "$CONTROL_GROUP" ]]; then
      for ((attempt = 1; attempt <= 20; attempt++)); do [[ ! -e "/sys/fs/cgroup$CONTROL_GROUP" ]] && break; sleep 0.1; done
      if [[ ! -e "/sys/fs/cgroup$CONTROL_GROUP" ]]; then pass 'transient cgroup directory was removed after service stop.'; else fail 'transient cgroup directory remained after service stop.'; fi
    fi
  else
    fail "bounded transient service did not become active (state=${active_state:-unknown})."
  fi
fi

section 'Lab 03 cleanup and result'
if cleanup; then pass 'transient unit and process cleanup verified.'; else fail 'transient service cleanup was incomplete.'; fi
trap - EXIT
if (( ERRORS > 0 )); then printf 'LAB 03 STATUS=FAIL; required checks failed=%s.\n' "$ERRORS"; exit 1; fi
if (( MISSING > 0 )); then printf 'LAB 03 STATUS=UNKNOWN; required evidence is missing (exit=2).\n'; exit 2; fi
printf 'LAB 03 STATUS=PASS; performance diagnostics and bounded CPU/memory cgroup exercise completed.\n'
