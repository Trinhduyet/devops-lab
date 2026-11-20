#!/usr/bin/env bash
# Read-only SSH, host-firewall, network-rules and listening-port summary.
# Addresses and rule match conditions are intentionally omitted from output.
set -uo pipefail
export LC_ALL=C

section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

section 'SSH session and effective authentication settings'
if [[ -n "${SSH_CONNECTION:-}" ]]; then
  read -r client_address _ server_address server_port <<< "$SSH_CONNECTION"
  if [[ "$client_address" == *:* ]]; then source_family=IPv6; else source_family=IPv4; fi
  if [[ "$server_address" == *:* ]]; then server_family=IPv6; else server_family=IPv4; fi
  printf 'SSH source family: %s; server family: %s; server port: %s\n' "$source_family" "$server_family" "$server_port"
else
  printf 'SSH_CONNECTION is unavailable (run inside the SSH session).\n'
fi
if have sshd; then
  sshd -T 2>/dev/null | awk '$1 ~ /^(port|permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|authorizedkeysfile|allowusers|denyusers)$/ { if ($1 == "authorizedkeysfile") print $1, "<configured>"; else print }'
else
  printf 'sshd command is unavailable.\n'
fi

section 'Address families and default routes (addresses redacted)'
if have ip; then
  ip -o address show | awk '{if ($3 != "inet" && $3 != "inet6") next; scope="unknown"; for(i=4;i<NF;i++) if($i=="scope") {scope=$(i+1); break} print $2, $3, "scope", scope}' | sort -u
  for family in 4 6; do
    ip -"$family" route show table main 2>/dev/null | awk -v family="$family" '$1 == "default" {print "IPv" family " default route present on", $5; found=1} END {if (!found) print "IPv" family " default route: none"}'
  done
else
  printf 'ip command is unavailable.\n'
fi

section 'UFW state and saved user-rule count'
if have ufw; then
  ufw status verbose 2>&1 | awk '/^Status:|^Logging:|^Default:/{print}'
  ufw status numbered 2>/dev/null | awk '/^Status:/{next} /^\[[[:space:]]*[0-9]+\]/{n++} END{print "Numbered UFW rules:",n+0}'
  ufw show added 2>/dev/null | awk '/^ufw[[:space:]]/{n++} END{print "Added UFW rule lines:",n+0}'
  if [[ -r /etc/default/ufw ]]; then
    awk -F= '/^(IPV6|DEFAULT_INPUT_POLICY|DEFAULT_OUTPUT_POLICY|DEFAULT_FORWARD_POLICY)=/{print "configured " $1 "=" $2}' /etc/default/ufw
  fi
else
  printf 'ufw command is unavailable.\n'
fi

section 'iptables and ip6tables chains/actions (match conditions omitted)'
for save_command in iptables-save ip6tables-save; do
  if have "$save_command"; then
    "$save_command" 2>/dev/null | awk -v source="$save_command" '
      /^\*/ {table=substr($0,2)}
      /^:/ {print source, table, $1, "policy", $2}
      /^-A / {chain=$2; action="(no explicit jump)"; for(i=3;i<=NF;i++) if($i=="-j" || $i=="-g") {action=$(i+1); break} print source, table, chain, "action", action}
    '
  else
    printf '%s: unavailable\n' "$save_command"
  fi
done

section 'nftables table and chain names (rules omitted)'
if have nft; then
  nft list ruleset 2>/dev/null | awk '
    /^table / {table=$2 " " $3; print "table",table}
    /^[[:space:]]*chain / {chain=$2; gsub(/[{}]/,"",chain); in_chain=1; print "chain",table,chain; next}
    /^[[:space:]]*}/ {in_chain=0}
    in_chain && /hook/ && /policy/ {hook="unknown"; policy="unknown"; for(i=1;i<=NF;i++){if($i=="hook") hook=$(i+1); if($i=="policy") policy=$(i+1)} print "chain-policy",table,chain,hook,policy}
    in_chain && !/hook/ && /(accept|drop|reject|jump|goto|return|queue)/ {n++; action="rule"; for(i=1;i<=NF;i++) if($i=="accept" || $i=="drop" || $i=="reject" || $i=="jump" || $i=="goto" || $i=="return" || $i=="queue") action=$i; print "rule-action",table,chain,action}
    END {if(NR==0) print "No nftables ruleset output."; print "nft action-rule count:",n+0}
  '
else
  printf 'nft command is unavailable.\n'
fi

section 'Listening TCP/UDP ports (addresses and process arguments omitted)'
if have ss; then
  ss -H -lntu 2>/dev/null | awk '{local=$5; port=local; sub(/^.*:/,"",port); address=local; sub(/:[^:]*$/,"",address); gsub(/^\[|\]$/,"",address); bind="specific-redacted"; if(address=="*" || address=="0.0.0.0" || address=="::") bind="wildcard"; else if(address ~ /^127\./ || address=="::1" || address ~ /^::ffff:127\./) bind="loopback"; else if(address ~ /^fe80:/) bind="link-local"; print $1, "port", port, "bind", bind}' | sort -u
else
  printf 'ss command is unavailable.\n'
fi

section 'Relevant systemd service state'
if have systemctl; then
  for unit in ufw nftables firewalld warp-svc tailscaled docker containerd; do
    state=$(systemctl is-active "$unit" 2>/dev/null || true)
    [[ -n "$state" ]] || state=unknown
    printf 'systemd.%s_unit=%s\n' "$unit" "$state"
  done
else
  printf 'systemctl command is unavailable.\n'
fi

printf '\nRead-only summary complete; no address, credential, or rule match value was printed.\n'
