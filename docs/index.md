# OpenShift 4.22 on Bare Metal, Air-Gapped, for ITSG-33

> **Status:** Draft v0.4 — Phase 0 (architecture), Phase 1 (content mirroring), Phase 2 (high-side
> setup), and the ITSG-33 control guidance are written; the other phases are planned.

> **Examples only — not validated.** Everything in this repository (scripts, configuration,
> procedures) is an **example**. None of it has been run end to end against a real Red Hat
> subscription, a real air-gapped environment, real bare-metal hardware, or a real OpenShift
> cluster. Review, adapt, and test it in a non-production environment, and check it against the
> official Red Hat documentation for your exact versions, before relying on it. It must also be
> validated against your department's tailored security control profile and your Security
> Assessment and Authorization (SA&A) process. See [Validation status and sources](reference/validation-status.md)
> for what was and wasn't tested.

## Purpose

A **lightweight, prescriptive reference implementation** for running
**Red Hat OpenShift Container Platform (OCP) 4.22** on **bare metal** in an **air-gapped**
environment, configured and evidenced against the Canadian Centre for Cyber Security (CCCS)
**ITSG-33** controls for **Protected B / Medium Integrity / Medium Availability (PBMM)** (ITSG-33
Annex 4A, Profile 1).

It covers the whole path, from mirroring content on the connected low side to operating a
compliant cluster on the high side:

```text
 Phase 1            Phase 2              Phase 3              Phase 4               Phase 5              Phase 6
 Mirror content --> Set up high side --> Install cluster --> Configure ITSG-33 --> Report & evidence --> Operate (SOPs)
 (low side)         (registry, Git)      (bare-metal IPI)    (GitOps, policies)    (scans, bundles)     (Day 2, upgrades)
```

## The reference deployment

| Aspect | Choice |
|---|---|
| Platform | Bare metal, installer-provisioned infrastructure (IPI) |
| Provisioning | Redfish virtual media (primary) or PXE with a provisioning network (alternative) |
| Topology | One HA cluster: 3 control plane nodes + 3..N workers |
| Connectivity | Air-gapped; content moved with `oc-mirror` v2 through a controlled transfer |
| High-side registry | mirror registry for Red Hat OpenShift on a dedicated RHEL 9 host |
| Configuration | OpenShift GitOps from the departmental Git server; ACM governance on the same cluster |
| Security tooling | Compliance Operator, File Integrity Operator, RHACS, OpenShift Logging, cert-manager, External Secrets |
| Storage | Enterprise storage through a vendor CSI driver; S3-compatible object storage for logs and backups |
| Cryptography | FIPS mode, LUKS disk encryption, IPsec east-west, departmental PKI |

The reasons for each choice, and the alternatives, are in
[Architecture decisions](00-architecture/architecture-decisions.md).

## Phases

| Phase | Where | Status | Start here |
|---|---|---|---|
| **0 — Architecture** | — | Written | [Reference architecture](00-architecture/reference-architecture.md) |
| **1 — Content mirroring** | Low side | Written (examples, not validated) | [Phase 1](01-mirroring/index.md) |
| **2 — High-side setup** | High side | Written (examples, not validated) | [Phase 2](02-high-side/index.md) |
| **3 — Bare-metal IPI install** | High side | Planned | [Phase 3](03-cluster-install/index.md) |
| **4 — ITSG-33 configuration as code** | High side | Control guidance available; GitOps planned | [Phase 4](04-itsg33-configuration/index.md) |
| **5 — Compliance reporting and evidence** | High side | Guidance available; automation planned | [Phase 5](05-compliance-evidence/index.md) |
| **6 — Standard operating procedures** | Both | Planned | [Phase 6](06-sops/index.md) |

Each phase page lists its **inputs**, **outputs**, the **architecture decisions** it depends on,
and the **ITSG-33 controls** it supports, so each phase hands off cleanly to the next.

## Intended audience

- Platform architects and engineers deploying OpenShift for Government of Canada (GC) workloads
  in disconnected environments
- IT security practitioners and security assessors carrying out SA&A
- Departmental security officers (DSOs) and authorizers who need traceability from controls to
  implementation
- Operators who run the platform day to day

## How to use this guide

1. Read the [ITSG-33 overview](00-architecture/itsg-33-overview.md) to see how ITSG-33 relates to
   NIST SP 800-53, and why that matters for OpenShift tooling.
2. Review the [reference architecture](00-architecture/reference-architecture.md) and agree on the
   [architecture decisions](00-architecture/architecture-decisions.md) marked **Department**.
3. Agree on the [shared responsibility model](00-architecture/shared-responsibility.md) with the
   infrastructure, shared-services, and content-transfer teams.
4. Work through Phases 1 to 5 in order. Keep the records each phase produces; they are evidence.
5. Use the [control traceability matrix](05-compliance-evidence/control-traceability-matrix.md)
   as the starting point for your System Security Plan (SSP) and Security Requirements
   Traceability Matrix (SRTM).
6. Run the platform with the [SOPs](06-sops/index.md).

## Repository layout

```text
docs/                         Documentation (published with TechDocs / MkDocs)
  00-architecture/            ITSG-33 overview, reference architecture, decisions, shared responsibility
  01-mirroring/ .. 06-sops/   One section per phase
  reference/                  Versions, references, backlog
versions.env                  Single source of truth for versions, operators, and images
lib/common.sh                 Helpers shared by the scripts of every phase
01-mirror/                    Phase 1 scripts, generated imageset-config.yaml, transfer record template
02-high-side/                 Phase 2 scripts (accept, registry install/hardening/access, import, installer)
03-install/ .. 05-evidence/   Configuration and scripts for later phases (added as they are built)
```

See [Versions and pinned content](reference/versions.md) for how `versions.env` is used.

## Scope

**In scope**

- Self-managed OpenShift Container Platform 4.22 on bare metal, installed with IPI, in an
  air-gapped environment
- Red Hat OpenShift Platform Plus components used on the cluster: Red Hat Advanced Cluster
  Management (ACM) and Red Hat Advanced Cluster Security (RHACS)
- Layered operators that implement security functions, such as the Compliance Operator, File
  Integrity Operator, OpenShift Logging, OpenShift GitOps, cert-manager, External Secrets, and OADP
- Platform-level controls that application workloads inherit

**Out of scope (for now)**

- Other platforms (vSphere, public cloud) and managed OpenShift (ROSA, ARO)
- OpenShift Virtualization and service mesh specifics
- AI workloads (GPU operators, OpenShift AI) — tracked in the [backlog](reference/backlog.md)
- Application-specific controls, such as application authentication and business logic
- Building the high-side supporting services (Git, IdP, PKI, SIEM, storage); they are assumed to
  exist
- A full replacement for a departmental SSP, Threat and Risk Assessment (TRA), or SA&A package

## Key design principles

1. **Lightweight.** One cluster, one registry host, and existing departmental services. Add
   components only when a control or a decision requires them.
2. **One-way, verifiable supply chain.** Every image, binary, and configuration file on the high
   side arrives through a recorded, checksummed, and signed transfer (SA-12, SI-7, CM-11).
3. **Secure by default, hardened by profile.** Start from OpenShift's secure defaults (RHCOS,
   SELinux enforcing, `restricted-v2` SCC). Set install-time-only protections (FIPS, disk
   encryption) on day one. Then apply a tailored compliance profile derived from the NIST SP 800-53
   Moderate content that ships with the Compliance Operator.
4. **Everything as code.** Versions, cluster configuration, policies, and compliance tailoring live
   in Git and are applied through GitOps. The Git history is configuration-management evidence.
5. **Continuous evidence.** Prefer controls that can be checked automatically and on a schedule
   over point-in-time screenshots.
6. **Inherit, don't reinvent.** Application teams should inherit as many controls as possible from
   the platform, so each application's SA&A gets smaller.

## Control family guidance

| Family | Name | Document |
|---|---|---|
| AC | Access Control | [ac-access-control.md](04-itsg33-configuration/controls/ac-access-control.md) |
| AU | Audit and Accountability | [au-audit-and-accountability.md](04-itsg33-configuration/controls/au-audit-and-accountability.md) |
| CA | Security Assessment and Authorization | [ca-security-assessment-and-authorization.md](04-itsg33-configuration/controls/ca-security-assessment-and-authorization.md) |
| CM | Configuration Management | [cm-configuration-management.md](04-itsg33-configuration/controls/cm-configuration-management.md) |
| CP | Contingency Planning | [cp-contingency-planning.md](04-itsg33-configuration/controls/cp-contingency-planning.md) |
| IA | Identification and Authentication | [ia-identification-and-authentication.md](04-itsg33-configuration/controls/ia-identification-and-authentication.md) |
| IR | Incident Response | [ir-incident-response.md](04-itsg33-configuration/controls/ir-incident-response.md) |
| RA | Risk Assessment | [ra-risk-assessment.md](04-itsg33-configuration/controls/ra-risk-assessment.md) |
| SA | System and Services Acquisition | [sa-system-and-services-acquisition.md](04-itsg33-configuration/controls/sa-system-and-services-acquisition.md) |
| SC | System and Communications Protection | [sc-system-and-communications-protection.md](04-itsg33-configuration/controls/sc-system-and-communications-protection.md) |
| SI | System and Information Integrity | [si-system-and-information-integrity.md](04-itsg33-configuration/controls/si-system-and-information-integrity.md) |
| AT, MA, MP, PE, PL, PM, PS | Operational and management families | [operational-and-management-families.md](04-itsg33-configuration/controls/operational-and-management-families.md) |

## Conventions

- Control identifiers follow ITSG-33 Annex 3A (for example, `AC-2`, `AC-2(1)` for an enhancement).
- **Responsibility** labels:
  - `Red Hat`: built into the product
  - `Infrastructure`: data centre, hardware, network, and storage
  - `Platform`: the team that runs OpenShift
  - `Tenant`: application teams
  - `Org`: departmental processes
- Architecture decisions are referenced as `AD-nn`.
- YAML examples target OpenShift 4.22 APIs. Always check API versions with
  `oc explain <kind> --api-version=<group/version>` before applying them.
- Placeholder values use `example.gc.ca` and `<angle-brackets>`.

## Disclaimer

This guide is not an official publication of Red Hat, the Canadian Centre for Cyber Security, or
the Treasury Board of Canada Secretariat. Meeting a control depends on the whole system, its
operating environment, and organizational processes. The departmental authorizer makes the final
call through the SA&A process.
