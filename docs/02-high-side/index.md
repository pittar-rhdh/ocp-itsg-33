# Phase 2 — High-Side Setup

[← Back to main](../index.md)

> **Examples only — not validated.** The scripts and configuration in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

Prepare the air-gapped environment: accept the transfer, build and harden the registry host,
install the mirror registry, populate it, and produce everything the cluster install needs.

| | |
|---|---|
| **Where** | High side: registry host in the MRZ |
| **Inputs** | A Phase 1 [transfer package](../01-mirroring/packaging-and-transfer.md#package-layout); the transfer public key (delivered out of band); departmental DNS, NTP, PKI, and Git |
| **Outputs** | Hardened, populated mirror registry with departmental TLS; pull-only cluster credentials; generated cluster resources (IDMS, ITMS, catalogs, release signatures, update graph); FIPS-capable `openshift-install-fips` pinned to the release digest; this repository on departmental Git; the import ledger |
| **Hands off to** | [Phase 3 — Cluster install](../03-cluster-install/index.md) |
| **Decisions** | AD-10, AD-12, AD-15, AD-18, AD-21 ([Architecture decisions](../00-architecture/architecture-decisions.md)) |
| **Key controls** | AC-2, AC-3, AC-6, CM-6, CM-7, CM-11, IA-5, SC-8, SC-12, SC-17, SI-7, AU-2 |

## Workflow

```text
 media ──> 01 accept-transfer ──> 08 publish-repo ──> departmental Git
            (verify, order,  │
             ledger, tools)  │
                             v
 02 check-registry-host ──> 03 install-mirror-registry ──> 04 harden ──> 05 configure-access
  (OS, FIPS, DNS, NTP,        (rootless, departmental      (no anonymous,   (org, robots,
   storage, certificate)       certificate)                 no sign-up, TLS)  pull secret)
                                                                                  │
                             06 disk-to-mirror  <─────────────────────────────────┘
                              (oc-mirror v2, cluster-resources/<ID>)
                                     │
                             07 extract-installer ──> Phase 3
                              (openshift-install-fips, release.env)
```

Steps 02–05 run once (and again for upgrades or certificate rotation). Steps 01, 06, and 08 run
for every transfer.

## Quick start

All scripts live in [`02-high-side/`](https://github.com/pittar-rhdh/ocp-itsg-33/tree/main/02-high-side)
and read `versions.env` and `02-high-side/settings.env` (override in `settings.local.env`).

```bash
# First transfer: verify by hand and clone the repository from the bundle (see "Accept a transfer")
02-high-side/01-accept-transfer.sh /run/media/transfer/T-20261106-01
02-high-side/08-publish-repo.sh T-20261106-01

# One-time registry setup (see "Registry host" and "Mirror registry")
02-high-side/02-check-registry-host.sh
02-high-side/03-install-mirror-registry.sh            # also runs 04-harden-mirror-registry.sh
#   -> create organization "mirror" and an OAuth token in the registry UI
02-high-side/05-configure-registry-access.sh

# Populate (see "Populate the registry")
02-high-side/06-disk-to-mirror.sh T-20261106-01
02-high-side/07-extract-installer.sh
```

## Pages

| Page | Content |
|---|---|
| [Registry host](registry-host.md) | Host build, service account, storage, firewall, audit, hardening baseline, supporting services checklist |
| [Accept a transfer](accept-transfer.md) | Bootstrapping the first transfer, verification, ordering, the import ledger, re-baselining |
| [Mirror registry](mirror-registry.md) | Installation, hardening, access model (robot accounts), certificates, upgrades, backup |
| [Populate the registry](populate-registry.md) | Disk-to-mirror, the generated cluster resources, extracting the installer, publishing the repository |

## Repository files

| File | Purpose |
|---|---|
| `02-high-side/settings.env` | Registry name and port, TLS files, storage paths, credential files, Git remote |
| `02-high-side/01-accept-transfer.sh` | Verify, order-check, copy, and record a transfer; unpack tools |
| `02-high-side/02-check-registry-host.sh` | Readiness and periodic compliance check of the host (`--tls-only` for the certificate) |
| `02-high-side/03-install-mirror-registry.sh` | Install or `--upgrade` the mirror registry (rootless) |
| `02-high-side/04-harden-mirror-registry.sh` | Apply, `--check`, and verify registry hardening; `--rotate-cert` |
| `02-high-side/05-configure-registry-access.sh` | Robot accounts, team, default permissions, credential files; `--rotate` |
| `02-high-side/06-disk-to-mirror.sh` | `oc-mirror --v2` disk-to-mirror and cluster resources per transfer |
| `02-high-side/07-extract-installer.sh` | Extract `openshift-install-fips` pinned to the mirrored release |
| `02-high-side/08-publish-repo.sh` | Fast-forward the departmental Git repository from the transfer's bundle |
| `lib/common.sh` | Helpers shared by all phases |

## How this phase supports ITSG-33

| Control | How |
|---|---|
| SI-7, SA-12 Integrity and supply chain | Every transfer is verified on the media and again after copying; tools come only from verified transfers; the installer is pinned to a release digest with a mirrored signature |
| CM-3 Change control | Transfers are imported in build order and recorded in an append-only ledger; Git is fast-forwarded only from reviewed low-side history |
| AC-2, AC-3, AC-6 Accounts and least privilege | No self-registration or anonymous pulls; one break-glass administrator; separate push-only and pull-only robot accounts; the cluster never receives push credentials |
| IA-5 Authenticator management | Robot tokens are generated by the registry, stored mode `0600`, verified, and rotatable |
| SC-8, SC-12, SC-13, SC-17 Transport and PKI | Departmental certificate checked for name, chain, key size, algorithm, and expiry; TLS 1.2/1.3 only; host in FIPS mode |
| CM-6, CM-7 Configuration and least functionality | Hardened registry settings applied idempotently with drift detection; repository mirroring disabled |
| AU-2, AU-12 Audit | Host auditd and the registry's journald logs forwarded to the SIEM; hardening and import records kept |
