# Shared Responsibility Model

[← Back to main](../index.md)

An OpenShift platform meets ITSG-33 controls through a **stack of responsibilities**. To build a
clear SSP and an inheritance model for application teams, record who owns each control.

## Parties

| Party | Description |
|---|---|
| **Red Hat** | Builds and supports the product. Provides secure defaults, security errata, FIPS-capable cryptography, signed content, and product security documentation. |
| **Infrastructure** | The departmental data centre team. Owns physical security, bare-metal servers and their BMCs and firmware, the data centre network (switches, firewalls, load balancers), and enterprise storage. |
| **Shared services** | Teams that run the high-side services the platform depends on: Git, IdP, PKI, SIEM, DNS, NTP, and S3-compatible object storage. |
| **Content transfer** | The people and process that move content from the low side to the high side (media custodians, transfer approvers, or the cross-domain solution operator). |
| **Platform** | The departmental (or shared services) team that installs, configures, and operates OpenShift. **Most of this guide is aimed at this party.** |
| **Tenant** | Application teams that deploy workloads on the platform. They inherit platform controls and implement application-level controls. |
| **Org** | Departmental security programme: policies, training, personnel security, the incident response organization, and the authorizer. |

## Responsibility by control family

Legend: **P** = primary, **S** = supporting, **I** = inherited / not applicable at this layer.
Shared services and content transfer are folded into **Infrastructure** and **Org** in this table;
see the next section for the air-gap specifics.

| Family | Red Hat | Infrastructure | Platform | Tenant | Org |
|---|---|---|---|---|---|
| AC — Access Control | S | S | **P** | **P** (app-level) | S |
| AT — Awareness and Training | I | I | S | S | **P** |
| AU — Audit and Accountability | S | S | **P** | S | S |
| CA — Security Assessment and Authorization | S | S | **P** | S | **P** |
| CM — Configuration Management | S | S | **P** | **P** (workloads) | S |
| CP — Contingency Planning | I | **P** | **P** | **P** (app data) | **P** |
| IA — Identification and Authentication | S | I | **P** | S | **P** (IdP) |
| IR — Incident Response | S | S | **P** | S | **P** |
| MA — Maintenance | S | **P** | **P** | I | S |
| MP — Media Protection | I | **P** | S | I | **P** |
| PE — Physical and Environmental | I | **P** | I | I | S |
| PL — Planning | I | I | **P** | S | **P** |
| PM — Program Management | I | I | S | I | **P** |
| PS — Personnel Security | I | S | S | S | **P** |
| RA — Risk Assessment | S | S | **P** | **P** | **P** |
| SA — System and Services Acquisition | **P** (product SDLC) | S | **P** | **P** (app SDLC) | **P** |
| SC — System and Communications Protection | S | S | **P** | S | S |
| SI — System and Information Integrity | **P** (errata) | S | **P** | **P** (images) | S |

## Responsibilities specific to the air-gapped, bare-metal design

| Area | Primary | Supporting | Notes |
|---|---|---|---|
| Choosing what content to mirror (`ImageSetConfiguration`) | Platform | Org (approval) | Changes go through change control (CM-3) |
| Low-side mirroring and integrity (checksums, signatures) | Platform | Content transfer | SA-12, SI-7 |
| Media handling and transfer records | Content transfer | Org | MP-2, MP-4, MP-5 |
| Mirror registry host (OS hardening, patching, backup) | Platform | Infrastructure | CM-6, CP-9, SI-2 |
| BMC firmware, credentials, and network isolation | Infrastructure | Platform | MA-2, AC-17, SC-7 |
| Node hardware lifecycle and media sanitization at disposal | Infrastructure | Org | MA-2, MP-6 |
| Supporting services (Git, IdP, PKI, SIEM, DNS, NTP, S3, storage) | Shared services | Platform | Each service carries its own SA&A; the platform inherits from it |
| RHACS offline vulnerability feeds and import cadence | Platform | Org | RA-5, SI-2, SI-5 |
| Support data leaving the high side (`must-gather`) | Platform | Org | Review and sanitize before release (MA-4, MP-5) |

> **Managed OpenShift** (ROSA, ARO, OpenShift Dedicated) is out of scope: those services need a
> connection to Red Hat and the cloud provider and don't fit an air-gapped design.

## Tenant inheritance model

The platform should publish an **inheritance statement** for application teams. Here is an
example for some controls:

| Control | Inheritance | What the tenant still does |
|---|---|---|
| AC-2 Account Management | Partial | Manage application-level accounts. Request namespace RBAC through the platform process. |
| AC-4 Information Flow Enforcement | Partial | Define namespace `NetworkPolicy` for application tiers. The platform supplies default-deny, zone ANPs, and a primary CUDN per zone. Request the right zone when the namespace is created, because it can't be changed later. |
| AU-2 / AU-12 Auditable Events / Audit Generation | Partial | Write application security events to stdout/stderr in a structured format. |
| AU-9 Protection of Audit Information | Full | — |
| CM-6 Configuration Settings | Partial | Harden container images and manifests (non-root, read-only root filesystem, no privilege escalation). |
| CP-9 Information System Backup | Partial | Label namespaces and PVCs for backup. Test application-consistent restores. |
| IA-2 Identification and Authentication | Full (platform access) | Application end-user authentication |
| SC-8 Transmission Confidentiality | Partial | Use TLS for routes (edge, re-encrypt, or passthrough). Use mTLS between services if required. |
| SC-13 Cryptographic Protection | Partial | Use the platform's FIPS crypto libraries. Don't bundle non-validated crypto. |
| SC-28 Protection of Information at Rest | Partial | Use encrypted storage classes. Encrypt application data where needed. |
| SI-2 Flaw Remediation | Partial | Rebuild and redeploy images when RHACS reports fixable CVEs. |
| SI-4 Information System Monitoring | Full | — |

Put the full inheritance view in the [control traceability matrix](../05-compliance-evidence/control-traceability-matrix.md).
