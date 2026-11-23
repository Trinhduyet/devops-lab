---
name: container-runtime-lab
description: Assess, install and practice Docker Engine/containerd in this repository with VPS security, resource and cleanup gates. Use only for its container runtime labs.
---

# Container Runtime Lab

Use this skill from the repository root. Follow the workflow **Assess → Install → Configure → Deploy → Verify → Troubleshoot → Cleanup**. Keep local, VPS and production evidence distinct.

1. Read `AGENTS.md`, `docs/progress.md`, `docs/resource-budget.md`, the active lab and the relevant SSH/firewall runbooks. Treat provider statements as manual evidence; refresh host state using `scripts/preflight.sh` and `scripts/security-baseline.sh` immediately before a host change.
2. Do not install Docker or change SSH/firewall/network until `scripts/validate.sh public-services` has no `FAIL` or `UNKNOWN`, all manual provider/rescue evidence is fresh, required resource gates pass, and the user explicitly approves the specific change. A confirmed rescue console alone does not clear the provider firewall gate.
3. Before pinning packages, use current official Docker documentation and inspect the target OS, architecture, existing Docker/containerd/runc packages, daemon state, disk/RAM headroom, cgroup v2, `overlay`, `br_netfilter`, IPv4 forwarding, UFW and nftables. Do not remove conflicting packages, edit daemon config, load modules or install software without a scoped approval.
4. Install only through Docker's official repository with the exact reviewed package versions. Do not expose the Docker API over TCP, add users to the `docker` group, or disable host security controls. Docker's `containerd.io` package supplies containerd; do not install a second standalone containerd.
5. Run the `docker` CLI via the repository's key-only remote helper. Keep app ports on `127.0.0.1`; never publish IPv4/IPv6 ports without separate explicit approval. Verify Docker's firewall integration and inspect published bindings, bridge networks and resource cgroups.
6. Keep services bounded for the 4-vCPU/3.8-GiB host. Do not run unbounded load, privileged containers, host networking, host PID namespace, or persistent data stores. Do not use global `prune`, remove unknown volumes, format disks, or rewrite provider-managed rules.
7. Use named resources with a lab-specific prefix, record exact image/package versions and observed output, and clean only objects created by that lab. Verify containers, networks, volumes, temporary directories, processes and rollback timers are gone before marking cleanup PASS.
8. Troubleshoot by observing first: `docker info`, `docker inspect`, `docker stats`, `docker network inspect`, `docker volume inspect`, `systemctl show docker containerd`, `journalctl`, `/sys/fs/cgroup`, `ss` and firewall summaries. Never infer a successful deployment from image build or local test alone.
9. Update the canonical progress and lab docs after each runtime exercise. Record unsupported or unexecuted checks as `NOT TESTED`; do not copy credentials, IPs, hostnames, full raw rules or raw host inventory into the public repository.

Use `docs/runbooks/phase-0-preflight.md` for provider firewall and rescue evidence, `docs/runbooks/ssh-hardening.md` for SSH changes, and `docs/resource-budget.md` for capacity gates. Docker Engine and UFW changes are separate operations and each needs its own backup, rollback plan and approval.
