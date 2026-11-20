#!/usr/bin/env bash
# Small phase-aware validator. Exit 1=required failure; 2=required evidence missing.
set -uo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FAILED=0
MISSING=0
WARNING_COUNT=0
UNKNOWN_COUNT=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILED=$((FAILED + 1)); }
missing() { printf 'UNKNOWN: %s\n' "$1"; MISSING=$((MISSING + 1)); UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)); }
warning() { printf 'WARNING: %s\n' "$1"; WARNING_COUNT=$((WARNING_COUNT + 1)); }
not_tested() { printf 'NOT TESTED: %s\n' "$1"; }
deferred() { printf 'DEFERRED: %s\n' "$1"; }
required_file() {
  if [[ -f "$ROOT/$1" ]]; then pass "required file $1 exists"; else missing "required file $1 is absent"; fi
}
required_executable() {
  if [[ -x "$ROOT/$1" ]]; then pass "executable bit set on $1"; else fail "required executable bit is missing on $1"; fi
}
run_gate() {
  local name=$1 status
  shift
  if "$@"; then
    pass "$name"
  else
    status=$?
    if [[ "$status" == 2 ]]; then missing "$name: required evidence is missing (exit=2)"; else fail "$name (exit=$status)"; fi
  fi
}

path_is_forbidden() {
  local path=$1
  case "$path" in
    .env|.env.*|*/.env|*/.env.*)
      [[ "$path" == .env.example || "$path" == */.env.example ]] || return 0
      ;;
    *.pem|*.key|*.ppk|*.p12|*.pfx|id_rsa*|id_ed25519*|id_ecdsa*|id_dsa*|*/id_rsa*|*/id_ed25519*|*/id_ecdsa*|*/id_dsa*|ssh_host_*_key|*/ssh_host_*_key) return 0 ;;
    kubeconfig|*/kubeconfig|*.kubeconfig|.kube/*|*/.kube/*|admin.conf|*/admin.conf|rke2.yaml|*/rke2.yaml) return 0 ;;
    inventory.local*|*/inventory.local*|raw-inventory*|*/raw-inventory*|preflight-raw*|security-baseline-raw*) return 0 ;;
    backups/*|backup/*|*/backups/*|*/backup/*|docs/evidence/*|*/docs/evidence/*|.terraform/*|*/.terraform/*) return 0 ;;
    *.log|*.log.*|*.out|*.trace|*.backup|*.backup.*|*.bak|*.bak.*|*.dump|*.sql.gz|*.tar.gz|*.tgz|*.tfstate|*.tfstate.*|*.tfvars|*.tfvars.json|crash.log) return 0 ;;
  esac
  return 1
}

repo_check() {
  local script path tracked
  for path in README.md AGENTS.md .gitignore docs/progress.md docs/infrastructure.md docs/resource-budget.md docs/architecture.md docs/roadmap.md docs/troubleshooting.md docs/runbooks/phase-0-preflight.md docs/runbooks/ssh-hardening.md .agents/skills/vps-linux-lab/SKILL.md labs/01-linux/README.md labs/02-linux/README.md applications/dotnet-sample-api/README.md scripts/preflight.sh scripts/security-baseline.sh scripts/lab01-readonly.sh scripts/lab02-systemd.sh scripts/validate.sh scripts/run-remote.ps1 .github/workflows/validate.yml; do
    required_file "$path"
  done
  for script in "$ROOT"/scripts/*.sh; do
    [[ -f "$script" ]] || continue
    if bash -n "$script"; then pass "bash -n $(basename "$script")"; else status=$?; fail "bash -n $(basename "$script") exit=$status"; fi
    if [[ -x "$script" ]]; then pass "executable bit set on scripts/$(basename "$script")"; else fail "scripts/$(basename "$script") is not executable"; fi
  done
  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ROOT"/scripts/*.sh; then pass 'ShellCheck scripts/*.sh'; else status=$?; fail "ShellCheck scripts/*.sh exit=$status"; fi
  else
    not_tested 'ShellCheck is not installed locally; CI installs its pinned Ubuntu package.'
  fi
  if tracked=$(git -C "$ROOT" ls-files); then
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      if path_is_forbidden "$path"; then fail "forbidden tracked path: $path"; fi
    done <<< "$tracked"
    pass 'tracked-path credential, inventory, raw-log and backup guard'
  else
    status=$?
    missing "git ls-files unavailable or failed (exit=$status)"
  fi
}

phase0_check() {
  run_gate 'read-only VPS preflight inventory' "$ROOT/scripts/preflight.sh"
  run_gate 'read-only security baseline inventory' "$ROOT/scripts/security-baseline.sh"
  warning 'Phase 0 inventory completion does not mean provider firewall or public-service security passed.'
}

lab01_check() {
  run_gate 'bounded Lab 01 permissions exercise and inventory' "$ROOT/scripts/lab01-readonly.sh" --permissions-demo
}

lab02_check() {
  run_gate 'bounded Lab 02 systemd, journal and signal exercise' "$ROOT/scripts/lab02-systemd.sh" --exercise
}

public_services_check() {
  local evidence=${PUBLIC_SERVICES_EVIDENCE_FILE:-$ROOT/docs/evidence/public-services.env}
  local key value line found missing_fields=0 failed_fields=0 unknown_fields=0
  local required_keys=(SSH_KEY_ONLY SSH_SERVER_AUTH HOST_FIREWALL PROVIDER_FIREWALL CONSOLE_RECOVERY)
  if [[ ! -f "$evidence" ]]; then
    missing "public-service security evidence file is absent: docs/evidence/public-services.env"
    deferred 'public-service deployment until required security evidence is recorded'
    return
  fi
  for key in "${required_keys[@]}"; do
    value=''
    found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=${line%$'\r'}
      [[ "$line" =~ ^[[:space:]]*# || -z "${line//[[:space:]]/}" ]] && continue
      if [[ "$line" =~ ^${key}=([A-Z_]+)$ ]]; then value=${BASH_REMATCH[1]}; found=1; fi
    done < "$evidence"
    if [[ "$found" == 0 ]]; then
      missing "public-service evidence $key is absent or malformed"
      missing_fields=$((missing_fields + 1))
    elif [[ "$value" == PASS ]]; then
      pass "public-service evidence $key=PASS"
    elif [[ "$value" == FAIL ]]; then
      fail "public-service evidence $key=FAIL"
      failed_fields=$((failed_fields + 1))
    else
      printf '%s: %s\n' "$key" "$value"
      missing "public-service evidence $key is $value, not PASS"
      unknown_fields=$((unknown_fields + 1))
    fi
  done
  if (( missing_fields + unknown_fields > 0 )); then deferred 'public-service deployment until required security evidence is complete'; fi
  if (( failed_fields > 0 )); then printf 'Public-service gate has %s failed field(s).\n' "$failed_fields"; fi
}

usage() {
  printf 'Usage: %s {repo|phase-0|lab-01|lab-02|public-services}\n' "${0##*/}" >&2
  exit 2
}

[[ $# == 1 ]] || usage
case "$1" in
  repo) repo_check ;;
  phase-0) phase0_check ;;
  lab-01) lab01_check ;;
  lab-02) lab02_check ;;
  public-services) public_services_check ;;
  *) usage ;;
esac

printf '\nValidation summary: FAIL=%s UNKNOWN=%s WARNING=%s\n' "$FAILED" "$UNKNOWN_COUNT" "$WARNING_COUNT"
if (( FAILED > 0 )); then exit 1; fi
if (( MISSING > 0 )); then exit 2; fi
exit 0
