# Phase 5 — Compliance Reporting and Evidence

[← Back to main](../index.md)

> **Examples only — not validated.** The configuration and commands in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

> **Status:** The compliance automation guide and traceability matrix are available now. The
> tailored profile, collection commands, and SRTM evidence columns are added in the Phase 5 work.

Show, continuously and on demand, that the controls configured in Phase 4 are in place and
working, and package that proof for the SA&A process.

| | |
|---|---|
| **Where** | High side |
| **Inputs** | Cluster converged by Phase 4; Compliance Operator, File Integrity Operator, ACM, and RHACS running |
| **Outputs** | Scheduled scan results; ACM and RHACS reports; versioned evidence bundles; SRTM with evidence locations |
| **Hands off to** | [Phase 6 — SOPs](../06-sops/index.md) (recurring evidence collection and review) |
| **Key controls** | CA-2, CA-5, CA-7, CM-6, SI-6, AU-6 |

## Available now

| Page | Content |
|---|---|
| [Compliance automation and evidence](compliance-automation-and-evidence.md) | Compliance Operator profiles and scans, ACM governance, RHACS, evidence bundle structure, starter collection commands |
| [Control traceability matrix](control-traceability-matrix.md) | Control-by-control summary with responsibility, inheritance, and links to the guidance |

## Planned content

| Page | Content |
|---|---|
| PBMM tailored profile | `TailoredProfile` for platform and node scans, with the rationale for every disabled rule and variable |
| Remediation workflow | Reviewing `ComplianceRemediation` objects through change control, rather than auto-applying |
| Reporting | ACM governance and RHACS compliance reports for the cluster |
| Evidence collection | Collection commands, bundle layout, integrity (SHA-256), and handling bundles as Protected B |
| SRTM | The traceability matrix extended with evidence location and collection frequency |
| Moving evidence off the high side | Only where policy allows; review and sanitization steps |

## Planned repository files

Templates only; the collection commands stay in the documentation:

```text
05-evidence/
  templates/                    # evidence bundle README and report templates
```
