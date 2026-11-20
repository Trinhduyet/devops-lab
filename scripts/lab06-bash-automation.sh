#!/usr/bin/env bash
# Lab 06: bounded Bash automation exercise for quoting, atomic replacement and status handling.
set -euo pipefail
export LC_ALL=C
umask 077

ERRORS=0
DEMO_DIR=''

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; ERRORS=$((ERRORS + 1)); }

cleanup_demo() {
  [[ -n "$DEMO_DIR" ]] || return 0
  if [[ ! "$DEMO_DIR" =~ ^/tmp/devops-lab06\.[A-Za-z0-9]{6}$ ]]; then
    printf 'CLEANUP REFUSED: temporary path is outside the expected exact pattern.\n' >&2
    return 1
  fi
  local path cleanup_errors=0
  for path in "$DEMO_DIR/state.env" "$DEMO_DIR/data file.txt" "$DEMO_DIR"/.atomic.*; do
    if [[ -e "$path" ]]; then
      if ! rm -f -- "$path"; then printf 'CLEANUP FAILED: could not remove a file in the exact lab directory.\n' >&2; cleanup_errors=$((cleanup_errors + 1)); fi
    fi
  done
  if (( cleanup_errors == 0 )); then
    if ! rmdir -- "$DEMO_DIR"; then printf 'CLEANUP FAILED: exact lab directory is not empty or could not be removed.\n' >&2; cleanup_errors=$((cleanup_errors + 1)); fi
  fi
  if (( cleanup_errors == 0 )) && [[ ! -e "$DEMO_DIR" ]]; then
    DEMO_DIR=''
    printf 'PASS: exact /tmp exercise directory and generated files removed.\n'
    return 0
  fi
  return 1
}
trap 'cleanup_demo || ERRORS=$((ERRORS + 1))' EXIT

printf '===== Bounded Bash automation exercise =====\n'
DEMO_DIR=$(mktemp -d /tmp/devops-lab06.XXXXXX)
if [[ ! "$DEMO_DIR" =~ ^/tmp/devops-lab06\.[A-Za-z0-9]{6}$ ]]; then fail 'mktemp returned an unexpected directory path.'; exit 1; fi
if [[ "$(stat -c '%a' "$DEMO_DIR")" == 700 ]]; then pass 'umask 077 created a private mode-700 directory.'; else fail 'temporary directory permissions were not 700.'; fi

write_state_atomically() {
  local target=$1 temporary
  temporary=$(mktemp "$DEMO_DIR/.atomic.XXXXXX")
  printf 'mode=lab\nrevision=1\n' > "$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$target"
}

target="$DEMO_DIR/state.env"
write_state_atomically "$target"
first_hash=$(sha256sum "$target" | awk '{print $1}')
write_state_atomically "$target"
second_hash=$(sha256sum "$target" | awk '{print $1}')
if [[ "$first_hash" == "$second_hash" && "$(stat -c '%a' "$target")" == 600 ]]; then
  pass 'repeating the atomic write is idempotent and preserves mode 600.'
else
  fail 'repeated atomic write changed content hash or file mode.'
fi

message="argument with spaces * \$HOME"
sample="$DEMO_DIR/data file.txt"
printf '%s\n' "$message" > "$sample"
if IFS= read -r observed < "$sample" && [[ "$observed" == "$message" ]]; then pass 'quoted argument preserved spaces and literal shell metacharacters without eval.'; else fail 'quoted argument did not round-trip exactly.'; fi

set +e
bash -c 'exit 7'
child_status=$?
set -e
if [[ "$child_status" == 7 ]]; then pass 'child exit status 7 was captured and handled explicitly.'; else fail "child exit status expected 7, observed $child_status."; fi

printf 'exercise files bytes=%s; files remain private under umask 077 until cleanup.\n' "$(wc -c < "$sample")"
if (( ERRORS > 0 )); then printf 'LAB 06 STATUS=FAIL.\n'; exit 1; fi
if cleanup_demo; then trap - EXIT; else fail 'temporary-file cleanup failed.'; trap - EXIT; exit 1; fi
printf 'LAB 06 STATUS=PASS; Bash quoting, atomic write, idempotency, exit status and cleanup verified.\n'
