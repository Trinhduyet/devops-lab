#!/usr/bin/env bash
# Lab 05: read-only filesystem, inode, mount and block-device observations.
set -uo pipefail
export LC_ALL=C

ERRORS=0
MISSING=0

section() { printf '\n===== %s =====\n' "$1"; }
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; ERRORS=$((ERRORS + 1)); }
missing() { printf 'UNKNOWN: %s\n' "$1"; MISSING=$((MISSING + 1)); }
not_tested() { printf 'NOT TESTED: %s\n' "$1"; }

section 'Read-only storage prerequisites'
for command_name in lsblk findmnt df stat du timeout awk sort sleep; do
  if command -v "$command_name" >/dev/null 2>&1; then printf 'AVAILABLE: %s\n' "$command_name"; else missing "required storage diagnostic command is unavailable: $command_name."; fi
done
if [[ ! -r /proc/diskstats ]]; then missing '/proc/diskstats is unavailable.'; fi
if (( MISSING > 0 )); then printf 'LAB 05 STATUS=UNKNOWN; required diagnostics are unavailable (exit=2).\n'; exit 2; fi

section 'Block-device topology (identifiers omitted)'
if block_summary=$(lsblk -bdn -o TYPE,SIZE,ROTA,FSTYPE); then
  if [[ -n "$block_summary" ]]; then
    awk '{printf "device-type=%s size-bytes=%s rotational-flag=%s filesystem=%s\n",$1,$2,$3,($4==""?"none":$4)}' <<< "$block_summary"
    pass 'lsblk returned block-device topology without device names, serials or UUIDs.'
  else missing 'lsblk returned no block-device summary.'; fi
else status=$?; missing "lsblk query failed (exit=$status)."; fi

section 'Mounts, filesystem capacity and inodes'
if root_mount=$(findmnt -n -T / -o TARGET,FSTYPE,OPTIONS); then printf 'root mount: %s\n' "$root_mount"; else status=$?; missing "findmnt root query failed (exit=$status)."; fi
if root_df=$(df -P -T / | awk 'NR==2 {printf "filesystem-type=%s blocks=%s used=%s available=%s use-percent=%s mount=%s\n",$2,$3,$4,$5,$6,$7; found=1} END{if(!found)exit 1}'); then printf '%s\n' "$root_df"; else status=$?; missing "root filesystem capacity query failed (exit=$status)."; fi
if root_inode=$(df -P -i / | awk 'NR==2 {printf "inodes-total=%s inodes-used=%s inodes-free=%s use-percent=%s mount=%s\n",$2,$3,$4,$5,$6; found=1} END{if(!found)exit 1}'); then printf '%s\n' "$root_inode"; else status=$?; missing "root inode query failed (exit=$status)."; fi
if filesystem=$(stat -f -c 'type=%T block-size=%S blocks=%b free-blocks=%f available-blocks=%a total-inodes=%c free-inodes=%d' /); then printf 'stat filesystem: %s\n' "$filesystem"; else status=$?; missing "stat filesystem query failed (exit=$status)."; fi
if usage=$(timeout 10s du -x -s /var/log /var/cache /tmp 2>/dev/null); then awk '{printf "bounded directory usage: %s blocks=%s\n",$2,$1}' <<< "$usage"; else status=$?; not_tested "du directory sample unavailable or exceeded 10s (exit=$status)."; fi

section 'Block I/O counters and sample semantics'
disk_counters() {
  local name reads sectors_read read_ms writes sectors_write write_ms io_ms
  while read -r _ _ name reads _ sectors_read read_ms writes _ sectors_write write_ms _ io_ms _; do
    [[ -e "/sys/block/$name" ]] || continue
    case "$name" in loop*|ram*|dm-*) continue ;; esac
    printf '%s %s %s %s %s %s %s\n' "$reads" "$sectors_read" "$read_ms" "$writes" "$sectors_write" "$write_ms" "$io_ms"
  done < /proc/diskstats
}
disk_before=$(disk_counters)
if [[ -z "$disk_before" ]]; then not_tested 'no whole-device disk counters were exposed for this sample.'; else
  sleep 1
  disk_after=$(disk_counters)
  if [[ -n "$disk_after" ]]; then
    awk -v before="$disk_before" -v after="$disk_after" 'BEGIN {nb=split(before,b,"\n"); na=split(after,a,"\n"); n=(nb<na?nb:na); for(i=1;i<=n;i++){split(b[i],old);split(a[i],new);reads+=new[1]-old[1];rsec+=new[2]-old[2];rms+=new[3]-old[3];writes+=new[4]-old[4];wsec+=new[5]-old[5];wms+=new[6]-old[6];busy+=new[7]-old[7]} printf "approximately 1s: read IOPS=%.1f write IOPS=%.1f read MB/s=%.3f write MB/s=%.3f\n",reads,writes,rsec*512/1000000,wsec*512/1000000; if(reads>=10)printf "mean completed-read latency=%.3f ms\n",rms/reads;else print "read latency=NOT TESTED (<10 completed reads; too few operations)";if(writes>=10)printf "mean completed-write latency=%.3f ms\n",wms/writes;else print "write latency=NOT TESTED (<10 completed writes; too few operations)";printf "device busy-counter delta=%d ms; multi-device sum is not normalized utilization\n",busy}'
  else missing 'second /proc/diskstats sample returned no counters.'; fi
fi
printf 'diskstats counters are cumulative; no synthetic disk I/O was generated.\n'

section 'LVM and storage mutation boundary'
if command -v pvs >/dev/null 2>&1; then not_tested 'LVM is installed; do not run pvs/vgs/lvs without a separate read-only review.'; else printf 'LVM tools are absent; no physical or logical volume was created.\n'; fi
printf 'No mount, unmount, partition, format, filesystem repair, LVM or disk write was performed.\n'

section 'Lab 05 result'
printf 'Read-only storage lab; failed required probes=%s, unavailable required results=%s.\n' "$ERRORS" "$MISSING"
if (( ERRORS > 0 )); then printf 'LAB 05 STATUS=FAIL.\n'; exit 1; fi
if (( MISSING > 0 )); then printf 'LAB 05 STATUS=UNKNOWN (exit=2).\n'; exit 2; fi
printf 'LAB 05 STATUS=PASS; filesystem and storage observations completed without mutation.\n'
