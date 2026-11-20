#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_DIR=$(mktemp -d /tmp/devops-validator-test.XXXXXX)
cleanup() { rm -f -- "$TEST_DIR/bin/sshd" "$TEST_DIR/bin/ufw" "$TEST_DIR/evidence.env" "$TEST_DIR/output.txt"; rmdir -- "$TEST_DIR/bin" && rmdir -- "$TEST_DIR"; }
trap cleanup EXIT
mkdir -p "$TEST_DIR/bin"
umask 077

cat > "$TEST_DIR/bin/sshd" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -t ]]; then exit 0; fi
if [[ "${1:-}" == -T && "${2:-}" == -C ]]; then
  printf 'pubkeyauthentication yes\n'
  printf 'passwordauthentication %s\n' "${MOCK_SSHD_PASSWORD:-no}"
  printf 'permitrootlogin prohibit-password\n'
  printf 'kbdinteractiveauthentication no\n'
elif [[ "${1:-}" == -T ]]; then
  printf 'usedns no\n'
else
  exit 64
fi
SH
cat > "$TEST_DIR/bin/ufw" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" != status ]]; then exit 64; fi
if [[ "${2:-}" == verbose ]]; then
  printf 'Status: active\nDefault: deny (incoming), allow (outgoing), disabled (routed)\n'
else
  printf '22/tcp ALLOW IN Anywhere\n'
fi
SH
chmod 700 "$TEST_DIR/bin/sshd" "$TEST_DIR/bin/ufw"

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
stale=$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)

run_gate_case() {
  local name=$1 expected=$2
  shift 2
  local output status
  set +e
  output=$(env PATH="$TEST_DIR/bin:$PATH" SSH_CONNECTION='127.0.0.1 40000 127.0.0.1 22' PUBLIC_SERVICES_SSH_KEY_VERIFIED=PASS PUBLIC_SERVICES_EVIDENCE_FILE="$TEST_DIR/evidence.env" "$@" bash "$ROOT/scripts/validate.sh" public-services 2>&1)
  status=$?
  set -e
  if [[ "$status" != "$expected" ]]; then printf 'FAIL: %s expected exit %s, got %s.\n' "$name" "$expected" "$status" >&2; exit 1; fi
  printf 'PASS: evidence gate scenario %s returned exit %s.\n' "$name" "$status"
  printf '%s\n' "$output" > "$TEST_DIR/output.txt"
}

printf 'PROVIDER_FIREWALL=PASS,MANUAL,%s\nCONSOLE_RECOVERY=PASS,MANUAL,%s\n' "$now" "$now" > "$TEST_DIR/evidence.env"
run_gate_case fresh-manual-evidence 0

printf 'PROVIDER_FIREWALL=PASS,MANUAL,%s\nPROVIDER_FIREWALL=PASS,MANUAL,%s\nCONSOLE_RECOVERY=PASS,MANUAL,%s\n' "$now" "$now" "$now" > "$TEST_DIR/evidence.env"
run_gate_case duplicate-key 1
grep -Fq 'duplicate public-service evidence key' "$TEST_DIR/output.txt"

printf 'PROVIDER_FIREWALL=PASS\nCONSOLE_RECOVERY=PASS,MANUAL,%s\n' "$now" > "$TEST_DIR/evidence.env"
run_gate_case malformed-record 1
if grep -Fq 'PASS: PROVIDER_FIREWALL' "$TEST_DIR/output.txt"; then printf 'FAIL: malformed evidence produced a PASS.\n' >&2; exit 1; fi

printf 'PROVIDER_FIREWALL=PASS,MANUAL,%s\nCONSOLE_RECOVERY=PASS,MANUAL,%s\n' "$stale" "$now" > "$TEST_DIR/evidence.env"
run_gate_case stale-manual-evidence 2
if grep -Fq 'PASS: PROVIDER_FIREWALL' "$TEST_DIR/output.txt"; then printf 'FAIL: stale evidence produced a PASS.\n' >&2; exit 1; fi

printf 'PROVIDER_FIREWALL=PASS,MANUAL,%s\nCONSOLE_RECOVERY=PASS,MANUAL,%s\n' "$now" "$now" > "$TEST_DIR/evidence.env"
run_gate_case live-host-state-overrides-recorded-status 1 env MOCK_SSHD_PASSWORD=yes
grep -Fq 'live sshd Match/Include-resolved policy does not meet' "$TEST_DIR/output.txt"

printf 'PROVIDER_FIREWALL=PASS,VPS_LIVE,%s\nCONSOLE_RECOVERY=PASS,MANUAL,%s\n' "$now" "$now" > "$TEST_DIR/evidence.env"
run_gate_case wrong-evidence-provenance 1
