# 01 — ITSG-33 Overview

[← Back to main](index.md)

## What ITSG-33 is

**ITSG-33, *IT Security Risk Management: A Lifecycle Approach*** is CCCS guidance for managing IT
security risk in Government of Canada information systems. It defines two levels of activity:

| Annex | Content | Relevance to this guide |
|---|---|---|
| Annex 1 | Departmental IT security risk management activities | Organizational context; sets departmental security control profiles |
| Annex 2 | Information system security risk management activities (the system lifecycle, including SA&A) | Where the OpenShift platform's SA&A fits |
| Annex 3A | Security control catalogue | **The controls this guide maps to** |
| Annex 4A | Security control profiles (for example, Profile 1: PBMM) | Which controls are selected for Protected B / Medium / Medium |
| Annex 5 | Glossary | Terminology |

## Relationship to NIST SP 800-53

The ITSG-33 Annex 3A catalogue is **derived from NIST SP 800-53 Revision 3**. It uses the same
families, identifiers, and enhancement numbering, and adds GC-specific changes and guidance. This
has a practical benefit for OpenShift:

- The **Compliance Operator** ships NIST SP 800-53 Moderate and High profiles (`ocp4-moderate`,
  `ocp4-moderate-node`, `rhcos4-moderate`, and the `-high` equivalents). Each rule is annotated with
  the NIST controls it supports. These map directly to ITSG-33 identifiers.
- **Red Hat Advanced Cluster Security** and **Red Hat Advanced Cluster Management** both report
  against NIST SP 800-53, and both let you add custom standards labels.

Keep the differences in mind:

- ITSG-33 follows the Rev 3 control set. Controls introduced in Rev 4 or Rev 5 (for example, the
  `SR` supply chain family and `PT` privacy family) do not exist in ITSG-33. Supply chain
  protection is covered by **SA-12** in ITSG-33.
- Some controls have GC-specific parameters (for example, retention periods and session lock
  timeouts). Use the values set in your departmental profile, not the NIST defaults.
- Some control enhancements selected in the NIST Moderate baseline are not selected in the PBMM
  profile, and the reverse also happens. Treat the Compliance Operator profile as a **starting
  point** and tailor it (see [04 — Compliance automation](04-compliance-automation-and-evidence.md)).

## Security control profiles

| Profile | Use |
|---|---|
| **ITSG-33 Annex 4A Profile 1 — PBMM** | Protected B, medium integrity, medium availability. The most common profile for GC business systems. |
| **CCCS Medium Cloud Security Profile** (ITSP.50.103, Annex B) | Replaces the earlier "GC Security Control Profile for Cloud-based GC IT Services" (PBMM cloud). Used when the department consumes cloud services. |
| ITSG-33 Annex 4A Profile 3 — SBMM | Secret, medium integrity, medium availability. Not targeted by this guide, though much of the technical guidance still applies. |

Each department tailors its profile. Use this guide alongside your **departmental security control
profile**, and adjust control selections and parameter values to match.

## Control families

ITSG-33 groups controls into three classes.

| Class | Families | Where covered |
|---|---|---|
| **Technical** | AC, AU, IA, SC | Detailed family documents |
| **Operational** | AT, CM, CP, IR, MA, MP, PE, PS, SI | CM, CP, IR, SI in detail; others in [operational and management families](controls/operational-and-management-families.md) |
| **Management** | CA, PL, PM, RA, SA | CA, RA, SA in detail; PL and PM in [operational and management families](controls/operational-and-management-families.md) |

## Related CCCS and GC guidance

This architecture also draws on these publications (see [References](references.md)):

| Publication | Use in this architecture |
|---|---|
| **ITSP.80.022** — Baseline security requirements for network security zones | Zone design for ingress, egress, and management (PAZ, OZ, RZ, MRZ) |
| **ITSP.40.111** — Cryptographic algorithms for UNCLASSIFIED, PROTECTED A, and PROTECTED B information | Allowed algorithms; drives TLS profile and FIPS decisions |
| **ITSP.40.062** — Guidance on securely configuring network protocols | TLS versions and cipher suite selection |
| **ITSP.50.103** — Guidance on the security categorization of cloud-based services | Cloud profile selection |
| **ITSM.50.062** — Cloud security risk management | Cloud-hosted OpenShift deployments |
| **TBS Policy on Service and Digital / Directive on Security Management** | Mandatory procedures, including the Appendix B security control procedures |
| **GC Cloud Guardrails** | Minimum guardrails for cloud tenancy; several map to OpenShift configuration |
| **GC Cyber Security Event Management Plan (GC CSEMP)** | Incident reporting obligations (IR family) |

## Where OpenShift fits in the SA&A process

ITSG-33 Annex 2 describes how security is built into the system development lifecycle. A shared
OpenShift platform usually goes through SA&A as a **platform (common control provider)**.
Application systems that run on it **inherit** platform controls.

```text
+--------------------------------------------------------------+
| Application system SA&A                                      |
|   - Application-specific controls (Tenant)                   |
|   - Inherited controls  <-------------------------------+    |
+---------------------------------------------------------|----+
                                                          |
+---------------------------------------------------------|----+
| OpenShift platform SA&A (common control provider)       |    |
|   - Platform controls (Platform) ------------------------+    |
|   - Inherited controls <-------------------------------+     |
+--------------------------------------------------------|-----+
                                                         |
+--------------------------------------------------------|-----+
| Infrastructure (data centre, vSphere, or cloud region) |     |
|   - CCCS-assessed cloud services / departmental DC ----+     |
+--------------------------------------------------------------+
```

The **[control traceability matrix](05-control-traceability-matrix.md)** shows which controls the
platform can offer as inheritable (fully or partly) to application systems.
