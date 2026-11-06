# 02-high-side — Phase 2: High-Side Setup

> **Examples only — not validated.** These scripts have not been run against a real Red Hat
> subscription or air-gapped environment. Read them, adapt them, and test them before use. See
> [validation status](../docs/reference/validation-status.md).

Scripts for the registry host on the air-gapped high side. Run them as the unprivileged registry
service account (`sudo -iu quay`), not root. Full guidance:
[docs/02-high-side](../docs/02-high-side/index.md).

| Script | When | Purpose |
|---|---|---|
| `01-accept-transfer.sh <dir> [--key k] [--allow-out-of-order reason]` | Every transfer | Verify, order-check, copy, ledger; unpack tools |
| `02-check-registry-host.sh [--tls-only]` | Before install; monthly | Host readiness and certificate checks |
| `03-install-mirror-registry.sh [--upgrade]` | Once; upgrades | Install the mirror registry (rootless), then harden |
| `04-harden-mirror-registry.sh [--check] [--rotate-cert]` | After install/upgrade; monthly | Apply/verify hardening; certificate rotation |
| `05-configure-registry-access.sh [--rotate robot]` | Once; token rotation | Robot accounts, team, default permissions, credential files |
| `06-disk-to-mirror.sh <id> [--dry-run]` | Every content transfer | `oc-mirror --v2` import; cluster resources per import |
| `07-extract-installer.sh [version]` | New release | Extract `openshift-install-fips` pinned to the release digest |
| `08-publish-repo.sh <id> [--no-push]` | Every transfer | Fast-forward departmental Git from the transfer's bundle |

Settings: `settings.env`, overridden by `settings.local.env` (git-ignored) or exported variables.
