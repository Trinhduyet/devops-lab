#!/usr/bin/env bash
# Read-only SSH, host-firewall, network-rules and listening-port summary.
# Addresses, credentials and firewall match conditions are intentionally omitted.
set -uo pipefail
export LC_ALL=C

ERRORS=0
NOT_TESTED=0
UNKNOWN_COUNT=0

section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
unknown() { printf 'UNKNOWN: %s\n' "$1"; UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)); }

failed_probe() {
  unknown "$1 failed (exit=$2); inspect the command on the host."
  ERRORS=$((ERRORS + 1))
}

section 'SSH session and effective authentication settings'
if [[ -n "${SSH_CONNECTION:-}" ]]; then
  read -r client_address _ server_address server_port <<< "$SSH_CONNECTION"
  if [[ "$client_address" == *:* ]]; then source_family=IPv6; else source_family=IPv4; fi
  if [[ "$server_address" == *:* ]]; then server_family=IPv6; else server_family=IPv4; fi
  printf 'SSH source family: %s; server family: %s; server port: %s\n' "$source_family" "$server_family" "$server_port"
else
  unknown 'SSH_CONNECTION unavailable; run this check inside the intended SSH session.'
fi
if have sshd; then
  effective=''
  if sshd -t >/dev/null 2>&1; then
    printf 'sshd -t: PASS\n'
  else
    status=$?
    failed_probe 'sshd -t' "$status"
  fi
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    if base_context=$(sshd -T); then
      usedns=$(awk '$1 == "usedns" {print $2; count++} END {if (count != 1) exit 1}' <<< "$base_context") || usedns=unknown
      connection_host=$client_address
      if [[ "$usedns" == yes ]]; then
        if reverse=$(getent hosts "$client_address" 2>/dev/null); then connection_host=$(awk 'NF >= 2 {print $2; exit}' <<< "$reverse"); else connection_host=''; fi
      elif [[ "$usedns" != no ]]; then
        connection_host=''
      fi
      if [[ -z "$connection_host" ]]; then
        unknown 'client host for sshd -T -C could not be resolved consistently with UseDNS.'
        ERRORS=$((ERRORS + 1))
      elif context=$(sshd -T -C "user=$(id -un),host=$connection_host,addr=$client_address,laddr=$server_address,lport=$server_port"); then
        printf 'sshd -T -C context: client address/hostname, server address and port from this live session; addresses redacted.\n'
      effective=$context
      else
        status=$?
        failed_probe 'sshd -T -C (live client context)' "$status"
      fi
    else
      status=$?
      failed_probe 'sshd -T (base context)' "$status"
    fi
  else
    if context=$(sshd -T); then effective=$context; else status=$?; failed_probe 'sshd -T' "$status"; fi
  fi
  if [[ -n "$effective" ]]; then
    filtered=$(awk '$1 ~ /^(usedns|port|permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|authorizedkeysfile|allowusers|denyusers)$/ { if ($1 == "authorizedkeysfile") print $1, "<configured>"; else if ($1 == "allowusers" || $1 == "denyusers") print $1, "<configured>"; else print }' <<< "$effective")
    if [[ -n "$filtered" ]]; then
      printf '%s\n' "$filtered"
      for directive in permitrootlogin pubkeyauthentication passwordauthentication kbdinteractiveauthentication; do
        value_count=$(awk -v key="$directive" '$1 == key {count++} END {print count+0}' <<< "$effective")
        if [[ "$value_count" != 1 ]]; then unknown "effective sshd output contains $value_count canonical $directive entries (expected 1)."; ERRORS=$((ERRORS + 1)); fi
      done
    else
      unknown 'effective SSH output did not contain the expected authentication directives.'
      ERRORS=$((ERRORS + 1))
    fi
  fi
else
  printf 'NOT TESTED: sshd command is unavailable.\n'
  NOT_TESTED=$((NOT_TESTED + 1))
fi

section 'SSH configuration sources (values are sanitized)'
if have python3 && [[ -r /etc/ssh/sshd_config ]]; then
  if config_summary=$(python3 - <<'PY'
from pathlib import Path
import glob
import shlex

root = Path('/etc/ssh')
auth = {'pubkeyauthentication', 'passwordauthentication', 'permitrootlogin',
        'kbdinteractiveauthentication', 'authenticationmethods', 'allowusers', 'denyusers'}
sequence = 0
active = set()

def label(path):
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.name

def scan(path, match_scope=False, depth=0):
    global sequence
    path = path.resolve()
    if depth > 16:
        raise RuntimeError('Include nesting exceeds inspection limit')
    if path in active:
        raise RuntimeError('Include cycle found')
    if not path.is_file():
        return match_scope
    active.add(path)
    try:
        for number, raw in enumerate(path.read_text(errors='replace').splitlines(), 1):
            try:
                fields = shlex.split(raw, comments=True, posix=True)
            except ValueError as error:
                raise RuntimeError(f'cannot parse {label(path)}:{number}: {error}') from error
            if not fields:
                continue
            key = fields[0].lower()
            if key == 'include':
                for pattern in fields[1:]:
                    include_pattern = pattern if pattern.startswith('/') else str(root / pattern)
                    matches = sorted(glob.glob(include_pattern))
                    for included in matches:
                        match_scope = scan(Path(included), match_scope, depth + 1)
                continue
            if key == 'match':
                match_scope = True
                sequence += 1
                scope = 'match-scope' if len(fields) > 1 else 'match-scope-invalid'
                print(f'{sequence:03d} {label(path)}:{number} {scope} Match <conditions redacted>')
            elif key in auth:
                sequence += 1
                scope = 'match-scope' if match_scope else 'global-scope'
                value = ' '.join(fields[1:]) if len(fields) > 1 else '<missing>'
                if key in {'allowusers', 'denyusers'}:
                    value = '<configured>'
                print(f'{sequence:03d} {label(path)}:{number} {scope} {key} {value}')
    finally:
        active.remove(path)
    return match_scope

scan(root / 'sshd_config')
PY
  ); then
    if [[ -n "$config_summary" ]]; then
      printf '%s\n' "$config_summary"
      printf 'Source order is shown for active Includes and Match scopes; sshd -T -C above is the authoritative effective result for this connection.\n'
    else
      unknown 'no active Include, Match or authentication directives found in inspected files.'
    fi
  else
    status=$?
    failed_probe 'SSH config source inspection' "$status"
  fi
else
  printf 'NOT TESTED: python3 or readable sshd_config is unavailable.\n'
  NOT_TESTED=$((NOT_TESTED + 1))
fi

section 'Address families and default routes (addresses redacted)'
if have ip; then
  if addresses=$(ip -o address show); then
    if [[ -n "$addresses" ]]; then
      awk '{if ($3 != "inet" && $3 != "inet6") next; scope="unknown"; for(i=4;i<NF;i++) if($i=="scope") {scope=$(i+1); break} print $2, $3, "scope", scope}' <<< "$addresses" | sort -u
    else
      printf 'No address records returned by ip.\n'
    fi
  else
    status=$?
    failed_probe 'ip -o address show' "$status"
  fi
  for family in 4 6; do
    if routes=$(ip -"$family" route show table main); then
      defaults=$(awk -v family="$family" '$1 == "default" {print "IPv" family " default route present on", $5; found=1} END {if (!found) print "IPv" family " default route: none"}' <<< "$routes")
      printf '%s\n' "$defaults"
    else
      status=$?
      failed_probe "ip -$family route show table main" "$status"
    fi
  done
else
  printf 'NOT TESTED: ip command is unavailable.\n'
  NOT_TESTED=$((NOT_TESTED + 1))
fi

section 'UFW state and saved user-rule count'
if have ufw; then
  if ufw_status=$(ufw status verbose); then
    if [[ -n "$ufw_status" ]]; then
      awk '/^Status:|^Logging:|^Default:/{print}' <<< "$ufw_status"
    else
      unknown 'ufw status returned empty output.'
      ERRORS=$((ERRORS + 1))
    fi
  else
    status=$?
    failed_probe 'ufw status verbose' "$status"
  fi
  if numbered=$(ufw status numbered); then
    number_count=$(awk '/^\[[[:space:]]*[0-9]+\]/{n++} END{print n+0}' <<< "$numbered")
    printf 'Numbered UFW rules: %s\n' "$number_count"
  else
    status=$?
    failed_probe 'ufw status numbered' "$status"
  fi
  if added=$(ufw show added); then
    added_count=$(awk '/^ufw[[:space:]]/{n++} END{print n+0}' <<< "$added")
    printf 'Added UFW rule lines: %s\n' "$added_count"
  else
    status=$?
    failed_probe 'ufw show added' "$status"
  fi
  if [[ -r /etc/default/ufw ]]; then
    awk -F= '/^(IPV6|DEFAULT_INPUT_POLICY|DEFAULT_OUTPUT_POLICY|DEFAULT_FORWARD_POLICY)=/{print "configured " $1 "=" $2}' /etc/default/ufw
  else
    unknown '/etc/default/ufw is not readable.'
  fi
else
  printf 'NOT TESTED: ufw command is unavailable.\n'
  NOT_TESTED=$((NOT_TESTED + 1))
fi

section 'iptables and ip6tables chains/actions (match conditions omitted)'
for save_command in iptables-save ip6tables-save; do
  if have "$save_command"; then
    if rules=$($save_command); then
      if [[ -n "$rules" ]]; then
        awk -v source="$save_command" '
          /^\*/ {table=substr($0,2)}
          /^:/ {print source, table, $1, "policy", $2}
          /^-A / {chain=$2; action="(no explicit jump)"; for(i=3;i<=NF;i++) if($i=="-j" || $i=="-g") {action=$(i+1); break} print source, table, chain, "action", action}
        ' <<< "$rules"
      else
        unknown "$save_command returned empty ruleset output."
      fi
    else
      status=$?
      failed_probe "$save_command" "$status"
    fi
  else
    printf 'NOT TESTED: %s unavailable.\n' "$save_command"
    NOT_TESTED=$((NOT_TESTED + 1))
  fi
done

section 'nftables table and chain names (rules omitted)'
if have nft; then
  if ruleset=$(nft list ruleset); then
    if [[ -n "$ruleset" ]]; then
      awk '
        /^table / {table=$2 " " $3; print "table",table}
        /^[[:space:]]*chain / {chain=$2; gsub(/[{}]/,"",chain); in_chain=1; print "chain",table,chain; next}
        /^[[:space:]]*}/ {in_chain=0}
        in_chain && /hook/ && /policy/ {hook="unknown"; policy="unknown"; for(i=1;i<=NF;i++){if($i=="hook") hook=$(i+1); if($i=="policy") policy=$(i+1)} print "chain-policy",table,chain,hook,policy}
        in_chain && !/hook/ && /(accept|drop|reject|jump|goto|return|queue)/ {action="rule"; for(i=1;i<=NF;i++) if($i=="accept" || $i=="drop" || $i=="reject" || $i=="jump" || $i=="goto" || $i=="return" || $i=="queue") action=$i; print "rule-action",table,chain,action}
      ' <<< "$ruleset"
    else
      unknown 'nft returned empty ruleset output.'
    fi
  else
    status=$?
    failed_probe 'nft list ruleset' "$status"
  fi
else
  printf 'NOT TESTED: nft command is unavailable.\n'
  NOT_TESTED=$((NOT_TESTED + 1))
fi

section 'Listening TCP/UDP ports (addresses and process arguments omitted)'
if have ss; then
  if listeners=$(ss -H -lntu); then
    if [[ -n "$listeners" ]]; then
      awk '{local=$5; port=local; sub(/^.*:/,"",port); address=local; sub(/:[^:]*$/,"",address); gsub(/^\[|\]$/,"",address); bind="specific-redacted"; if(address=="*" || address=="0.0.0.0" || address=="::") bind="wildcard"; else if(address ~ /^127\./ || address=="::1" || address ~ /^::ffff:127\./) bind="loopback"; else if(address ~ /^fe80:/) bind="link-local"; print $1, "port", port, "bind", bind}' <<< "$listeners" | sort -u
    else
      printf 'No listening TCP/UDP sockets returned by ss.\n'
    fi
  else
    status=$?
    failed_probe 'ss -H -lntu' "$status"
  fi
else
  printf 'NOT TESTED: ss command is unavailable.\n'
  NOT_TESTED=$((NOT_TESTED + 1))
fi

section 'Relevant systemd service state'
if have systemctl; then
  for unit in ufw nftables firewalld warp-svc tailscaled docker containerd; do
    if load_state=$(systemctl show --property=LoadState --value "$unit"); then
      if active_state=$(systemctl show --property=ActiveState --value "$unit"); then
        printf 'systemd.%s load=%s active=%s\n' "$unit" "${load_state:-UNKNOWN}" "${active_state:-UNKNOWN}"
      else
        status=$?
        failed_probe "systemctl show ActiveState for $unit" "$status"
      fi
    else
      status=$?
      failed_probe "systemctl show LoadState for $unit" "$status"
    fi
  done
else
  printf 'NOT TESTED: systemctl command is unavailable.\n'
  NOT_TESTED=$((NOT_TESTED + 1))
fi

section 'Inventory result'
printf 'Read-only summary; no address, credential or rule match value was intentionally printed. Failed probes=%s; unknown fields=%s; checks not tested=%s. This is not a security gate.\n' "$ERRORS" "$UNKNOWN_COUNT" "$NOT_TESTED"
if (( ERRORS > 0 )); then
  printf 'INVENTORY STATUS=INCOMPLETE.\n'
  exit 1
fi
if (( UNKNOWN_COUNT > 0 )); then
  printf 'INVENTORY STATUS=COLLECTED_WITH_UNKNOWN (not a security or deployment PASS).\n'
else
  printf 'INVENTORY STATUS=COLLECTED (not a security or deployment PASS).\n'
fi
