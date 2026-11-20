#!/usr/bin/env bash
# Read-only VPS inventory. This is not a phase-gate validator.
# No package installation, service changes, network probes, or configuration writes.
set -uo pipefail
export LC_ALL=C

ERRORS=0
OPTIONAL_SKIPS=0

section() { printf '\n===== %s =====\n' "$1"; }

run() {
  local status
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'
  if "$@"; then
    printf '[probe=OK]\n'
  else
    status=$?
    printf '[probe=FAILED exit=%s]\n' "$status"
    ERRORS=$((ERRORS + 1))
  fi
}

optional() {
  if command -v "$1" >/dev/null 2>&1; then
    run "$@"
  else
    printf '\n[NOT TESTED command unavailable: %s]\n' "$1"
    OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
  fi
}

section 'Identity and operating system'
optional id
optional hostnamectl --static
optional cat /etc/os-release
optional uname -r
optional uname -m
optional timedatectl status

section 'CPU and memory'
optional lscpu
optional free -h
optional uptime
optional swapon --show
optional vmstat -s

section 'Storage and filesystems'
optional lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,ROTA
optional df -hT
optional df -ih
optional findmnt -D

section 'Virtualization, cgroups and kernel features'
optional systemd-detect-virt
optional systemd-detect-virt --vm
optional cat /proc/1/cgroup
optional cat /sys/fs/cgroup/cgroup.controllers
optional grep -E '(^nodev[[:space:]]+overlay$|^nodev[[:space:]]+cgroup2?$)' /proc/filesystems
optional sysctl kernel.pid_max vm.max_map_count fs.inotify.max_user_instances fs.inotify.max_user_watches
optional modinfo -F filename overlay
optional modinfo -F filename br_netfilter
if command -v grep >/dev/null 2>&1 && [[ -r /proc/modules ]]; then
  if grep -E '^(overlay|br_netfilter) ' /proc/modules; then
    printf '[observation=module loaded]\n'
  else
    printf '[observation=no matching module currently loaded]\n'
  fi
else
  printf '[NOT TESTED module list unavailable]\n'
  OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
fi
optional sysctl net.ipv4.ip_forward
if command -v sysctl >/dev/null 2>&1; then
  if bridge_sysctl=$(sysctl net.bridge.bridge-nf-call-iptables 2>&1); then
    printf '%s\n' "$bridge_sysctl"
  else
    status=$?
    case "$bridge_sysctl" in
      *'No such file or directory'*)
        printf '[NOT TESTED bridge netfilter sysctl is not exposed by this kernel (query exit=%s): %s]\n' "$status" "$bridge_sysctl"
        OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
        ;;
      *)
        printf '[probe=FAILED sysctl net.bridge.bridge-nf-call-iptables exit=%s]: %s\n' "$status" "$bridge_sysctl"
        ERRORS=$((ERRORS + 1))
        ;;
    esac
  fi
else
  printf '[NOT TESTED sysctl unavailable]\n'
  OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
fi

section 'Network addresses, routes and DNS'
optional ip -br address
optional ip route show table main
optional ip -6 route show table main
if command -v getent >/dev/null 2>&1 && command -v hostname >/dev/null 2>&1; then
  optional sh -c "host=\$(hostname -f) && getent ahosts \"\$host\""
else
  printf '[NOT TESTED DNS lookup requires getent and hostname]\n'
  OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
fi

section 'Listening ports and firewall status'
optional ss -lntup
optional ufw status verbose
optional ufw show added
if command -v systemctl >/dev/null 2>&1; then
  for unit in firewalld nftables; do
    if state=$(systemctl is-active "$unit"); then
      printf 'systemd.%s=%s [state observation]\n' "$unit" "$state"
    else
      status=$?
      case "$state" in
        inactive|unknown|failed)
          printf 'systemd.%s=%s [state observation, query exit=%s]\n' "$unit" "$state" "$status"
          ;;
        *)
          printf 'systemd.%s=UNKNOWN [query failed exit=%s]\n' "$unit" "$status"
          ERRORS=$((ERRORS + 1))
          ;;
      esac
    fi
  done
else
  printf '[NOT TESTED systemctl unavailable]\n'
  OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
fi
optional nft list tables
optional iptables -S
optional ip6tables -S

section 'Services and container tooling'
if command -v systemctl >/dev/null 2>&1; then
  if state=$(systemctl is-system-running); then
    printf 'systemd.state=%s [state observation]\n' "$state"
  else
    status=$?
    case "$state" in
      degraded|maintenance|starting|stopping|offline|unknown)
        printf 'systemd.state=%s [state observation, query exit=%s]\n' "$state" "$status"
        ;;
      *)
        printf 'systemd.state=UNKNOWN [query failed exit=%s]\n' "$status"
        ERRORS=$((ERRORS + 1))
        ;;
    esac
  fi
  optional systemctl --failed --no-pager
else
  printf '[NOT TESTED systemctl unavailable]\n'
  OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
fi
optional docker version
optional docker compose version
optional containerd --version
optional ctr version
optional crictl version
optional kubectl version --client

section 'Inventory result'
printf 'INVENTORY ONLY: collected observations; phase gates were not validated. Failed probes=%s; optional checks not tested=%s.\n' "$ERRORS" "$OPTIONAL_SKIPS"
if (( ERRORS > 0 )); then
  printf 'INVENTORY STATUS=INCOMPLETE (inspect failed probes; do not infer PASS from partial output).\n'
  exit 1
fi
printf 'INVENTORY STATUS=COLLECTED (not a security or deployment PASS).\n'
