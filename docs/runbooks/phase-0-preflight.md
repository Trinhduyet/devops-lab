# Runbook — Phase 0 preflight and firewall safety

## Purpose and evidence boundaries

Use this runbook for read-only host inventory and for planning a future firewall change. `scripts/preflight.sh` and `scripts/security-baseline.sh` collect inventory; they do not authorize a change or prove a security gate. `scripts/validate.sh public-services` checks live host state and separately requires fresh manual evidence for provider ingress and out-of-band recovery.

The lab has completed a live SSH inventory and Linux labs. Exact host identifiers, raw network/rule output, current SSH policy, and provider console details stay in local-only evidence; this public runbook records no machine-specific security posture. No SSH, firewall, network, disk, package, or cluster configuration was changed during those read-only labs.

## Read-only collection

From PowerShell at the repository root:

```powershell
.\scripts\run-remote.ps1 -Phase phase-0
```

The helper uploads only the required scripts to a unique remote `mktemp` directory, runs `bash -n` on each script, invokes inventory and validation, and cleans that exact directory. `INVENTORY STATUS=COLLECTED` means the probes ran; it is not a security/deployment gate. Validator exit codes remain: `0` required gates satisfied, `1` a required check failed, `2` required evidence is missing or stale.

Read-only Linux commands for a focused review:

```bash
uname -a
cat /etc/os-release
uptime
free -h
df -hT
ip -brief address
ip -4 route show table main
ip -6 route show table main
getent ahosts example.org
systemctl --failed --no-pager
systemd-detect-virt
stat -fc %T /sys/fs/cgroup
command -v docker containerd kubectl kubeadm rke2
```

SSH/authentication and firewall inspection should use `scripts/security-baseline.sh`. It builds `sshd -T -C` from the current `SSH_CONNECTION` client and server context, evaluates effective settings after OpenSSH `Include`/`Match` processing, checks one canonical output per key directive, and reports malformed/missing data as unknown/failure. It never treats client key-only success as proof that server password authentication is disabled. Redact raw addresses, source networks, user names and rules before sharing any output.

## Read-only firewall inspection

```bash
sudo ufw status verbose
sudo ufw show added
sudo grep -E '^(IPV6|DEFAULT_INPUT_POLICY|DEFAULT_OUTPUT_POLICY|DEFAULT_FORWARD_POLICY)=' /etc/default/ufw
sudo iptables -S
sudo ip6tables -S
sudo nft list ruleset
sudo ss -lntup
sudo grep -nEi 'icmpv6|ipv6-icmp' /etc/ufw/before6.rules
```

Rule dumps can contain host addresses, interfaces and source networks. Keep them in the local terminal; do not paste raw output into GitHub. `ufw status` lists UFW-managed rules, while raw rules and persisted files are needed to understand other firewall managers. See [ufw(8)](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html) and [ufw-framework(8)](https://manpages.ubuntu.com/manpages/noble/man8/ufw-framework.8.html).

## Docker host-change versus public exposure

Run `.\scripts\run-remote.ps1 -Phase host-change` before a Docker package installation. This read-only gate checks the current key-only management session, SSH service and syntax, fresh manual provider/rescue evidence, capacity, cgroup/kernel support, and collects the current firewall/forwarding state for impact review. Exit `0` is necessary evidence for the install review; it is not approval to change the host.

Run `scripts/validate.sh public-services` only when the intended service will be reachable from the Internet. A Compose mapping on `127.0.0.1` is not public exposure, but Docker installation still changes the host runtime/network surface and requires host-change approval and rollback. Docker's port-publishing behavior must still be checked after installation.

## Required preconditions before any firewall change

Firewall changes can interrupt the only management path. Do not change firewall/network state until all of these are true and the specific change set has been confirmed:

1. Provider IPv4/IPv6 ingress policy has been reviewed; a verified provider rescue/Web Console has been used to log in successfully.
2. A second independent SSH session works with the intended key; keep the first session open for recovery.
3. The intended SSH authentication policy and allowed management path are understood from fresh `sshd -t` and `sshd -T -C` output.
4. The current UFW state and IPv4/IPv6 behavior are understood; retain required ICMPv6 rules.
5. Both `/etc/ufw` and `/etc/default/ufw` have been backed up in a root-only archive and the archive contents have been verified.
6. A timed rollback has been armed and verified active before enabling filtering. The timer restores emergency connectivity only; it is not a full configuration restore.

If any precondition is missing, leave firewall state unchanged.

## Backup and candidate sequence — not executed

Create a private archive before preparing any change:

```bash
sudo install -d -m 700 /root/ufw-backups
sudo sh -c 'umask 077; tar -C / -czf "/root/ufw-backups/ufw-$(date -u +%Y%m%dT%H%M%SZ).tar.gz" etc/ufw etc/default/ufw'
sudo tar -tzf /root/ufw-backups/<backup-file>.tar.gz
```

Only after all preconditions and approval, prepare and review rules before enabling:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH management'
sudo ufw status verbose
sudo ufw status numbered
sudo ufw --dry-run --force enable
```

Expected policy: incoming denied by default, outgoing allowed, and the explicitly approved management path allowed. If `IPV6=yes`, the generic port rule may also allow IPv6 from any source at the host firewall layer; replace it with a reviewed source-restricted rule when the source/path is verified. Never add Kubernetes API, etcd, kubelet, NodePort or application ports by default.

Before enabling, create and verify a five-minute connectivity recovery timer:

```bash
sudo systemd-run --unit=devops-lab-ufw-rollback --on-active=5m --timer-property=AccuracySec=1s /usr/sbin/ufw --force disable
sudo systemctl is-active devops-lab-ufw-rollback.timer
```

Proceed only if the timer reports `active`. Then enable and inspect the firewall, and verify a new SSH session from the client:

```bash
sudo ufw --force enable
sudo ufw status verbose
```

```powershell
ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no devops-lab "printf NEW_SSH_OK"
```

Only after the new session and expected rules are verified, cancel the timer and verify it is inactive:

```bash
sudo systemctl stop devops-lab-ufw-rollback.timer
sudo systemctl show --property=ActiveState --value devops-lab-ufw-rollback.timer
```

The timer sequence is documented, not executed as part of the read-only labs. `systemd-run --on-active` creates a transient timer/service; see [systemd-run(1)](https://www.freedesktop.org/software/systemd/man/255/systemd-run.html).

## Emergency connectivity recovery — management path only

Preconditions for an intentional recovery action are a provider rescue/Web Console that has already been verified, a verified archive, and a rollback timer confirmed active before the firewall change. If SSH is lost, allow that timer to disable UFW or use the verified console to run:

```bash
sudo ufw disable
sudo ufw status verbose
```

This restores a management path by disabling UFW. It does not restore saved configuration files.

## Full UFW configuration rollback — restore saved files

This is separate from emergency connectivity recovery. First regain a stable management session or use the verified console; confirm the correct archive contains both `etc/ufw` and `etc/default/ufw`; review the restore contents. Then:

```bash
sudo ufw --force disable
sudo tar -C / -xzf /root/ufw-backups/<backup-file>.tar.gz etc/ufw etc/default/ufw
sudo ufw status verbose
sudo grep -E '^(IPV6|DEFAULT_INPUT_POLICY|DEFAULT_OUTPUT_POLICY|DEFAULT_FORWARD_POLICY)=' /etc/default/ufw
```

Do not remove the archive until the restored runtime rules, persisted defaults, SSH access and recovery console have been verified. The emergency timer is never a substitute for a reviewed full rollback.

## Current gate and next steps

- Linux Labs 01–06 completed with bounded or read-only exercises and verified cleanup; see [progress](../progress.md).
- SSH hardening remains unapplied. Firewall/security and public ingress remain separate gates; detailed live posture is not published here.
- Provider/public application ingress and authoritative DNS remain unverified. Host route, resolver, and Docker registry egress over IPv4/IPv6 were checked during Lab 07 on 2026-11-23; no non-SSH public listener was present at final check.
- Docker Engine and the bounded Lab 07 smoke are complete under the separate host-change approval/gate. Docker/containerd application labs and Kubernetes still require their own compatibility/resource checks. No Kubernetes control-plane ports are exposed by this runbook.
