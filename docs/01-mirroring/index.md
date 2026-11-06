# Phase 1 — Content Mirroring (Low Side)

[← Back to main](../index.md)

> **Examples only — not validated.** The commands and configuration files in this phase are
> examples. They have not been run end to end against a real Red Hat subscription, air-gapped
> environment, or cluster. Test and adapt them before use. See
> [Validation status](../reference/validation-status.md).

Build a complete, verifiable package of everything the high side needs: the OpenShift release,
the approved operators, additional images, tools, RHACS vulnerability data, and this
repository.

| | |
|---|---|
| **Where** | Low side (connected mirror workstation) |
| **Inputs** | Red Hat pull secret; `01-mirror/imageset-config.yaml` (what to mirror); [Versions and pinned content](../reference/versions.md); a transfer signing key |
| **Outputs** | One signed transfer package per import (see [Packaging and transfer](packaging-and-transfer.md)) and a completed transfer record |
| **Hands off to** | [Phase 2 — High-side setup](../02-high-side/index.md) |
| **Decisions** | AD-02, AD-15, AD-19, AD-20 ([Architecture decisions](../00-architecture/architecture-decisions.md)) |
| **Key controls** | CM-3, CM-11, SA-12, SI-7, MP-2, MP-4, MP-5, SI-2, RA-5(2) |

## Workflow

```text
 oc-mirror list operators ─> edit imageset-config.yaml ─> pull request review, commit ─┐
                                                                                        v
 download + GPG-verify tools ─> workstation checks ─> oc-mirror --v2 (mirror-to-disk) ─> package ─> media ─> verify
   (oc, oc-mirror,                                                                     (SHA256SUMS,  (copy)   (before it
    mirror-registry,               roxctl scanner download-db ──────────────────────────^ GPG signature,       leaves)
    butane, roxctl)                (daily if possible)                                  git bundle, record)
```

## Quick start

The examples use `/data/mirror` for data and `4.22.18` for the release; see
[Versions and pinned content](../reference/versions.md) for the pinned versions.

```bash
# One-time setup (see "Mirror workstation")
mkdir -p /data/mirror/{tools,cache,archive,rhacs,transfers}
#   download and verify oc, oc-mirror, mirror-registry, butane, roxctl; generate the transfer key

# Decide what to mirror (see "ImageSetConfiguration")
oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.22 \
  --package=compliance-operator --v2
vi 01-mirror/imageset-config.yaml
git commit -am "Pin content for import T-20261106-01"     # through a reviewed pull request

# Mirror (see "Mirror to disk")
umask 0022
oc-mirror --v2 --config 01-mirror/imageset-config.yaml \
  --cache-dir /data/mirror/cache --authfile ~/.secrets/pull-secret.json \
  file:///data/mirror/archive
roxctl scanner download-db --version <rhacs-version> --skip-central --force \
  --scanner-db-file /data/mirror/rhacs/scanner-vuln-updates-<rhacs-version>-$(date -u +%Y%m%d).zip

# Package, sign, verify (see "Packaging and transfer")
#   move archives into /data/mirror/transfers/<transfer-id>/, add config, tools, git bundle,
#   write SHA256SUMS, sign it, then verify the copy on the media:
gpgv --keyring /tmp/transfer-key.gpg SHA256SUMS.asc SHA256SUMS
sha256sum --check --strict SHA256SUMS
```

## Pages

| Page | Content |
|---|---|
| [Mirror workstation](workstation.md) | Host build, tool downloads and verification, pull secret, storage sizing, transfer signing key, readiness checks |
| [ImageSetConfiguration](imageset-configuration.md) | What `imageset-config.yaml` contains; choosing channels and versions |
| [Mirror to disk](mirror-to-disk.md) | Running `oc-mirror` v2, cache and history, incremental runs, optional signature verification, RHACS data |
| [Packaging and transfer](packaging-and-transfer.md) | Package layout, checksums and signature, media, chain of custody, verification |
| [Ongoing imports](ongoing-imports.md) | Cadence, z-stream and operator updates, RHACS feeds, emergency imports, record keeping |

## Repository files

| File | Purpose |
|---|---|
| `01-mirror/imageset-config.yaml` | Example `ImageSetConfiguration`: the reviewed source of truth for mirrored content |
| `01-mirror/signature-policy.json` | Optional image signature policy for mirroring |
| `01-mirror/transfer-record.md` | Chain-of-custody record template |

## How this phase supports ITSG-33

| Control | How |
|---|---|
| CM-3 Configuration change control | Content changes are made in `imageset-config.yaml` and reviewed as pull requests |
| CM-11 User-installed software / SA-12 Supply chain protection | Only content listed in the reviewed configuration is mirrored; binaries are verified against Red Hat's signing key |
| SI-7 Software and information integrity | Every transfer carries a SHA-256 manifest signed by the transfer key, verified before and after transfer |
| MP-2, MP-4, MP-5 Media access, storage, transport | The transfer record documents approvals, media, custody hand-offs, receipt, and disposition |
| SI-2 Flaw remediation / RA-5(2) Update vulnerability data | A defined import cadence, with emergency imports and frequent (ideally daily) RHACS feeds |
