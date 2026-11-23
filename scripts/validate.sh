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
section() { printf '\n===== %s =====\n' "$1"; }
required_file() {
  if [[ -s "$ROOT/$1" ]]; then pass "required file $1 exists and is non-empty"; else missing "required file $1 is absent or empty"; fi
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
    .env.example|*/.env.example) return 1 ;;
    .env|.env.*|*/.env|*/.env.*) return 0 ;;
    .ssh|.ssh/*|*/.ssh|*/.ssh/*) return 0 ;;
    *.pem|*.key|*.ppk|*.p12|*.pfx|id_rsa*|id_ed25519*|id_ecdsa*|id_dsa*|*/id_rsa*|*/id_ed25519*|*/id_ecdsa*|*/id_dsa*|ssh_host_*_key|*/ssh_host_*_key) return 0 ;;
    kubeconfig|*/kubeconfig|*.kubeconfig|.kube/*|*/.kube/*|admin.conf|*/admin.conf|rke2.yaml|*/rke2.yaml) return 0 ;;
    secrets/*|*/secrets/*|credentials/*|*/credentials/*) return 0 ;;
    inventory.local*|*/inventory.local*|raw-inventory*|*/raw-inventory*|preflight-raw*|*/preflight-raw*|security-baseline-raw*|*/security-baseline-raw*) return 0 ;;
    backups/*|backup/*|*/backups/*|*/backup/*|docs/evidence/*|*/docs/evidence/*|.terraform/*|*/.terraform/*) return 0 ;;
    *.log|*.log.*|*.out|*.trace|*.backup|*.backup.*|*.bak|*.bak.*|*.dump|*.sql.gz|*.tar.gz|*.tgz|*.tfstate|*.tfstate.*|*.tfvars|*.tfvars.json) return 0 ;;
    bin/*|*/bin/*|obj/*|*/obj/*|.DS_Store|*/.DS_Store|Thumbs.db|*/Thumbs.db) return 0 ;;
  esac
  return 1
}

repo_check() {
  local script path tracked path_violations=0 policy_ok=1
  for path in README.md AGENTS.md .gitignore docs/progress.md docs/infrastructure.md docs/resource-budget.md docs/architecture.md docs/roadmap.md docs/troubleshooting.md docs/runbooks/phase-0-preflight.md docs/runbooks/ssh-hardening.md .agents/skills/vps-linux-lab/SKILL.md .agents/skills/container-runtime-lab/SKILL.md labs/01-linux/README.md labs/02-linux/README.md labs/03-linux/README.md labs/04-linux/README.md labs/05-linux/README.md labs/06-linux/README.md labs/07-docker-engine/README.md labs/08-docker-networking/README.md labs/09-docker-storage/README.md labs/10-dotnet-api/README.md labs/11-containerd/README.md applications/dotnet-sample-api/README.md applications/dotnet-sample-api/.dockerignore applications/dotnet-sample-api/DevOpsLab.SampleApi.csproj applications/dotnet-sample-api/Program.cs applications/dotnet-sample-api/Dockerfile applications/dotnet-sample-api/compose.yaml applications/dotnet-sample-api/tests/smoke.ps1 scripts/preflight.sh scripts/security-baseline.sh scripts/lab01-readonly.sh scripts/lab02-systemd.sh scripts/lab03-performance.sh scripts/lab04-networking.sh scripts/lab05-storage.sh scripts/lab06-bash-automation.sh scripts/test-dotnet-api.sh scripts/validate.sh scripts/run-remote.ps1 scripts/validate-powershell.ps1 scripts/tests/test-run-remote.ps1 scripts/tests/test-validator-evidence.sh .github/workflows/validate.yml; do
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
      if path_is_forbidden "$path"; then fail "forbidden tracked path: $path"; path_violations=$((path_violations + 1)); fi
    done <<< "$tracked"
    if (( path_violations == 0 )); then pass 'tracked-path credential, inventory, raw-log and backup guard'; fi
  else
    status=$?
    missing "git ls-files unavailable or failed (exit=$status)"
  fi
  for path in .env .env.local nested/.env nested/path/.ssh/config id_ed25519 nested/tls/server.pem nested/tls/cert.p12 secrets/token credentials/token kubeconfig .kube/config admin.conf rke2.yaml inventory.local raw-inventory.txt nested/preflight-raw.txt nested/security-baseline-raw.txt docs/evidence/public-services.env nested/docs/evidence/live.txt .terraform/terraform.tfstate terraform.tfvars state.tfstate app.log crash.log backups/state.tar.gz nested/file.backup bin/output nested/path/bin/output obj/output Thumbs.db .DS_Store; do
    if ! path_is_forbidden "$path" || ! git -C "$ROOT" check-ignore --no-index -q -- "$path"; then
      fail "forbidden-path policy drift between validator and .gitignore (sample: $path)"
      policy_ok=0
    fi
  done
  for path in .env.example nested/.env.example; do
    if path_is_forbidden "$path" || git -C "$ROOT" check-ignore --no-index -q -- "$path"; then
      fail "$path must remain an allowed environment template exception."
      policy_ok=0
    fi
  done
  if (( policy_ok == 1 )); then pass 'forbidden-path samples agree with .gitignore'; fi
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

lab03_check() {
  run_gate 'bounded Lab 03 Linux performance and cgroup exercise' "$ROOT/scripts/lab03-performance.sh" --exercise
}

lab04_check() {
  run_gate 'read-only Lab 04 networking inventory' "$ROOT/scripts/lab04-networking.sh"
}

lab05_check() {
  run_gate 'read-only Lab 05 storage inventory' "$ROOT/scripts/lab05-storage.sh"
}

lab06_check() {
  run_gate 'bounded Lab 06 Bash automation exercise' "$ROOT/scripts/lab06-bash-automation.sh"
}

public_services_check() {
  local evidence=${PUBLIC_SERVICES_EVIDENCE_FILE:-$ROOT/docs/evidence/public-services.env}
  local line key value source observed observed_epoch now age line_number=0 malformed=0
  local provider_seen=0 console_seen=0 provider_status='' provider_time='' console_status='' console_time=''
  local client_address='' server_address='' server_port='' connection_host='' usedns='' base_context='' context='' ssh_values='' ufw_status='' ufw_rules='' ufw_active=''

  section 'Live VPS SSH verification'
  if [[ "${PUBLIC_SERVICES_SSH_KEY_VERIFIED:-}" == PASS ]]; then
    pass 'this gate arrived over a key-only OpenSSH session.'
  else
    missing 'run this gate through run-remote.ps1 with its key-only SSH options.'
  fi
  if [[ -z "${SSH_CONNECTION:-}" ]]; then
    missing 'SSH_CONNECTION is absent; this gate must execute inside the current VPS SSH session.'
  elif ! command -v sshd >/dev/null 2>&1; then
    missing 'sshd is unavailable on the VPS.'
  else
    read -r client_address _ server_address server_port <<< "$SSH_CONNECTION"
    if [[ -z "$client_address" || -z "$server_address" || ! "$server_port" =~ ^[0-9]+$ ]]; then
      missing 'SSH_CONNECTION is malformed; live SSH policy cannot be evaluated.'
    elif ! sshd -t >/dev/null 2>&1; then
      fail 'sshd -t failed for the current VPS configuration.'
    elif ! base_context=$(sshd -T 2>/dev/null); then
      missing 'could not read base sshd effective configuration.'
    else
      usedns=$(awk '$1 == "usedns" {print $2; count++} END {if (count != 1) exit 1}' <<< "$base_context") || usedns=unknown
      connection_host=$client_address
      if [[ "$usedns" == yes ]]; then
        if reverse=$(getent hosts "$client_address" 2>/dev/null); then connection_host=$(awk 'NF >= 2 {print $2; exit}' <<< "$reverse"); else connection_host=''; fi
      fi
      if [[ -z "$connection_host" ]]; then
        missing 'client host context could not be resolved as required by UseDNS.'
      elif context=$(sshd -T -C "user=$(id -un),host=$connection_host,addr=$client_address,laddr=$server_address,lport=$server_port" 2>/dev/null); then
        if ssh_values=$(awk 'BEGIN {n=split("pubkeyauthentication passwordauthentication permitrootlogin kbdinteractiveauthentication", a, " "); for (i=1; i<=n; i++) wanted[a[i]]=1} $1 in wanted {count[$1]++; value[$1]=$2} END {for (i=1; i<=n; i++) {if (count[a[i]] != 1) exit 1; printf "%s=%s%s", a[i], value[a[i]], (i == n ? "\n" : " ")}}' <<< "$context"); then
          printf 'sshd -T -C evaluated the live client/server address and port; OpenSSH resolved Include and Match precedence.\n'
          printf 'Effective SSH policy: %s\n' "$ssh_values"
          if grep -Fxq 'pubkeyauthentication yes' <<< "$context" && grep -Fxq 'passwordauthentication no' <<< "$context" && grep -Fxq 'permitrootlogin prohibit-password' <<< "$context" && grep -Fxq 'kbdinteractiveauthentication no' <<< "$context"; then
            pass 'live sshd policy matches key-only requirements, including canonical PermitRootLogin.'
          else
            fail 'live sshd Match/Include-resolved policy does not meet key-only deployment requirements.'
          fi
        else
          missing 'sshd -T -C did not emit each required canonical directive exactly once.'
        fi
      else
        missing 'sshd -T -C failed for the live connection context.'
      fi
    fi
  fi

  section 'Live VPS host-firewall verification'
  if ! command -v ufw >/dev/null 2>&1; then
    missing 'UFW command is unavailable; host firewall state is not verified.'
  elif ufw_status=$(ufw status verbose 2>/dev/null) && ufw_rules=$(ufw status 2>/dev/null); then
    ufw_active=$(awk -F': ' '$1 == "Status" {print $2; count++} END {if (count != 1) exit 1}' <<< "$ufw_status") || ufw_active=unknown
    if [[ "$ufw_active" != active ]]; then
      fail 'live UFW status is not active.'
    elif ! grep -Fq 'Default: deny (incoming)' <<< "$ufw_status" || ! grep -Fq 'allow (outgoing)' <<< "$ufw_status"; then
      fail 'live UFW defaults do not deny incoming and allow outgoing traffic.'
    elif [[ ! "$server_port" =~ ^[0-9]+$ ]] || ! awk -v port="$server_port" '$1 == port || $1 == port "/tcp" {if ($2 == "ALLOW" || ($2 == "(v6)" && $3 == "ALLOW")) found=1} END {exit !found}' <<< "$ufw_rules"; then
      fail 'live UFW rules do not show an incoming allow rule for the current SSH port.'
    else
      pass 'live UFW is active, denies incoming by default, and allows the current SSH port.'
    fi
  else
    missing 'live UFW status queries failed; host firewall is not verified.'
  fi

  section 'Fresh manually recorded provider evidence'
  if [[ ! -s "$evidence" ]]; then
    missing 'manual provider-firewall and rescue-console evidence is absent.'
    deferred 'public-service deployment until fresh portal evidence is recorded.'
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_number=$((line_number + 1))
      line=${line%$'\r'}
      [[ "$line" =~ ^[[:space:]]*# || -z "${line//[[:space:]]/}" ]] && continue
      if [[ ! "$line" =~ ^([A-Z][A-Z0-9_]*)=(PASS|FAIL|UNKNOWN),(MANUAL|VPS_LIVE|CLIENT_LIVE),([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)$ ]]; then
        fail "malformed public-service evidence record at line $line_number."
        malformed=1
        continue
      fi
      key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}; source=${BASH_REMATCH[3]}; observed=${BASH_REMATCH[4]}
      case "$key" in
        PROVIDER_FIREWALL) if (( provider_seen )); then fail 'duplicate public-service evidence key: PROVIDER_FIREWALL.'; malformed=1; else provider_seen=1; provider_status=$value; provider_time=$observed; fi ;;
        CONSOLE_RECOVERY) if (( console_seen )); then fail 'duplicate public-service evidence key: CONSOLE_RECOVERY.'; malformed=1; else console_seen=1; console_status=$value; console_time=$observed; fi ;;
        *) fail "unexpected public-service evidence key: $key."; malformed=1 ;;
      esac
      if [[ "$source" != MANUAL ]]; then fail "evidence $key must be manual portal evidence; host state is checked live."; malformed=1; fi
    done < "$evidence"
    if (( malformed == 0 )); then
      now=$(date -u +%s)
      for key in PROVIDER_FIREWALL CONSOLE_RECOVERY; do
        if [[ "$key" == PROVIDER_FIREWALL ]]; then value=$provider_status; observed=$provider_time; else value=$console_status; observed=$console_time; fi
        if [[ "$key" == PROVIDER_FIREWALL && $provider_seen == 0 || "$key" == CONSOLE_RECOVERY && $console_seen == 0 ]]; then
          missing "fresh manual evidence is missing: $key."
          continue
        fi
        if ! observed_epoch=$(date -u -d "$observed" +%s 2>/dev/null) || [[ ! "$observed_epoch" =~ ^[0-9]+$ ]] || [[ "$(date -u -d "@$observed_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" != "$observed" ]]; then
          fail "evidence timestamp is invalid: $key."
          continue
        fi
        age=$((now - observed_epoch))
        if (( age < -60 || age > 86400 )); then
          missing "manual evidence is future-dated or older than 24 hours: $key."
          continue
        fi
        case "$value" in
          PASS) pass "$key=PASS [MANUAL; age ${age}s]." ;;
          FAIL) fail "$key=FAIL [MANUAL]." ;;
          UNKNOWN) missing "$key remains UNKNOWN [MANUAL]." ;;
        esac
      done
    fi
  fi
  if (( MISSING > 0 )); then deferred 'public-service deployment until current live host checks and fresh manual evidence are complete.'; fi
}

usage() {
  printf 'Usage: %s {repo|phase-0|lab-01|lab-02|lab-03|lab-04|lab-05|lab-06|public-services}\n' "${0##*/}" >&2
  exit 2
}

[[ $# == 1 ]] || usage
case "$1" in
  repo) repo_check ;;
  phase-0) phase0_check ;;
  lab-01) lab01_check ;;
  lab-02) lab02_check ;;
  lab-03) lab03_check ;;
  lab-04) lab04_check ;;
  lab-05) lab05_check ;;
  lab-06) lab06_check ;;
  public-services) public_services_check ;;
  *) usage ;;
esac

printf '\nValidation summary: FAIL=%s UNKNOWN=%s WARNING=%s\n' "$FAILED" "$UNKNOWN_COUNT" "$WARNING_COUNT"
if (( FAILED > 0 )); then exit 1; fi
if (( MISSING > 0 )); then exit 2; fi
exit 0
