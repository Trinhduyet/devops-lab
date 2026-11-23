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
  for path in README.md AGENTS.md .gitignore docs/progress.md docs/infrastructure.md docs/resource-budget.md docs/architecture.md docs/roadmap.md docs/troubleshooting.md docs/runbooks/phase-0-preflight.md docs/runbooks/ssh-hardening.md docs/runbooks/docker-engine-install.md .agents/skills/vps-linux-lab/SKILL.md .agents/skills/container-runtime-lab/SKILL.md labs/01-linux/README.md labs/02-linux/README.md labs/03-linux/README.md labs/04-linux/README.md labs/05-linux/README.md labs/06-linux/README.md labs/07-docker-engine/README.md labs/08-docker-networking/README.md labs/09-docker-storage/README.md labs/10-dotnet-api/README.md labs/11-containerd/README.md applications/dotnet-sample-api/README.md applications/dotnet-sample-api/.dockerignore applications/dotnet-sample-api/DevOpsLab.SampleApi.csproj applications/dotnet-sample-api/Program.cs applications/dotnet-sample-api/Dockerfile applications/dotnet-sample-api/compose.yaml applications/dotnet-sample-api/tests/smoke.ps1 scripts/preflight.sh scripts/security-baseline.sh scripts/lab01-readonly.sh scripts/lab02-systemd.sh scripts/lab03-performance.sh scripts/lab04-networking.sh scripts/lab05-storage.sh scripts/lab06-bash-automation.sh scripts/test-dotnet-api.sh scripts/test-dotnet-container.sh scripts/validate.sh scripts/run-remote.ps1 scripts/validate-powershell.ps1 scripts/tests/test-run-remote.ps1 scripts/tests/test-validator-evidence.sh .github/workflows/validate.yml; do
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

manual_recovery_evidence_check() {
  local evidence=$1 line key value source observed observed_epoch now age line_number=0 malformed=0
  local provider_seen=0 console_seen=0 provider_status='' provider_time='' console_status='' console_time=''

  section 'Fresh manually recorded provider and recovery evidence'
  if [[ ! -s "$evidence" ]]; then
    missing 'manual provider-firewall and recovery-console evidence is absent.'
    return
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line=${line%$'\r'}
    [[ "$line" =~ ^[[:space:]]*# || -z "${line//[[:space:]]/}" ]] && continue
    if [[ ! "$line" =~ ^([A-Z][A-Z0-9_]*)=(PASS|FAIL|UNKNOWN),(MANUAL|VPS_LIVE|CLIENT_LIVE),([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)$ ]]; then
      fail "malformed provider/recovery evidence record at line $line_number."
      malformed=1
      continue
    fi
    key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}; source=${BASH_REMATCH[3]}; observed=${BASH_REMATCH[4]}
    case "$key" in
      PROVIDER_FIREWALL) if (( provider_seen )); then fail 'duplicate manual evidence key: PROVIDER_FIREWALL.'; malformed=1; else provider_seen=1; provider_status=$value; provider_time=$observed; fi ;;
      CONSOLE_RECOVERY) if (( console_seen )); then fail 'duplicate manual evidence key: CONSOLE_RECOVERY.'; malformed=1; else console_seen=1; console_status=$value; console_time=$observed; fi ;;
      *) fail "unexpected provider/recovery evidence key: $key."; malformed=1 ;;
    esac
    if [[ "$source" != MANUAL ]]; then fail "evidence $key must be MANUAL; live host state is checked separately."; malformed=1; fi
  done < "$evidence"

  if (( malformed != 0 )); then return; fi
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
}

host_change_check() {
  local evidence=${HOST_CHANGE_EVIDENCE_FILE:-$ROOT/docs/evidence/public-services.env}
  local ssh_client='' ssh_server='' ssh_port=''
  local mem_available_kb='' cpus='' load_one='' disk_available_kb='' disk_used_percent=''
  local cgroup_type='' ufw_status='' ufw_state='' forward_value='' nft_tables='' iptables_rules='' ip6tables_rules=''

  section 'Docker host-change management recovery'
  if [[ "${HOST_CHANGE_SSH_KEY_VERIFIED:-}" == PASS && -n "${SSH_CONNECTION:-}" ]]; then
    read -r ssh_client _ ssh_server ssh_port <<< "$SSH_CONNECTION"
    if [[ -n "$ssh_client" && -n "$ssh_server" && "$ssh_port" =~ ^[0-9]+$ ]]; then
      pass 'this preflight arrived inside a key-only SSH session with a usable connection context.'
    else
      missing 'SSH_CONNECTION is malformed; management recovery context is not verified.'
    fi
  else
    missing 'run this preflight through run-remote.ps1 using its key-only SSH options.'
  fi
  if ! command -v sshd >/dev/null 2>&1 || ! sshd -t >/dev/null 2>&1; then
    fail 'live sshd syntax check failed or sshd is unavailable.'
  else
    pass 'live sshd syntax check passed.'
  fi
  if systemctl is-active --quiet ssh.service; then pass 'SSH service is active for management recovery.'; else fail 'SSH service is not active.'; fi

  section 'Docker installation resource preflight'
  if ! mem_available_kb=$(awk '$1 == "MemAvailable:" {value=$2; count++} END {if (count != 1 || value !~ /^[0-9]+$/) exit 1; print value}' /proc/meminfo); then
    missing 'MemAvailable could not be read exactly once.'
  elif (( mem_available_kb < 1572864 )); then
    fail "MemAvailable is below the Docker lab minimum of 1536 MiB (${mem_available_kb} KiB)."
  else
    pass "MemAvailable meets the Docker lab minimum of 1536 MiB (${mem_available_kb} KiB)."
  fi

  if ! cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || [[ ! "$cpus" =~ ^[1-9][0-9]*$ ]]; then
    missing 'online CPU count is unavailable.'
  elif ! load_one=$(awk '{if (NF < 1 || $1 !~ /^[0-9]+([.][0-9]+)?$/) exit 1; print $1}' /proc/loadavg); then
    missing 'one-minute load average is unavailable.'
  elif awk -v average="$load_one" -v count="$cpus" 'BEGIN {exit !(average < count)}'; then
    pass "one-minute load is below online CPU count ($load_one < $cpus)."
  else
    fail "one-minute load must be below online CPU count ($load_one >= $cpus)."
  fi

  if ! disk_values=$(df -Pk -- / | awk 'NR == 2 {gsub(/%/, "", $5); print $4, $5; count++} END {if (count != 1) exit 1}'); then
    missing 'root filesystem free space and use percentage are unavailable.'
  else
    read -r disk_available_kb disk_used_percent <<< "$disk_values"
    if [[ ! "$disk_available_kb" =~ ^[0-9]+$ || ! "$disk_used_percent" =~ ^[0-9]+$ ]]; then
      missing 'root filesystem capacity output is malformed.'
    elif (( disk_available_kb < 8388608 || disk_used_percent >= 80 )); then
      fail "root filesystem must have at least 8 GiB free and remain below 80% used (free=${disk_available_kb} KiB, used=${disk_used_percent}%)."
    else
      pass "root filesystem meets the 8 GiB free / <80% used gate (free=${disk_available_kb} KiB, used=${disk_used_percent}%)."
    fi
  fi

  if ! cgroup_type=$(stat -fc %T /sys/fs/cgroup 2>/dev/null); then
    missing 'cgroup filesystem type is unavailable.'
  elif [[ "$cgroup_type" == cgroup2fs ]]; then
    pass 'cgroup v2 is mounted.'
  else
    fail 'Docker lab requires cgroup v2 on this host.'
  fi
  if command -v modinfo >/dev/null 2>&1 && modinfo -F filename overlay >/dev/null 2>&1; then
    pass 'OverlayFS kernel module is available for the Docker storage driver.'
  else
    missing 'OverlayFS module availability could not be verified.'
  fi

  section 'Docker network and firewall impact assessment'
  if ! command -v ufw >/dev/null 2>&1 || ! ufw_status=$(ufw status verbose 2>/dev/null); then
    missing 'UFW state could not be collected for the installation impact review.'
  elif ! ufw_state=$(awk -F': ' '$1 == "Status" {print $2; count++} END {if (count != 1) exit 1}' <<< "$ufw_status"); then
    missing 'UFW status output did not contain one canonical state.'
  else
    pass "UFW state was collected (active=$ufw_state); this result does not pass public exposure policy."
    if [[ "$ufw_state" != active ]]; then warning 'UFW is inactive; record this in the Docker installation review and keep application ports unpublished.'; fi
  fi
  if ! forward_value=$(sysctl -n net.ipv4.ip_forward 2>/dev/null) || [[ ! "$forward_value" =~ ^[01]$ ]]; then
    missing 'IPv4 forwarding state could not be collected.'
  else
    pass "IPv4 forwarding state was collected (value=$forward_value); Docker bridge startup may alter forwarding/filter rules."
  fi
  if ! nft_tables=$(nft list tables 2>/dev/null) || ! iptables_rules=$(iptables -S 2>/dev/null) || ! ip6tables_rules=$(ip6tables -S 2>/dev/null); then
    missing 'nftables and both iptables-family rule summaries must be queryable before reviewing Docker network effects.'
  else
    pass 'nftables, IPv4 iptables and IPv6 iptables state were collected without printing raw rules.'
  fi
  warning 'Host-change preflight does not test or authorize public application ingress; use public-services only for an Internet-facing service.'

  manual_recovery_evidence_check "$evidence"
  if (( MISSING > 0 )); then deferred 'Docker host change until management recovery, resource capacity and fresh provider evidence are complete.'; fi
  printf 'Approval boundary: this preflight does not authorize package installation or host configuration changes.\n'
}

public_services_check() {
  local evidence=${PUBLIC_SERVICES_EVIDENCE_FILE:-$ROOT/docs/evidence/public-services.env}
  local client_address='' server_address='' server_port='' connection_host='' usedns='' base_context='' context='' ssh_values='' session_user='' permit_root_ok=0 ufw_status='' ufw_rules='' ufw_active=''

  section 'Public-service exposure gate: live SSH policy'
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
    session_user=$(id -un 2>/dev/null) || session_user=''
    if [[ -z "$client_address" || -z "$server_address" || ! "$server_port" =~ ^[0-9]+$ || -z "$session_user" ]]; then
      missing 'SSH connection/account context is incomplete; live SSH policy cannot be evaluated.'
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
      elif context=$(sshd -T -C "user=$session_user,host=$connection_host,addr=$client_address,laddr=$server_address,lport=$server_port" 2>/dev/null); then
        if ssh_values=$(awk 'BEGIN {n=split("pubkeyauthentication passwordauthentication permitrootlogin kbdinteractiveauthentication hostbasedauthentication gssapiauthentication", a, " "); for (i=1; i<=n; i++) wanted[a[i]]=1} $1 in wanted {count[$1]++; value[$1]=$2} END {for (i=1; i<=n; i++) {if (count[a[i]] != 1) exit 1; printf "%s=%s%s", a[i], value[a[i]], (i == n ? "\n" : " ")}}' <<< "$context"); then
          printf 'sshd -T -C used the current management account and live connection context after Include/Match precedence.\n'
          printf 'Effective SSH policy: %s\n' "$ssh_values"
          if [[ "$session_user" == root ]]; then
            grep -Fxq 'permitrootlogin prohibit-password' <<< "$context" && permit_root_ok=1
          elif grep -Fxq 'permitrootlogin no' <<< "$context" || grep -Fxq 'permitrootlogin prohibit-password' <<< "$context"; then
            permit_root_ok=1
          fi
          if grep -Fxq 'pubkeyauthentication yes' <<< "$context" \
            && grep -Fxq 'passwordauthentication no' <<< "$context" \
            && grep -Fxq 'kbdinteractiveauthentication no' <<< "$context" \
            && grep -Fxq 'hostbasedauthentication no' <<< "$context" \
            && grep -Fxq 'gssapiauthentication no' <<< "$context" \
            && (( permit_root_ok == 1 )); then
            pass 'live SSH authentication is key-only; PermitRootLogin is compatible with the current management account.'
          else
            fail 'live sshd Match/Include-resolved policy does not meet strict key-only requirements for the current management account.'
          fi
        else
          missing 'sshd -T -C did not emit each canonical key-only directive exactly once.'
        fi
      else
        missing 'sshd -T -C failed for the live connection context.'
      fi
    fi
  fi

  section 'Public-service exposure gate: host firewall'
  if ! command -v ufw >/dev/null 2>&1; then
    missing 'UFW command is unavailable; public-service host firewall state is not verified.'
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
    missing 'live UFW status queries failed; public-service host firewall is not verified.'
  fi

  manual_recovery_evidence_check "$evidence"
  if (( MISSING > 0 )); then deferred 'public-service exposure until strict live SSH, host firewall and fresh provider evidence are complete.'; fi
}

usage() {
  printf 'Usage: %s {repo|phase-0|lab-01|lab-02|lab-03|lab-04|lab-05|lab-06|host-change|public-services}\n' "${0##*/}" >&2
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
  host-change) host_change_check ;;
  public-services) public_services_check ;;
  *) usage ;;
esac

printf '\nValidation summary: FAIL=%s UNKNOWN=%s WARNING=%s\n' "$FAILED" "$UNKNOWN_COUNT" "$WARNING_COUNT"
if (( FAILED > 0 )); then exit 1; fi
if (( MISSING > 0 )); then exit 2; fi
exit 0
