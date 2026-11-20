#!/usr/bin/env bash
# Read-only VPS inventory for DevOps Infrastructure Lab.
# No package installation, service changes, network probes, or configuration writes.
set -u
export LC_ALL=C

section() {
  printf '\n===== %s =====\n' "$1"
}

run() {
  local status
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'
  "$@" 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    printf '[exit=%s]\n' "$status"
  fi
  return 0
}

optional() {
  if command -v "$1" >/dev/null 2>&1; then
    run "$@"
  else
    printf '\n[missing command: %s]\n' "$1"
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
optional sh -c 'grep -E "^(overlay|br_netfilter) " /proc/modules || true'
optional sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables

section 'Network addresses, routes and DNS'
optional ip -br address
optional ip route show table main
optional ip -6 route show table main
optional sh -c 'getent ahosts "$(hostname -f 2>/dev/null || hostname)"'

section 'Listening ports and firewall status'
optional ss -lntup
optional ufw status verbose
optional ufw show added
optional systemctl is-active firewalld
optional systemctl is-active nftables
optional nft list tables
optional iptables -S
optional ip6tables -S

section 'Services and container tooling'
optional systemctl is-system-running
optional systemctl --failed --no-pager
optional docker version
optional docker compose version
optional containerd --version
optional ctr version
optional crictl version

section 'End of read-only preflight'
printf 'No settings were changed. Review host/IP details before sharing this output.\n'
