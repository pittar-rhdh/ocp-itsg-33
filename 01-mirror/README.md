# 01-mirror — Phase 1: Content Mirroring (Low Side)

> **Examples only — not validated.** These scripts have not been run against a real Red Hat
> subscription or air-gapped environment. Read them, adapt them, and test them before use. See
> [validation status](../docs/reference/validation-status.md).

Scripts and configuration for building signed transfer packages on the connected mirror
workstation. Full guidance: [docs/01-mirroring](../docs/01-mirroring/index.md).

Run the scripts in order:

| Script | Purpose |
|---|---|
| `01-download-tools.sh [--install]` | Download and GPG-verify `oc`, `oc-mirror`, mirror registry, `roxctl` |
| `02-check-workstation.sh` | Readiness checks |
| `03-list-operator-channels.sh [pkg ...]` | Report available releases, channels, versions |
| `04-render-imageset-config.sh [--check]` | Generate `imageset-config.yaml` from `../versions.env` |
| `05-mirror-to-disk.sh [--dry-run] [--since yyyy-mm-dd]` | `oc-mirror --v2` mirror-to-disk |
| `06-download-rhacs-db.sh` | RHACS offline vulnerability data |
| `07-package-transfer.sh [--id ID] [--no-tools] [--no-content]` | Assemble, checksum, sign |
| `08-verify-transfer.sh <dir> [--key pub.asc]` | Verify a package (both sides) |

- **What** is mirrored: `../versions.env`. **Where** it is stored: `settings.env`, overridden by
  `settings.local.env` (git-ignored).
- `imageset-config.yaml` is generated. Don't edit it by hand.
