# Phase 1 — Content Mirroring (Low Side)

[← Back to main](../index.md)

> **Examples only — not validated.** The scripts and configuration in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

Build a complete, verifiable package of everything the high side needs: the OpenShift release,
the approved operators, additional images, tools, RHACS vulnerability data, and this
repository.

| | |
|---|---|
| **Where** | Low side (connected mirror workstation) |
| **Inputs** | Red Hat pull secret; [`versions.env`](../reference/versions.md); a transfer signing key |
| **Outputs** | One signed transfer package per import (see [Packaging and transfer](packaging-and-transfer.md)) and a completed transfer record |
| **Hands off to** | [Phase 2 — High-side setup](../02-high-side/index.md) |
| **Decisions** | AD-02, AD-15, AD-19, AD-20 ([Architecture decisions](../00-architecture/architecture-decisions.md)) |
| **Key controls** | CM-3, CM-11, SA-12, SI-7, MP-2, MP-4, MP-5, SI-2, RA-5(2) |

## Workflow

```text
 versions.env ──(04 render)──> imageset-config.yaml ──(PR review, commit)──┐
                                                                            v
 01 download-tools ─> 02 check-workstation ─> 05 mirror-to-disk ─> 07 package-transfer ─> media ─> 08 verify
   (GPG-verified        (readiness gate)       (oc-mirror v2)        (SHA256SUMS + GPG     (copy)    (before it
    oc, oc-mirror,                                                    signature + record)              leaves)
    mirror-registry,     06 download-rhacs-db ─────────────────────────────^
    roxctl)              (daily if possible)
```

## Quick start

All scripts live in [`01-mirror/`](https://github.com/pittar-rhdh/ocp-itsg-33/tree/main/01-mirror)
and read `versions.env` (what to mirror) and `01-mirror/settings.env` (where to store it).

```bash
# One-time workstation setup (see "Mirror workstation")
01-mirror/01-download-tools.sh --install
01-mirror/02-check-workstation.sh

# Decide what to mirror (see "ImageSetConfiguration")
01-mirror/03-list-operator-channels.sh          # review the live catalogs
vi versions.env                                 # pin versions and channels
01-mirror/04-render-imageset-config.sh          # regenerate imageset-config.yaml
git commit -am "Pin content for import <id>"    # through a reviewed pull request

# Mirror, package, verify (see "Mirror to disk" and "Packaging and transfer")
01-mirror/05-mirror-to-disk.sh --dry-run        # optional: see what would be mirrored
01-mirror/05-mirror-to-disk.sh
01-mirror/06-download-rhacs-db.sh               # if RHACS_VERSION is set
01-mirror/07-package-transfer.sh --id T-20261106-01
01-mirror/08-verify-transfer.sh /media/transfer/T-20261106-01 --key transfer-key.pub.asc
```

## Pages

| Page | Content |
|---|---|
| [Mirror workstation](workstation.md) | Host build, tools, pull secret, storage sizing, transfer signing key |
| [ImageSetConfiguration](imageset-configuration.md) | How `versions.env` becomes `imageset-config.yaml`; choosing channels and versions |
| [Mirror to disk](mirror-to-disk.md) | Running `oc-mirror` v2, cache and history, incremental runs, optional signature verification |
| [Packaging and transfer](packaging-and-transfer.md) | Package layout, checksums and signature, media, chain of custody, verification |
| [Ongoing imports](ongoing-imports.md) | Cadence, z-stream and operator updates, RHACS feeds, emergency imports, record keeping |

## Repository files

| File | Purpose |
|---|---|
| `versions.env` (repository root) | What is mirrored: OpenShift versions, operators, images, tool versions |
| `01-mirror/settings.env` | Where data is stored on the workstation; signing and verification settings |
| `01-mirror/imageset-config.yaml` | Generated `ImageSetConfiguration` (committed; do not edit by hand) |
| `01-mirror/01-download-tools.sh` | Download and verify `oc`, `oc-mirror`, mirror registry, and `roxctl` |
| `01-mirror/02-check-workstation.sh` | Readiness checks for the workstation |
| `01-mirror/03-list-operator-channels.sh` | Report of available releases, channels, and versions |
| `01-mirror/04-render-imageset-config.sh` | Render (or `--check`) `imageset-config.yaml` |
| `01-mirror/05-mirror-to-disk.sh` | Run `oc-mirror --v2` mirror-to-disk |
| `01-mirror/06-download-rhacs-db.sh` | Download RHACS offline vulnerability data |
| `01-mirror/07-package-transfer.sh` | Assemble, checksum, and sign a transfer package |
| `01-mirror/08-verify-transfer.sh` | Verify a transfer package (low side and high side) |
| `01-mirror/signature-policy.json` | Optional image signature policy for mirroring |
| `01-mirror/templates/transfer-record.md` | Chain-of-custody record template |

## How this phase supports ITSG-33

| Control | How |
|---|---|
| CM-3 Configuration change control | Content changes are made in `versions.env` and the generated `imageset-config.yaml`, reviewed as pull requests |
| CM-11 User-installed software / SA-12 Supply chain protection | Only content listed in the reviewed configuration is mirrored; binaries are verified against Red Hat's signing key |
| SI-7 Software and information integrity | Every transfer carries a SHA-256 manifest signed by the transfer key, verified before and after transfer |
| MP-2, MP-4, MP-5 Media access, storage, transport | The transfer record documents approvals, media, custody hand-offs, receipt, and disposition |
| SI-2 Flaw remediation / RA-5(2) Update vulnerability data | A defined import cadence, with emergency imports and frequent (ideally daily) RHACS feeds |
