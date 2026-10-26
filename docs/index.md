# OpenShift 4.22 Reference Architecture for ITSG-33

> **Status:** Draft v0.1 — first iteration. Content is guidance and must be validated against your
> department's tailored security control profile, the official OpenShift 4.22 documentation, and
> your Security Assessment and Authorization (SA&A) process.

## Purpose

This reference architecture shows how **Red Hat OpenShift Container Platform (OCP) 4.22** can be
designed, configured, and operated to meet the security controls in the Canadian Centre for Cyber
Security (CCCS) publication **ITSG-33: IT Security Risk Management — A Lifecycle Approach**. It
focuses on the **Protected B / Medium Integrity / Medium Availability (PBMM)** profile (ITSG-33
Annex 4A, Profile 1) and its cloud successor, the **CCCS Medium Cloud Security Profile**.

For each relevant control, the guide records:

1. **What the control asks for**, in short form (see ITSG-33 Annex 3A for the authoritative text).
2. **Who is responsible**: Red Hat (product), the infrastructure provider, the platform team, or
   the application/tenant team.
3. **How OpenShift meets it**: the platform capabilities, operators, and design decisions involved.
4. **Configuration examples**: declarative YAML you can adapt and manage with GitOps.
5. **Evidence**: the commands, reports, and artifacts an assessor can review.

## Intended audience

- Platform architects and engineers designing OpenShift for Government of Canada (GC) workloads
- IT security practitioners and security assessors carrying out SA&A
- Departmental security officers (DSOs) and authorizers who need traceability from controls to
  implementation

## How to use this guide

1. Read the [ITSG-33 overview](01-itsg-33-overview.md) to see how ITSG-33 relates to NIST SP 800-53
   and why that matters for OpenShift tooling.
2. Review the [reference architecture](02-reference-architecture.md) for the target topology, network
   zoning, and supporting services.
3. Agree on the [shared responsibility model](03-shared-responsibility.md) with your infrastructure
   provider and application teams.
4. Set up [compliance automation and evidence collection](04-compliance-automation-and-evidence.md)
   early. Most technical controls can be checked continuously.
5. Work through the [control family guidance](controls/index.md) and record your implementation
   decisions.
6. Use the [control traceability matrix](05-control-traceability-matrix.md) as the starting point for
   your System Security Plan (SSP) and the Security Requirements Traceability Matrix (SRTM).

## Document map

| Document | Description |
|---|---|
| [01 — ITSG-33 overview](01-itsg-33-overview.md) | ITSG-33 structure, profiles, the link to NIST SP 800-53, and related CCCS guidance |
| [02 — Reference architecture](02-reference-architecture.md) | Target topology, network security zones, node roles, and supporting services |
| [03 — Shared responsibility model](03-shared-responsibility.md) | Who owns each control family, for self-managed and managed OpenShift |
| [04 — Compliance automation and evidence](04-compliance-automation-and-evidence.md) | Compliance Operator, ACM governance, RHACS, and evidence packaging |
| [05 — Control traceability matrix](05-control-traceability-matrix.md) | Control-by-control summary linked to the detailed guidance |
| [Control families](controls/index.md) | Detailed guidance for each ITSG-33 control family |
| [References](references.md) | ITSG-33, CCCS, TBS, and Red Hat references |

### Control family guidance

| Family | Name | Document |
|---|---|---|
| AC | Access Control | [controls/ac-access-control.md](controls/ac-access-control.md) |
| AU | Audit and Accountability | [controls/au-audit-and-accountability.md](controls/au-audit-and-accountability.md) |
| CA | Security Assessment and Authorization | [controls/ca-security-assessment-and-authorization.md](controls/ca-security-assessment-and-authorization.md) |
| CM | Configuration Management | [controls/cm-configuration-management.md](controls/cm-configuration-management.md) |
| CP | Contingency Planning | [controls/cp-contingency-planning.md](controls/cp-contingency-planning.md) |
| IA | Identification and Authentication | [controls/ia-identification-and-authentication.md](controls/ia-identification-and-authentication.md) |
| IR | Incident Response | [controls/ir-incident-response.md](controls/ir-incident-response.md) |
| RA | Risk Assessment | [controls/ra-risk-assessment.md](controls/ra-risk-assessment.md) |
| SA | System and Services Acquisition | [controls/sa-system-and-services-acquisition.md](controls/sa-system-and-services-acquisition.md) |
| SC | System and Communications Protection | [controls/sc-system-and-communications-protection.md](controls/sc-system-and-communications-protection.md) |
| SI | System and Information Integrity | [controls/si-system-and-information-integrity.md](controls/si-system-and-information-integrity.md) |
| AT, MA, MP, PE, PL, PM, PS | Operational and management families | [controls/operational-and-management-families.md](controls/operational-and-management-families.md) |

## Scope

**In scope**

- Self-managed OpenShift Container Platform 4.22 on bare metal, VMware vSphere, or a GC-approved
  public cloud region in Canada
- Red Hat OpenShift Platform Plus components: Red Hat Advanced Cluster Management (ACM), Red Hat
  Advanced Cluster Security (RHACS), and Red Hat Quay
- Layered operators that implement security functions, such as the Compliance Operator, File
  Integrity Operator, OpenShift Logging, OpenShift GitOps, cert-manager, and OADP
- Platform-level controls that application workloads inherit

**Out of scope (for this iteration)**

- Application-specific controls, such as application authentication and business logic
- OpenShift Virtualization, OpenShift AI, and service mesh specifics (they may be covered later)
- A full replacement for a departmental SSP, Threat and Risk Assessment (TRA), or SA&A package

## Key design principles

1. **Secure by default, hardened by profile.** Start from OpenShift's secure defaults (RHCOS,
   SELinux enforcing, `restricted-v2` SCC). Then apply a tailored compliance profile derived from
   the NIST SP 800-53 Moderate content that ships with the Compliance Operator.
2. **Everything as code.** Cluster configuration, policies, and compliance tailoring live in Git and
   are applied through GitOps. The Git history is configuration-management evidence.
3. **Continuous evidence.** Prefer controls that can be checked automatically and on a schedule over
   point-in-time screenshots.
4. **Defence in depth across zones.** Align cluster ingress and egress with the GC network security
   zone model (ITSP.80.022), and enforce default-deny traffic inside the cluster.
5. **Inherit, don't reinvent.** Application teams should inherit as many controls as possible from
   the platform, so each application's SA&A gets smaller.

## Conventions

- Control identifiers follow ITSG-33 Annex 3A (for example, `AC-2`, `AC-2(1)` for an enhancement).
- **Responsibility** labels:
  - `Red Hat`: built into the product
  - `Infrastructure`: hypervisor, cloud, or data centre provider
  - `Platform`: the team that runs OpenShift
  - `Tenant`: application teams
  - `Org`: departmental processes
- YAML examples target OpenShift 4.22 APIs. Always check API versions with
  `oc explain <kind> --api-version=<group/version>` before applying them.
- Placeholder values use `example.gc.ca` and `<angle-brackets>`.

## Roadmap

| Iteration | Planned content |
|---|---|
| v0.1 (this draft) | Architecture, responsibility model, family-level guidance with inline configuration snippets and evidence commands |
| v0.2 | A `config/` directory of Kustomize overlays (baseline, PBMM hardening, zone-specific ingress) deployable with OpenShift GitOps |
| v0.3 | A Compliance Operator `TailoredProfile` mapped to the PBMM control selections, plus an ACM `PolicyGenerator` set annotated with ITSG-33 controls |
| v0.4 | Evidence automation: scripts or pipelines that build an evidence bundle (scan results, configuration exports, policy reports) for each assessment cycle |
| v0.5 | Coverage for OpenShift Virtualization, service mesh, and disconnected or air-gapped installs |

## Disclaimer

This guide is not an official publication of Red Hat, the Canadian Centre for Cyber Security, or
the Treasury Board of Canada Secretariat. Meeting a control depends on the whole system, its
operating environment, and organizational processes. The departmental authorizer makes the final
call through the SA&A process.
