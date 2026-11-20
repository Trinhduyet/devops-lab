#!/usr/bin/env bash
# Lab 02: inspect systemd/process state and run a bounded transient-service exercise.
set -uo pipefail
export LC_ALL=C

ERRORS=0
MISSING=0
UNIT=''
CHILD_PID=''
UNIT_STARTED=0

section() { printf '\n===== %s =====\n' "$1"; }
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; ERRORS=$((ERRORS + 1)); }
cleanup() {
  local cleanup_errors=0
  local state wait_status
  if [[ -n "$CHILD_PID" ]]; then
    if kill -0 "$CHILD_PID"; then
      if ! kill -TERM "$CHILD_PID"; then printf 'CLEANUP FAILED: could not signal child process.\n' >&2; cleanup_errors=$((cleanup_errors + 1)); fi
    else
      status=$?
      if [[ "$status" != 1 ]]; then printf 'CLEANUP FAILED: could not inspect child process (exit=%s).\n' "$status" >&2; cleanup_errors=$((cleanup_errors + 1)); fi
    fi
    if wait "$CHILD_PID"; then :; else wait_status=$?; if [[ "$wait_status" != 143 && "$wait_status" != 137 ]]; then printf 'CLEANUP WARNING: child wait status=%s.\n' "$wait_status" >&2; cleanup_errors=$((cleanup_errors + 1)); fi; fi
    CHILD_PID=''
  fi
  if [[ "$UNIT_STARTED" == 1 && -n "$UNIT" ]]; then
    if state=$(systemctl show --property=LoadState --value "$UNIT"); then
      if [[ "$state" == not-found ]]; then
        UNIT_STARTED=0
      elif [[ -z "$state" ]]; then
        printf 'CLEANUP FAILED: systemctl returned empty unit load state.\n' >&2
        cleanup_errors=$((cleanup_errors + 1))
      else
        if ! timeout 10s systemctl stop "$UNIT"; then printf 'CLEANUP FAILED: could not stop transient unit %s.\n' "$UNIT" >&2; cleanup_errors=$((cleanup_errors + 1)); fi
        if state=$(systemctl show --property=LoadState --value "$UNIT"); then
          if [[ "$state" != not-found && -n "$state" ]]; then
            if ! systemctl reset-failed "$UNIT"; then printf 'CLEANUP WARNING: could not reset transient unit state.\n' >&2; cleanup_errors=$((cleanup_errors + 1)); fi
          fi
        else
          status=$?
          printf 'CLEANUP FAILED: could not verify transient unit state (exit=%s).\n' "$status" >&2
          cleanup_errors=$((cleanup_errors + 1))
        fi
        UNIT_STARTED=0
      fi
    else
      status=$?
      printf 'CLEANUP FAILED: could not inspect transient unit load state (exit=%s).\n' "$status" >&2
      cleanup_errors=$((cleanup_errors + 1))
    fi
  fi
  return "$cleanup_errors"
}
trap 'cleanup || ERRORS=$((ERRORS + 1))' EXIT

section 'systemd, service and journal inventory'
for command_name in systemctl systemd-run journalctl ps sleep mktemp timeout; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'AVAILABLE: %s\n' "$command_name"
  else
    printf 'NOT TESTED: required command %s is unavailable.\n' "$command_name"
    MISSING=$((MISSING + 1))
  fi
done
if (( MISSING > 0 )); then
  printf 'LAB 02 STATUS=UNKNOWN; required command evidence is missing (exit=2).\n'
  exit 2
fi
if [[ "$(id -u)" != 0 ]]; then
  printf 'NOT TESTED: the transient system service exercise requires the system manager; run through the authorized root SSH alias.\n'
  printf 'LAB 02 STATUS=UNKNOWN; required service-manager access is missing (exit=2).\n'
  exit 2
fi
if systemd_version=$(systemd --version); then head -n 1 <<< "$systemd_version"; else status=$?; printf 'UNKNOWN: systemd --version failed (exit=%s).\n' "$status"; ERRORS=$((ERRORS + 1)); fi
if system_state=$(systemctl is-system-running); then
  printf 'systemd manager state: %s\n' "$system_state"
else
  status=$?
  case "$system_state" in
    degraded|maintenance|starting|stopping|offline|unknown) printf 'systemd manager state: %s (query exit=%s)\n' "$system_state" "$status" ;;
    *) printf 'UNKNOWN: systemctl is-system-running failed (exit=%s).\n' "$status"; ERRORS=$((ERRORS + 1)) ;;
  esac
fi
if failed_units=$(systemctl --failed --no-legend --no-pager); then
  if [[ -z "$failed_units" ]]; then printf 'Failed service units: 0\n'; else printf 'Failed service unit rows: %s\n' "$(wc -l <<< "$failed_units")"; fi
else
  status=$?
  printf 'UNKNOWN: failed-unit inventory failed (exit=%s).\n' "$status"
  ERRORS=$((ERRORS + 1))
fi
if journal_usage=$(journalctl --disk-usage); then printf '%s\n' "$journal_usage"; else status=$?; printf 'UNKNOWN: journal disk usage query failed (exit=%s).\n' "$status"; ERRORS=$((ERRORS + 1)); fi
if process_rows=$(ps -e --no-headers) && [[ -n "$process_rows" ]]; then printf 'Process count snapshot: %s\n' "$(wc -l <<< "$process_rows")"; else printf 'UNKNOWN: process inventory failed or was empty.\n'; ERRORS=$((ERRORS + 1)); fi

if [[ "${1:-}" != '--exercise' ]]; then
  section 'Inventory result'
  printf 'Inventory only; pass --exercise to start a bounded transient service and signal a child process.\n'
  if (( ERRORS > 0 )); then printf 'LAB 02 INVENTORY STATUS=INCOMPLETE.\n'; exit 1; fi
  printf 'LAB 02 INVENTORY STATUS=COLLECTED (not the hands-on lab gate).\n'
  exit 0
fi

section 'Bounded transient service lifecycle'
UNIT="devops-lab02-$(date -u +%Y%m%d%H%M%S)-$$.service"
case "$UNIT" in devops-lab02-[0-9]*.service) ;; *) fail 'generated unit name did not match the expected prefix.'; exit 1 ;; esac
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if systemd-run --quiet --unit="$UNIT" --property=RuntimeMaxSec=40s /bin/bash -c 'printf "%s\n" DEVOPS_LAB02_SERVICE_STARTED; exec /usr/bin/sleep 35'; then
  UNIT_STARTED=1
  pass 'transient service accepted by the systemd manager.'
else
  status=$?
  fail "systemd-run rejected the temporary service (exit=$status)."
fi

if [[ "$UNIT_STARTED" == 1 ]]; then
  active_state=''
  for attempt in {1..20}; do
    if active_state=$(systemctl show --property=ActiveState --value "$UNIT"); then
      [[ "$active_state" == active ]] && break
    else
      status=$?
      fail "systemctl could not inspect the transient unit (exit=$status)."
      break
    fi
    sleep 0.25
  done
  if [[ "$active_state" == active ]]; then
    main_pid=$(systemctl show --property=MainPID --value "$UNIT")
    pass "transient service reached ActiveState=active (MainPID=${main_pid:-unknown})."
    if service_metrics=$(systemctl show --property=ControlGroup --property=MemoryCurrent --property=CPUUsageNSec "$UNIT"); then
      if [[ -n "$service_metrics" ]]; then printf 'systemd service metrics:\n%s\n' "$service_metrics"; else fail 'systemd returned empty cgroup metrics.'; fi
    else
      status=$?
      fail "systemctl could not inspect cgroup metrics (exit=$status)."
    fi
    if [[ "$main_pid" =~ ^[1-9][0-9]*$ ]]; then
      if process_view=$(ps -o pid,ppid,stat,comm -p "$main_pid"); then printf '%s\n' "$process_view"; else status=$?; fail "ps could not inspect service process (exit=$status)."; fi
    else
      fail 'systemd did not report a positive MainPID.'
    fi
  else
    fail "transient service did not become active (last state=${active_state:-unknown})."
  fi

  marker_seen=0
  for attempt in {1..20}; do
    if service_log=$(journalctl --unit="$UNIT" --since="$started_at" --no-pager --output=cat); then
      if grep -Fqx 'DEVOPS_LAB02_SERVICE_STARTED' <<< "$service_log"; then marker_seen=1; break; fi
    else
      status=$?
      fail "journalctl could not inspect the temporary unit (exit=$status)."
      break
    fi
    sleep 0.25
  done
  if [[ "$marker_seen" == 1 ]]; then pass 'journalctl contains the exercise start marker.'; else fail 'journalctl start marker was not observed.'; fi

  if timeout 10s systemctl stop "$UNIT"; then
    if stopped_state=$(systemctl show --property=ActiveState --value "$UNIT"); then
      if [[ "$stopped_state" == inactive ]]; then pass 'systemctl stop returned success and ActiveState=inactive.'; else fail "service stop state was ${stopped_state:-empty}, expected inactive."; fi
    else
      status=$?
      fail "systemctl could not verify service stop (exit=$status)."
    fi
  else
    status=$?
    fail "systemctl stop failed or timed out (exit=$status)."
  fi
fi

section 'Process signals and wait status'
sleep 30 &
CHILD_PID=$!
child_name=''
attempt=0
while (( attempt < 40 )); do
  attempt=$((attempt + 1))
  if [[ -r "/proc/$CHILD_PID/comm" ]]; then IFS= read -r child_name < "/proc/$CHILD_PID/comm"; [[ "$child_name" == sleep ]] && break; fi
  sleep 0.05
done
if [[ "$child_name" != sleep ]]; then
  fail "temporary child did not become the expected sleep process (comm=${child_name:-unknown})."
elif kill -TERM "$CHILD_PID"; then
  if wait "$CHILD_PID"; then
    fail 'child process exited normally after SIGTERM; expected signal termination.'
  else
    child_status=$?
    if [[ "$child_status" == 143 ]]; then pass 'SIGTERM delivered; Bash wait status was 143.'; else fail "unexpected child wait status after SIGTERM: $child_status."; fi
  fi
  CHILD_PID=''
else
  status=$?
  fail "kill -TERM failed for the exercise child (exit=$status)."
fi

section 'Cleanup and result'
if cleanup; then
  pass 'temporary child process and transient service cleanup completed.'
else
  fail 'temporary resource cleanup was incomplete; inspect the named unit/process.'
fi
trap - EXIT
if (( ERRORS > 0 )); then
  printf 'LAB 02 STATUS=FAIL; required checks failed=%s.\n' "$ERRORS"
  exit 1
fi
printf 'LAB 02 STATUS=PASS; bounded systemd, journal, process and signal checks completed.\n'
