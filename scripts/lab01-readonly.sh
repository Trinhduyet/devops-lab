#!/usr/bin/env bash
# Linux fundamentals inventory and an optional disposable permissions exercise.
set -uo pipefail
export LC_ALL=C
ERRORS=0
OPTIONAL_SKIPS=0
demo_dir=''

section() { printf '\n===== %s =====\n' "$1"; }
run() {
  local status
  printf '\n$'; printf ' %q' "$@"; printf '\n'
  if "$@" 2>&1; then printf '[probe=OK]\n'; else status=$?; printf '[probe=FAILED exit=%s]\n' "$status"; ERRORS=$((ERRORS + 1)); fi
}
cleanup_demo() {
  [[ -n "$demo_dir" ]] || return 0
  case "$demo_dir" in
    /tmp/devops-lab01.*)
      rm -f -- "$demo_dir/sample.txt" || return 1
      rmdir -- "$demo_dir" || return 1
      demo_dir=''
      printf 'CLEANUP PASS: disposable permission-demo directory removed.\n'
      ;;
    *) printf 'CLEANUP REFUSED: temporary directory did not match expected prefix.\n' >&2; return 1 ;;
  esac
}
trap 'cleanup_demo || ERRORS=$((ERRORS + 1))' EXIT

section 'Filesystem hierarchy and root filesystem'
run stat -c '%n type=%F owner=%U:%G mode=%a' / /etc /var /usr /home /root /tmp /proc /sys /dev /run /opt /srv
run findmnt -T /
run df -hT /

section 'Kernel and CPU architecture'
run uname -r
run uname -m
run getconf LONG_BIT
if command -v lscpu >/dev/null 2>&1; then
  if cpu=$(lscpu); then awk -F: '$1 ~ /^[[:space:]]*(Architecture|CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|Virtualization)$/ {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $1 ": " $2}' <<< "$cpu"; else status=$?; printf '[probe=FAILED lscpu exit=%s]\n' "$status"; ERRORS=$((ERRORS + 1)); fi
else printf '[NOT TESTED lscpu unavailable]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi

section 'Processes and threads'
if processes=$(ps -e --no-headers) && [[ -n "$processes" ]]; then printf 'process rows: %s\n' "$(wc -l <<< "$processes")"; else printf 'UNKNOWN: ps process inventory failed or returned empty output.\n'; ERRORS=$((ERRORS + 1)); fi
if threads=$(ps -eLf --no-headers) && [[ -n "$threads" ]]; then printf 'thread rows: %s\n' "$(wc -l <<< "$threads")"; else printf 'UNKNOWN: ps thread inventory failed or returned empty output.\n'; ERRORS=$((ERRORS + 1)); fi
if process_summary=$(ps -eo pid,ppid,nlwp,comm --sort=-nlwp); then printf 'highest-thread-count processes (top 12):\n'; head -n 13 <<< "$process_summary"; else status=$?; printf 'UNKNOWN: process summary failed (exit=%s).\n' "$status"; ERRORS=$((ERRORS + 1)); fi

section 'Current user, groups, UID/GID, and selected account records'
run id
if command -v getent >/dev/null 2>&1; then
  current_user=$(id -un)
  if passwd_entry=$(getent passwd "$current_user"); then awk -F: '{print "passwd entry: user=" $1 " uid=" $3 " gid=" $4 " shell=" $7}' <<< "$passwd_entry"; else status=$?; printf 'UNKNOWN: passwd lookup failed (exit=%s).\n' "$status"; ERRORS=$((ERRORS + 1)); fi
  if sudo_group=$(getent group sudo); then if [[ -n "$sudo_group" ]]; then awk -F: '{print "sudo group entry: name=" $1 " gid=" $3}' <<< "$sudo_group"; else printf 'sudo group entry: absent.\n'; fi; else status=$?; printf 'UNKNOWN: sudo group lookup failed (exit=%s).\n' "$status"; ERRORS=$((ERRORS + 1)); fi
else printf '[NOT TESTED getent unavailable]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi

section 'Permissions and ACL metadata'
run stat -c '%n owner=%U:%G mode=%a' / /etc/passwd /etc/shadow /tmp
if command -v getfacl >/dev/null 2>&1; then run getfacl -cp /etc/passwd /etc/shadow; else printf '[NOT TESTED getfacl unavailable; no package installed]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi

section 'Allowlisted environment variables and shell'
for variable in SHELL LANG TERM; do if [[ -v $variable ]]; then printf '%s=%s\n' "$variable" "${!variable}"; else printf '%s=<unset>\n' "$variable"; fi; done
printf 'UID=%s\n' "$(id -u)"
printf 'PATH component count=%s\n' "$(awk -v RS=: 'END{print NR}' <<< "${PATH:-}")"
if bash_version=$(bash --version); then head -n 1 <<< "$bash_version"; else status=$?; printf '[probe=FAILED bash --version exit=%s]\n' "$status"; ERRORS=$((ERRORS + 1)); fi

section 'Package architecture and package-management tools (no update/install)'
if command -v dpkg >/dev/null 2>&1; then run dpkg --print-architecture; else printf '[NOT TESTED dpkg unavailable]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi
if command -v apt-get >/dev/null 2>&1; then run apt-get --version; else printf '[NOT TESTED apt-get unavailable]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi
if command -v dpkg-query >/dev/null 2>&1; then run dpkg-query -W '-f=${binary:Package} ${Version}\n' bash libc6 systemd openssh-server; else printf '[NOT TESTED dpkg-query unavailable]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi
if command -v apt-cache >/dev/null 2>&1; then run apt-cache policy bash; else printf '[NOT TESTED apt-cache unavailable]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi

section 'Optional ACL package state (does not affect required package inventory)'
if command -v dpkg-query >/dev/null 2>&1; then
  if acl_package=$(dpkg-query -W '-f=${db:Status-Status} ${Version}\n' acl 2>/dev/null); then
    if [[ "$acl_package" == installed* ]]; then printf 'Optional package acl: %s\n' "$acl_package"; else printf '[NOT TESTED optional ACL package is not installed]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi
  else
    status=$?
    printf '[NOT TESTED optional ACL package query unavailable (exit=%s); required package inventory remains independent]\n' "$status"
    OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
  fi
else
  printf '[NOT TESTED optional ACL package query requires dpkg-query]\n'
  OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1))
fi

if [[ "${1:-}" == '--permissions-demo' ]]; then
  section 'Disposable /tmp permissions and ACL exercise'
  demo_dir=$(mktemp -d /tmp/devops-lab01.XXXXXX) || { printf 'FAIL: mktemp could not create the demo directory.\n'; exit 1; }
  if (umask 077; : > "$demo_dir/sample.txt"); then
    if default_mode=$(stat -c '%a' "$demo_dir/sample.txt"); then
      printf 'default mode with umask 077: %s\n' "$default_mode"
      if [[ "$default_mode" == 600 ]]; then printf 'PASS: umask produced mode 600.\n'; else printf 'FAIL: expected mode 600, observed %s.\n' "$default_mode"; ERRORS=$((ERRORS + 1)); fi
    else
      status=$?
      printf 'UNKNOWN: stat of temporary file failed (exit=%s).\n' "$status"
      ERRORS=$((ERRORS + 1))
    fi
  else
    status=$?
    printf 'FAIL: could not create temporary permission-demo file (exit=%s).\n' "$status"
    ERRORS=$((ERRORS + 1))
  fi
  if chmod 640 "$demo_dir/sample.txt"; then
    if chmod_mode=$(stat -c '%a' "$demo_dir/sample.txt"); then
      printf 'mode after chmod 640: %s\n' "$chmod_mode"
      if [[ "$chmod_mode" == 640 ]]; then printf 'PASS: chmod produced mode 640.\n'; else printf 'FAIL: expected mode 640, observed %s.\n' "$chmod_mode"; ERRORS=$((ERRORS + 1)); fi
    else
      status=$?
      printf 'UNKNOWN: stat after chmod failed (exit=%s).\n' "$status"
      ERRORS=$((ERRORS + 1))
    fi
  else
    status=$?
    printf 'FAIL: chmod 640 failed (exit=%s).\n' "$status"
    ERRORS=$((ERRORS + 1))
  fi
  if command -v setfacl >/dev/null 2>&1 && command -v getfacl >/dev/null 2>&1 && getent passwd nobody >/dev/null 2>&1; then
    run setfacl -m u:nobody:r-- "$demo_dir/sample.txt"
    run getfacl -cp "$demo_dir/sample.txt"
  else printf '[NOT TESTED setfacl/getfacl or nobody account unavailable; ACL write exercise skipped]\n'; OPTIONAL_SKIPS=$((OPTIONAL_SKIPS + 1)); fi
  if cleanup_demo; then trap - EXIT; else exit 1; fi
fi

section 'Inventory result'
printf 'Linux fundamentals inventory only; no package or system configuration was changed. Failed probes=%s; optional checks not tested=%s.\n' "$ERRORS" "$OPTIONAL_SKIPS"
if (( ERRORS > 0 )); then printf 'INVENTORY STATUS=INCOMPLETE.\n'; exit 1; fi
printf 'INVENTORY STATUS=COLLECTED (not a phase gate PASS).\n'
