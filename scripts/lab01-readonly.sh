#!/usr/bin/env bash
# Linux fundamentals inventory and an optional disposable permissions exercise.
set -uo pipefail
export LC_ALL=C

section() { printf '\n===== %s =====\n' "$1"; }
run() {
  local status
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'
  "$@" 2>&1
  status=$?
  if [[ $status -ne 0 ]]; then printf '[exit=%s]\n' "$status"; fi
  return 0
}

section 'Filesystem hierarchy and root filesystem'
run stat -c '%n type=%F owner=%U:%G mode=%a' / /etc /var /usr /home /root /tmp /proc /sys /dev /run /opt /srv
run findmnt -T /
run df -hT /

section 'Kernel and CPU architecture'
run uname -r
run uname -m
run getconf LONG_BIT
if command -v lscpu >/dev/null 2>&1; then
  lscpu | awk -F: '$1 ~ /^[[:space:]]*(Architecture|CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|Virtualization)$/ {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $1 ": " $2}'
fi

section 'Processes and threads'
printf 'process rows: '
ps -e --no-headers 2>/dev/null | wc -l
printf 'thread rows: '
ps -eLf --no-headers 2>/dev/null | wc -l
printf 'highest-thread-count processes (top 12):\n'
ps -eo pid,ppid,nlwp,comm --sort=-nlwp 2>/dev/null | head -n 13

section 'Current user, groups, UID/GID, and selected account records'
run id
if command -v getent >/dev/null 2>&1; then
  current_user=$(id -un 2>/dev/null || printf root)
  getent passwd "$current_user" | awk -F: '{print "passwd entry: user=" $1 " uid=" $3 " gid=" $4 " shell=" $7}'
  getent group sudo | awk -F: '{print "sudo group entry: name=" $1 " gid=" $3}'
fi

section 'Permissions and ACL metadata'
run stat -c '%n owner=%U:%G mode=%a' / /etc/passwd /etc/shadow /tmp
if command -v getfacl >/dev/null 2>&1; then
  getfacl -cp /etc/passwd /etc/shadow 2>&1
else
  printf 'getfacl is unavailable; ACL utility was not installed.\n'
fi

section 'Allowlisted environment variables and shell'
for variable in SHELL LANG TERM; do
  if [[ -v $variable ]]; then printf '%s=%s\n' "$variable" "${!variable}"; else printf '%s=<unset>\n' "$variable"; fi
done
printf 'UID=%s\n' "$(id -u)"
printf 'PATH component count=%s\n' "$(awk -v RS=: 'END{print NR}' <<< "${PATH:-}")"
bash --version | head -n 1

section 'Package architecture and package-management tools (no update/install)'
if command -v dpkg >/dev/null 2>&1; then run dpkg --print-architecture; fi
if command -v apt-get >/dev/null 2>&1; then apt-get --version | head -n 1; else printf 'apt-get is unavailable.\n'; fi
if command -v dpkg-query >/dev/null 2>&1; then
  dpkg-query -W -f='${binary:Package} ${Version}\n' bash libc6 systemd openssh-server acl 2>/dev/null || true
fi
if command -v apt-cache >/dev/null 2>&1; then
  apt-cache policy bash 2>/dev/null | awk '/Installed:|Candidate:/{print}'
fi

if [[ "${1:-}" == "--permissions-demo" ]]; then
  section 'Disposable /tmp permissions and ACL exercise'
  demo_dir=$(mktemp -d /tmp/devops-lab01.XXXXXX) || exit 1
  cleanup_demo() {
    case "$demo_dir" in
      /tmp/devops-lab01.*)
        rm -f -- "$demo_dir/sample.txt"
        rmdir -- "$demo_dir" 2>/dev/null || true
        ;;
    esac
  }
  trap cleanup_demo EXIT
  (
    umask 077
    : > "$demo_dir/sample.txt"
  )
  printf 'default mode with umask 077: '
  stat -c '%a' "$demo_dir/sample.txt"
  chmod 640 "$demo_dir/sample.txt"
  printf 'mode after chmod 640: '
  stat -c '%a' "$demo_dir/sample.txt"
  if command -v setfacl >/dev/null 2>&1 && command -v getfacl >/dev/null 2>&1 && getent passwd nobody >/dev/null 2>&1; then
    setfacl -m u:nobody:r-- "$demo_dir/sample.txt"
    printf 'temporary ACL for nobody (file is removed on exit):\n'
    getfacl -cp "$demo_dir/sample.txt"
  else
    printf 'setfacl/getfacl or the nobody account is unavailable; ACL write exercise skipped.\n'
  fi
fi

printf '\nLinux fundamentals inventory complete. Package or system configuration was not changed.\n'
