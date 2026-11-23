# Runbook — Docker Engine installation on Ubuntu 24.04

## Status and approval boundary

This is a reviewed installation plan, not an executed change. Docker Engine installation is a host change because it installs privileged services and modifies packet-filtering/network behavior. It needs a fresh passing `host-change` gate and explicit approval for the exact package install and expected network effects. It does not require the `public-services` exposure gate when the only workload binds to loopback. Any Internet-reachable service requires that separate gate and a separate approval.

Do not change SSH, UFW, provider firewall, routes, or forwarding policy as part of this package install. Keep a verified rescue console and an independent SSH session available. A passing preflight is evidence, not approval.

## Reviewed package set

Official Docker Ubuntu instructions support Ubuntu 24.04 Noble on amd64. The official Noble amd64 package index currently lists this pinned set (reviewed 2026-11-23):

| Package | Exact version |
|---|---|
| `docker-ce` | `5:29.10.0-1~ubuntu.24.04~noble` |
| `docker-ce-cli` | `5:29.10.0-1~ubuntu.24.04~noble` |
| `containerd.io` | `2.4.2-4~ubuntu.24.04~noble` |
| `docker-buildx-plugin` | `0.39.1-1~ubuntu.24.04~noble` |
| `docker-compose-plugin` | `5.8.0-1~ubuntu.24.04~noble` |

The `containerd.io` package supplies containerd and runc. Do not install Ubuntu `docker.io`, a separate containerd/runc package, or a second Kubernetes runtime in this step. Before installation, refresh the official index and verify all five exact versions are still available. If any version is unavailable, stop and review a new package set; do not silently substitute `latest`.

## Host-change gate and resource budget

Immediately before installation, from the Windows management machine:

```powershell
.\scripts\run-remote.ps1 -Phase host-change
```

Proceed only if the validator exits `0`, with no `FAIL` or `UNKNOWN`, fresh manual provider-firewall and rescue-console evidence, key-only management session, active SSH service, cgroup v2, available OverlayFS, and these resource minimums:

- `MemAvailable` at least 1536 MiB.
- One-minute load below online CPU count.
- Root filesystem has at least 8 GiB free and remains below 80% used.
- UFW, IPv4/IPv6 iptables and nftables state can be collected for review. UFW inactive is reported as a warning here; it does not pass or fail the independent public exposure gate.

The preflight uses the current SSH session. Before installation, open a second independent key-only SSH session and keep both it and the verified provider rescue console available. Do not rely on the single session that launched the install as the only recovery path.

## Read-only package and network preflight

Run after the `host-change` gate and before approval:

```bash
cat /etc/os-release
dpkg --print-architecture
dpkg-query -W ca-certificates curl
apt-cache policy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
dpkg-query -W docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io containerd runc 2>/dev/null || true
systemctl show docker docker.socket containerd --property=LoadState,ActiveState,UnitFileState
free -h
df -h /
stat -fc %T /sys/fs/cgroup
modinfo -F filename overlay
modinfo -F filename br_netfilter
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
sudo ufw status verbose
sudo nft list ruleset
sudo iptables -S
sudo ip6tables -S
```

Package conflicts are a stop condition. Do not remove conflicting software or reset Docker/containerd state automatically. Record the existing rules and forwarding values in root-only local backup files; do not commit or paste raw addresses/rules into GitHub.

## Planned package installation sequence — not executed

Only after the exact approval, complete the backup and rollback preconditions below. Then use Docker's signed apt repository and simulate the exact package operation first:

```bash
sudo apt-get update
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl --fail --location --silent --show-error https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
apt-cache policy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo apt-get -s install docker-ce=5:29.10.0-1~ubuntu.24.04~noble docker-ce-cli=5:29.10.0-1~ubuntu.24.04~noble containerd.io=2.4.2-4~ubuntu.24.04~noble docker-buildx-plugin=0.39.1-1~ubuntu.24.04~noble docker-compose-plugin=5.8.0-1~ubuntu.24.04~noble
```

Review the simulation for removals, unexpected upgrades, provider/network packages and exact versions. Stop if it removes packages or changes anything beyond the reviewed Docker package set. After that review, the approved install command is:

```bash
sudo apt-get install --yes docker-ce=5:29.10.0-1~ubuntu.24.04~noble docker-ce-cli=5:29.10.0-1~ubuntu.24.04~noble containerd.io=2.4.2-4~ubuntu.24.04~noble docker-buildx-plugin=0.39.1-1~ubuntu.24.04~noble docker-compose-plugin=5.8.0-1~ubuntu.24.04~noble
```

This may start `containerd` and `dockerd`, create `docker0` and Docker-managed iptables/nftables chains, enable IPv4 forwarding, and change the `FORWARD` policy. Published container ports may not pass through UFW's usual input path. Do not edit Docker-created rules or change the UFW/provider firewall in this phase. Keep application mappings bound to `127.0.0.1`; do not expose the Docker API over TCP.

## Backup and rollback preparation — not executed

Before installing, save root-only copies of the current apt sources, UFW configuration/default file, package inventory, relevant sysctls, and packet-filter state. If `/etc/apt/keyrings` already exists, archive it separately; otherwise record that it was absent. These files contain host details and remain on the VPS only:

```bash
sudo install -d -m 700 /root/devops-lab/docker-install-backup
sudo sh -c 'umask 077; tar -C / -czf /root/devops-lab/docker-install-backup/config-before.tgz etc/apt/sources.list.d etc/ufw etc/default/ufw'
if sudo test -d /etc/apt/keyrings; then sudo tar -C / -czf /root/devops-lab/docker-install-backup/keyrings-before.tgz etc/apt/keyrings; else sudo sh -c 'umask 077; printf "absent\n" > /root/devops-lab/docker-install-backup/keyrings-were-absent.txt'; fi
sudo sh -c 'umask 077; dpkg-query -W -f="${binary:Package}\t${Version}\n" > /root/devops-lab/docker-install-backup/packages-before.txt'
sudo sh -c 'umask 077; sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding > /root/devops-lab/docker-install-backup/forwarding-before.txt'
sudo sh -c 'umask 077; nft list ruleset > /root/devops-lab/docker-install-backup/nft-before.txt'
sudo sh -c 'umask 077; iptables-save > /root/devops-lab/docker-install-backup/iptables-before.txt'
sudo sh -c 'umask 077; ip6tables-save > /root/devops-lab/docker-install-backup/ip6tables-before.txt'
sudo tar -tzf /root/devops-lab/docker-install-backup/config-before.tgz
if sudo test -f /root/devops-lab/docker-install-backup/keyrings-before.tgz; then sudo tar -tzf /root/devops-lab/docker-install-backup/keyrings-before.tgz; else sudo cat /root/devops-lab/docker-install-backup/keyrings-were-absent.txt; fi
sudo ls -l /root/devops-lab/docker-install-backup
```

Before the install command, arm and verify a ten-minute emergency timer that stops the Docker services if the install session is lost:

```bash
sudo systemd-run --unit=devops-lab-docker-rollback --on-active=10m --timer-property=AccuracySec=1s /usr/bin/systemctl stop docker.service docker.socket containerd.service
sudo systemctl is-active devops-lab-docker-rollback.timer
```

If a second SSH session and local-only Compose verification succeed, cancel the timer and verify it is inactive:

```bash
sudo systemctl stop devops-lab-docker-rollback.timer
sudo systemctl show --property=ActiveState --value devops-lab-docker-rollback.timer
```

The timer only stops the services; it does not restore packet-filter rules, UFW configuration, or previous package state. If connectivity is lost, use the verified provider rescue console. Do not blindly restore a whole-host iptables/nftables snapshot because it may overwrite provider-managed or otherwise valid rules. Inspect actual differences and apply only a reviewed recovery action.

For a separately approved package rollback, stop the services and remove only the five reviewed Docker packages without purging configuration or deleting `/var/lib/docker` and `/var/lib/containerd`:

```bash
sudo systemctl stop docker.service docker.socket containerd.service
sudo apt-get remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

This package removal is not part of the install approval. It is not a data rollback: preserve Docker/containerd data until its contents are reviewed. Restore backed-up apt/UFW files only if they were changed and only after confirming the exact intended state. Never use `docker system prune` as rollback.

## Post-install verification and cleanup

Verify versions, services, networking, and no unexpected published ports:

```bash
dpkg-query -W -f='${binary:Package}=${Version}\n' docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
docker version
docker compose version
docker info --format 'server={{.ServerVersion}} driver={{.Driver}} cgroup={{.CgroupVersion}}'
systemctl show docker containerd --property=LoadState,ActiveState,MemoryCurrent
sudo ss -lntup
sudo ufw status verbose
sudo iptables -S
sudo ip6tables -S
sudo nft list tables
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
```

Do not record raw host rules or identifiers in Git. Run a bounded container smoke only after post-install resource checks; keep memory, CPU, PIDs and execution time bounded. Stop and remove only the named lab container/network/image, then verify cleanup. A successful package install is not public-service approval and does not prove the host is production ready.

## Official sources

- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Official Docker Noble amd64 package index](https://download.docker.com/linux/ubuntu/dists/noble/pool/stable/amd64/)
- [Docker packet filtering and firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
- [Docker iptables behavior](https://docs.docker.com/engine/network/firewall-iptables/)
- [Docker port publishing](https://docs.docker.com/engine/network/port-publishing/)
