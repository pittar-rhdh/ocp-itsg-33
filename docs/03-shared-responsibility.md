# 03 — Shared Responsibility Model

[← Back to main](index.md)

An OpenShift platform meets ITSG-33 controls through a **stack of responsibilities**. To build a
clear SSP and an inheritance model for application teams, record who owns each control.

## Parties

| Party | Description |
|---|---|
| **Red Hat** | Builds and supports the product. Provides secure defaults, security errata, FIPS-capable cryptography, signed content, and product security documentation. |
| **Infrastructure** | The data centre, hypervisor (vSphere), bare-metal hosting, or cloud provider. Owns physical security, hardware, and underlying network and storage. For public cloud, this means CCCS-assessed services in Canadian regions. |
| **Platform** | The departmental (or shared services) team that installs, configures, and operates OpenShift. **Most of this guide is aimed at this party.** |
| **Tenant** | Application teams that deploy workloads on the platform. They inherit platform controls and implement application-level controls. |
| **Org** | Departmental security programme: policies, training, personnel security, the incident response organization, and the authorizer. |

## Responsibility by control family (self-managed OpenShift)

Legend: **P** = primary, **S** = supporting, **I** = inherited / not applicable at this layer

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

## Managed OpenShift (ROSA / ARO / OpenShift Dedicated)

With a managed offering, Red Hat (together with the cloud provider) takes on part of the
**Platform** responsibilities. These include control plane operations, upgrades, monitoring of
cluster health, and parts of incident response. Before relying on inheritance:

- Get the provider's **CCCS assessment** or equivalent attestation, and check which services and
  regions were assessed.
- Check which configuration you can still control (for example, FIPS, etcd encryption, audit log
  forwarding, and IdP configuration). Some controls in this guide can't be changed or work
  differently in a managed service.
- Review **SRE access** to clusters (MA-4, AC-17, PS-7) and the provider's audit log access for
  that activity.

## Tenant inheritance model

The platform should publish an **inheritance statement** for application teams. Here is an
example for some controls:

| Control | Inheritance | What the tenant still does |
|---|---|---|
| AC-2 Account Management | Partial | Manage application-level accounts. Request namespace RBAC through the platform process. |
| AC-4 Information Flow Enforcement | Partial | Define namespace `NetworkPolicy` for application tiers. The platform supplies default-deny and zone ANPs. |
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

Put the full inheritance view in the [control traceability matrix](05-control-traceability-matrix.md).
