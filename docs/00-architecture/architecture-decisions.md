# Architecture Decisions

[← Back to main](../index.md) · [Reference architecture](reference-architecture.md)

This page records the decisions that shape the reference deployment. Each one is an input to the
System Security Plan (PL-2) and the TRA. Decisions marked **Decided** are fixed for this
repository. Decisions marked **Department** must be made by each adopting department. Record your
choice, the rationale, and the approver.

| Status | Meaning |
|---|---|
| **Decided** | Fixed for this reference implementation. The procedures and configuration assume it. |
| **Default** | The repository uses this option, but documents how to change it. |
| **Department** | No default. Each department must decide and record its choice. |

## Decision log

| ID | Decision | Choice in this repository | Status | Alternatives | Related controls |
|---|---|---|---|---|---|
| AD-01 | Deployment platform | Bare metal, installer-provisioned infrastructure (IPI) | Decided | Agent-based installer; UPI | CM-2, CM-8 |
| AD-02 | Connectivity | Air-gapped high side; content mirrored with `oc-mirror` v2 | Decided | Connected through a proxy | SA-9, SA-12, CM-11, SC-7 |
| AD-03 | Authentication model | Built-in OAuth server with an OIDC identity provider | Department | Direct authentication with an external OIDC provider | IA-2, IA-5, AC-2 |
| AD-04 | Cluster tenancy and management plane | Single HA cluster (3 control plane + 3..N workers); ACM and RHACS run on the same cluster | Decided | Separate management (hub) cluster; one cluster per security domain | SC-2, SC-3, CA-7 |
| AD-05 | East-west encryption | OVN-Kubernetes IPsec `Full`, enabled at install time | Default | IPsec `External`; none (with TRA justification) | SC-8, SC-13 |
| AD-06 | Disk encryption key source | LUKS bound to TPM2 | Default | Tang (NBDE); TPM2 and Tang together | SC-28, SC-12 |
| AD-07 | Log destination and retention | Departmental SIEM, plus LokiStack for short-term search | Department | SIEM only | AU-4, AU-9, AU-11 |
| AD-08 | Telemetry and remote health reporting | Disabled (no path to Red Hat from the high side) | Decided | — | SA-9 |
| AD-09 | Network isolation model (per zone or tenant) | Tier 1 policy isolation by default; tier 2 CUDN per zone where the TRA requires it | Department | Tier 3 separate cluster; BGP route advertisement (VRF-lite / EVPN) | AC-4, SC-7 |
| AD-10 | High-side registry | mirror registry for Red Hat OpenShift on a dedicated RHEL 9 registry host | Decided | Red Hat Quay (operator or standalone); existing departmental registry | CM-11, SA-12 |
| AD-11 | Bare-metal provisioning method | Redfish virtual media, no provisioning network | Default | PXE with a dedicated provisioning network (documented as the alternative) | CM-2, SC-7 |
| AD-12 | GitOps source of truth | Existing departmental Git server on the high side; this repository is transferred with each content import | Decided | Git server on the registry host; in-cluster Git | CM-2, CM-3, CM-5 |
| AD-13 | Persistent storage | Existing enterprise storage through the vendor's CSI driver (NFS acceptable for general RWX only) | Decided | OpenShift Data Foundation; LVM Storage | CP-9, SC-28 |
| AD-14 | Object storage | Existing departmental S3-compatible endpoint for LokiStack and OADP | Department | No object storage: SIEM-only logging and backups to another target | AU-11, CP-9 |
| AD-15 | Content transfer method | Removable media or one-way transfer; SHA-256 manifest signed with a dedicated transfer GPG key whose public key reaches the high side out of band; chain-of-custody record | Department | Cross-domain solution (CDS) | MP-2, MP-5, SA-12, SI-7 |
| AD-16 | API and ingress load balancing | Platform-managed VIPs (keepalived / HAProxy) | Default | Departmental external load balancer (user-managed); check 4.22 support for your topology | SC-5, SC-7 |
| AD-17 | Platform services placement | Infra role on the first three workers | Default | Dedicated infra nodes | SC-2, SC-3 |
| AD-18 | Registry host and provisioner host | Two separate RHEL 9 FIPS hosts | Default | One combined host (lab only) | CM-7, SC-2 |
| AD-19 | Update path | OpenShift Update Service on the cluster, fed by mirrored graph data; EUS-to-EUS for y-stream upgrades | Default | Manual upgrades to an explicit release digest | SI-2, CM-3 |
| AD-20 | Application image source | Tenant images come from a departmental registry. The mirror registry holds Red Hat and approved third-party content only. | Department | A separate organization in the mirror registry | CM-11, SA-12, RA-5 |
| AD-21 | Mirror registry runtime and access | Rootless, under a dedicated service account; all content in one organization; push-only and pull-only robot accounts; one break-glass administrator | Default | Root (system) install; LDAP authentication for named registry users | AC-2, AC-6, IA-5 |

## Recording a decision

Copy this block into your SSP or an ADR file for each decision, and keep it under change control.

```markdown
### AD-nn <Title>

- **Status:** Proposed | Accepted | Superseded by AD-xx
- **Date / approver:** YYYY-MM-DD / <name, role>
- **Context:** What forces the decision (requirements, constraints, TRA findings).
- **Decision:** What was chosen.
- **Consequences:** Residual risks, follow-up work, and the controls affected.
```
