---
name: vps-linux-lab
description: Run source-grounded, low-risk Linux VPS assessments and hands-on administration labs for this repository. Use when working through Phase 0 or the Linux labs; do not use for unrelated Linux questions.
---

# VPS Linux Lab

Apply this skill from the repository root.

1. Read the root `AGENTS.md`, then check `docs/progress.md` and the relevant lab/runbook. Treat user/provider claims, live observations and unknowns as separate evidence classes.
2. For a VPS inventory, use `scripts/preflight.sh`; for SSH/auth/firewall/routes/listeners use `scripts/security-baseline.sh`; for Labs 01–06 use their matching `scripts/labNN-*.sh` source and `scripts/run-remote.ps1 -Phase lab-NN`. Inspect each script before the first run. Lab 03 must enforce its live memory/load/cgroup gates and transient-service cleanup; Labs 04–05 remain read-only; Lab 06 must use exact temporary paths and verify file/process cleanup. Use `scripts/validate.sh` with the matching phase; its public-service gate is separate from Linux labs.
3. Prefer SSH key-only client options for auth proof. Never print or persist private keys, passwords, tokens, full environment dumps, raw address/rule output or host identifiers. Summarize runtime evidence without source addresses.
4. Run remote scripts through `scripts/run-remote.ps1`. It uploads only the selected scripts to a unique remote `mktemp` directory, runs `bash -n` on each script separately and removes only that directory's script files. Keep exercises bounded and check cleanup. Do not install packages just to complete an optional utility exercise; record it as NOT TESTED instead.
5. Do not change SSH, firewall, network, packages, partitions, mounts or cluster state unless the user authorized that phase and its preconditions/rollback are documented. For remote firewall changes, require current provider/out-of-band access, backups of both `/etc/ufw` and `/etc/default/ufw`, a verified IPv4/IPv6 SSH allow path, rollback timer, second-session verification and explicit approval for that exact change. Keep emergency connectivity recovery separate from full configuration restore.
6. Treat `preflight.sh` and `security-baseline.sh` as inventories, not gate passes. `validate.sh` uses exit 0 for satisfied required gates, 1 for a required failure and 2 for missing required evidence; optional checks can remain NOT TESTED without blocking unrelated labs.
7. Update the canonical inventory, progress table and relevant lab/runbook after execution. Mark PASS only from observed output; keep provider firewall, external reachability and production readiness distinct.

Use `docs/infrastructure.md` for sanitized observed VPS facts, `docs/progress.md` for status, and `docs/runbooks/phase-0-preflight.md` plus `docs/runbooks/ssh-hardening.md` for the security workflow. Do not copy raw evidence or current host security posture into public files. For Docker Engine, Docker networking/storage or containerd phases, use `.agents/skills/container-runtime-lab/SKILL.md`.
