# Control Family Guidance

[← Back to main](../index.md)

Each family document uses the same structure for every control. This keeps the guidance easy to
scan and makes it simple to copy into an SSP or SRTM.

## Control entry template

```markdown
### XX-n Control Name

| Attribute | Value |
|---|---|
| **Responsibility** | Platform / Tenant / Org / Infrastructure / Red Hat |
| **Inheritable by tenants** | Full / Partial / No |
| **OpenShift capabilities** | Features, operators, and APIs |
| **Automated check** | Compliance Operator / ACM policy / RHACS / Manual |

**Control intent (summary):** One or two sentences. See ITSG-33 Annex 3A for the authoritative text.

**Implementation guidance:** How the reference architecture meets the control.

**Configuration example:** YAML or commands.

**Evidence:** What to collect and how.
```

## Families

| Family | Document | Class |
|---|---|---|
| AC — Access Control | [ac-access-control.md](ac-access-control.md) | Technical |
| AU — Audit and Accountability | [au-audit-and-accountability.md](au-audit-and-accountability.md) | Technical |
| CA — Security Assessment and Authorization | [ca-security-assessment-and-authorization.md](ca-security-assessment-and-authorization.md) | Management |
| CM — Configuration Management | [cm-configuration-management.md](cm-configuration-management.md) | Operational |
| CP — Contingency Planning | [cp-contingency-planning.md](cp-contingency-planning.md) | Operational |
| IA — Identification and Authentication | [ia-identification-and-authentication.md](ia-identification-and-authentication.md) | Technical |
| IR — Incident Response | [ir-incident-response.md](ir-incident-response.md) | Operational |
| RA — Risk Assessment | [ra-risk-assessment.md](ra-risk-assessment.md) | Management |
| SA — System and Services Acquisition | [sa-system-and-services-acquisition.md](sa-system-and-services-acquisition.md) | Management |
| SC — System and Communications Protection | [sc-system-and-communications-protection.md](sc-system-and-communications-protection.md) | Technical |
| SI — System and Information Integrity | [si-system-and-information-integrity.md](si-system-and-information-integrity.md) | Operational |
| AT, MA, MP, PE, PL, PM, PS | [operational-and-management-families.md](operational-and-management-families.md) | Mixed |

## Notes on control selection

- The controls covered are the ones with a **meaningful OpenShift implementation** in the PBMM
  profile. Controls that are mostly organizational are covered briefly.
- Control and enhancement selection **must be checked against your departmental profile**.
- `(n)` after a control ID means a control enhancement, for example `AC-2(4)`.
