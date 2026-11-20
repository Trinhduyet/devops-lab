#!/usr/bin/env bash
# Lab 04: read-only IPv4/IPv6, routes, DNS and socket diagnostics.
set -uo pipefail
export LC_ALL=C

ERRORS=0
MISSING=0

section() { printf '\n===== %s =====\n' "$1"; }
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; ERRORS=$((ERRORS + 1)); }
missing() { printf 'UNKNOWN: %s\n' "$1"; MISSING=$((MISSING + 1)); }
not_tested() { printf 'NOT TESTED: %s\n' "$1"; }

section 'Read-only networking prerequisites'
for command_name in ip ss getent awk sort wc timeout systemctl; do
  if command -v "$command_name" >/dev/null 2>&1; then printf 'AVAILABLE: %s\n' "$command_name"; else missing "required network diagnostic command is unavailable: $command_name."; fi
done
for path in /proc/net/route /proc/net/ipv6_route /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do
  if [[ -r "$path" ]]; then printf 'AVAILABLE: %s\n' "${path##*/}"; else not_tested "optional kernel network table unavailable: ${path##*/}."; fi
done
if (( MISSING > 0 )); then printf 'LAB 04 STATUS=UNKNOWN; required diagnostics are unavailable (exit=2).\n'; exit 2; fi

section 'Interfaces and IPv4/IPv6 addressing'
if links=$(ip -o link show); then
  awk -F': ' '{iface=$2; sub(/@.*/,"",iface); state="unknown"; n=split($3,fields," "); for(i=1;i<=n;i++) if(fields[i]=="state" && i<n) state=fields[i+1]; print "interface",iface,"state",state}' <<< "$links"
else status=$?; missing "interface link inventory failed (exit=$status)."; fi
if addresses=$(ip -o address show); then
  if [[ -n "$addresses" ]]; then
    awk '{if($3!="inet" && $3!="inet6")next; iface=$2; sub(/@.*/,"",iface); split($4,cidr,"/"); scope="unknown"; for(i=5;i<NF;i++) if($i=="scope") scope=$(i+1); print iface,$3,"prefix-length",cidr[2],"scope",scope}' <<< "$addresses" | sort -u
  else missing 'ip returned no interface address records.'; fi
else status=$?; missing "interface address inventory failed (exit=$status)."; fi
printf 'Address values and full network prefixes are intentionally omitted from output.\n'

section 'Routes, policy tables and NAT concepts'
for family in 4 6; do
  if routes=$(ip -"$family" route show table main); then
    default_count=$(awk '$1=="default"{count++} END{print count+0}' <<< "$routes")
    route_count=$(awk 'NF{count++} END{print count+0}' <<< "$routes")
    printf 'IPv%s main table: routes=%s default-routes=%s\n' "$family" "$route_count" "$default_count"
    awk -v family="$family" '$1=="default"{dev="unknown"; proto="unknown"; for(i=1;i<=NF;i++){if($i=="dev")dev=$(i+1); if($i=="proto")proto=$(i+1)} print "IPv" family " default route interface=" dev " proto=" proto}' <<< "$routes"
  else status=$?; missing "IPv$family route query failed (exit=$status)."; fi
done
printf 'Route destinations, next-hop addresses, source networks, and NAT/firewall match rules are omitted.\n'

section 'Resolver configuration and bounded DNS lookup'
if [[ -r /etc/resolv.conf ]]; then
  resolver_count=$(awk '$1=="nameserver"{count++} END{print count+0}' /etc/resolv.conf)
  printf 'configured resolver entries=%s; resolver addresses omitted.\n' "$resolver_count"
else not_tested '/etc/resolv.conf is not readable.'; fi
if resolved=$(timeout 5s getent ahosts example.org 2>/dev/null) && [[ -n "$resolved" ]]; then
  answer_count=$(awk '{print $1}' <<< "$resolved" | sort -u | wc -l | tr -d '[:space:]')
  pass "DNS resolution for example.org returned $answer_count unique address record(s); values omitted."
else status=$?; fail "bounded DNS resolution for example.org failed or timed out (exit=$status)."; fi
if systemctl is-active --quiet systemd-resolved.service; then pass 'systemd-resolved.service is active.'; else not_tested 'systemd-resolved.service is not active; resolver may be managed by another service.'; fi

section 'TCP/UDP sockets and connection-state summary'
if socket_summary=$(ss -s); then printf '%s\n' "$socket_summary"; else status=$?; missing "ss summary failed (exit=$status)."; fi
if listeners=$(ss -H -lntu); then
  if [[ -n "$listeners" ]]; then
    awk '{local=$5; port=local; sub(/^.*:/,"",port); address=local; sub(/:[^:]*$/,"",address); gsub(/^\[|\]$/,"",address); bind="specific-redacted"; if(address=="*" || address=="0.0.0.0" || address=="::")bind="wildcard"; else if(address ~ /^127\./ || address=="::1")bind="loopback"; print $1,"port",port,"bind",bind}' <<< "$listeners" | sort -u
  else printf 'No listening TCP/UDP sockets returned by ss.\n'; fi
else status=$?; missing "ss listening socket query failed (exit=$status)."; fi
for table in tcp tcp6 udp udp6; do
  if [[ -r "/proc/net/$table" ]]; then count=$(awk 'NR>1{count++} END{print count+0}' "/proc/net/$table"); printf '/proc/net/%s socket rows=%s\n' "$table" "$count"; fi
done

section 'Host firewall state (observation only)'
if command -v ufw >/dev/null 2>&1; then
  if ufw_status=$(ufw status 2>/dev/null); then awk -F': ' '$1=="Status"{print "UFW status:",$2}' <<< "$ufw_status"; else status=$?; missing "UFW status query failed (exit=$status)."; fi
else not_tested 'UFW is not installed; firewall is still checked separately before public services.'; fi
printf 'No port, route, firewall, DNS, resolver or interface configuration was changed.\n'

section 'Lab 04 result'
printf 'Read-only networking lab; failed required probes=%s, unavailable required results=%s. This is not public-ingress or production proof.\n' "$ERRORS" "$MISSING"
if (( ERRORS > 0 )); then printf 'LAB 04 STATUS=FAIL.\n'; exit 1; fi
if (( MISSING > 0 )); then printf 'LAB 04 STATUS=UNKNOWN (exit=2).\n'; exit 2; fi
printf 'LAB 04 STATUS=PASS; interface, route, resolver and socket observations completed.\n'
