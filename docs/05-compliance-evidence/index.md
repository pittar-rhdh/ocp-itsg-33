# Phase 5 — Compliance Reporting and Evidence

[← Back to main](../index.md)

> **Examples only — not validated.** The configuration and commands in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

Show, continuously and on demand, that the controls configured in Phase 4 are in place and
working, and package that proof for the SA&A process. The Compliance Operator, ACM governance,
RHACS, and the File Integrity Operator produce the results; people review them, fix findings
through Git, record what cannot be fixed in the POA&M, and collect signed evidence bundles that
the SRTM points to.

| | |
|---|---|
| **Where** | High side: admin host with cluster access (read-only account for collection); departmental Git; Protected B evidence store |
| **Inputs** | Cluster converged by [Phase 4](../04-itsg33-configuration/index.md); Compliance Operator scans (`itsg33-pbmm`), ACM policies (`itsg33-policies`), RHACS Central (offline), and File Integrity Operator running; evidence custodian GPG key; departmental SRTM and POA&M templates |
| **Outputs** | Reviewed scan results; remediations merged through Git; exceptions in the `TailoredProfile` with rationale; POA&M entries; periodic reports; signed evidence bundles; SRTM rows with evidence locations |
| **Hands off to** | [Phase 6 — SOPs](../06-sops/index.md) (recurring review, reporting, and evidence collection) |
| **Decisions** | AD-04, AD-07, AD-15, AD-22, AD-23 ([Architecture decisions](../00-architecture/architecture-decisions.md)); departmental choices listed in [Evidence collection](evidence-collection.md#departmental-decisions) |
| **Key controls** | CA-2, CA-5, CA-7, CM-3, CM-6, SI-6, SI-7, RA-5, AU-6, AU-9 |

## Workflow

```text
 continuous   Compliance Operator  daily 01:00, ScanSettingBinding itsg33-pbmm
              ACM policies         inform only, itsg33-policies -> local-cluster
              RHACS (offline)      vulnerabilities, runtime policy, compliance
              File Integrity       AIDE on every node
        │
 review       FAIL / MANUAL / INCONSISTENT / ERROR, by severity        -> Scan review and remediation
        ├──> fix:        ComplianceRemediation object -> 04-gitops component -> PR -> sync -> rescan
        ├──> exception:  TailoredProfile disableRules / setValues with rationale -> PR
        └──> not fixed:  POA&M entry (CA-5) with owner and milestones
        │
 report       daily / weekly / monthly / quarterly / before authorization   -> Reporting
        │
 collect      read-only account (ocp-security-auditors) -> evidence bundle  -> Evidence collection
        │     SHA256SUMS + detached GPG signature by the evidence custodian
        │
 store        Protected B evidence store -> SRTM evidence column -> assessor (CA-2)
        │
 Phase 6      the same steps as recurring SOPs
```

## Pages

| Page | Content |
|---|---|
| [Compliance automation and evidence](compliance-automation-and-evidence.md) | The evidence sources: what each tool proves, Compliance Operator profiles and tailoring, mapping rules to ITSG-33 controls, ACM governance, RHACS |
| [Scan review and remediation](scan-review-and-remediation.md) | Reading results, triage, fixing findings through Git (never auto-apply), exceptions with rationale, the POA&M, rescans, content updates |
| [Reporting](reporting.md) | What each tool reports and how to get it in an air-gapped cluster; reporting cadence, owners, and audiences |
| [Evidence collection](evidence-collection.md) | Bundle layout mapped to controls, collection commands, raw ARF results, signing and verification, Protected B handling, retention, moving evidence off the high side |
| [Control traceability matrix](control-traceability-matrix.md) | Control-by-control summary; evidence locations and frequency; building the departmental SRTM |

## Repository files

Examples only; the collection commands stay in the documentation.

| File | Purpose |
|---|---|
| `05-evidence/README.md` | What the example files are and how they are used |
| `05-evidence/evidence-bundle-index.md` | Template for the `README.md` at the top of every evidence bundle: metadata, artifact-to-control table, integrity |
| `05-evidence/srtm-example.csv` | Example SRTM rows with configuration, automated check, evidence location, frequency, and owner |
| `05-evidence/poam-example.csv` | Example POA&M rows for findings from the Compliance Operator, ACM, RHACS, and the File Integrity Operator |

## How this phase supports ITSG-33

| Control | How |
|---|---|
| CA-2 Security assessments | Assessors get read-only cluster access, signed evidence bundles, raw ARF results, and an SRTM that names the evidence for each control |
| CA-5 Plan of action and milestones | Every FAIL that is not fixed, every MANUAL check not yet assessed, and every exception goes into the POA&M with an owner and dates |
| CA-7 Continuous monitoring | Daily scans, ACM policy status and history, RHACS vulnerability data, and AIDE results, reviewed on a fixed cadence |
| CM-3, CM-6 Change control and settings | Remediations are reviewed and merged through Git like any other change; exceptions are versioned in the `TailoredProfile` |
| SI-6 Security function verification | The daily scan verifies the security settings; rescans confirm each fix |
| SI-7 Integrity | File Integrity Operator results in every bundle; bundles themselves are hashed and signed |
| RA-5 Vulnerability scanning | RHACS vulnerability reports from offline vulnerability data, with the data import date recorded |
| AU-6, AU-9 Audit review and protection | Reports go to named audiences on a schedule; evidence is protected by checksums, signatures, and access control |
