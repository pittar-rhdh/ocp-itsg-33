# PROTECTED B — Evidence Bundle `<cluster>/<YYYY-MM-DD>`

> **Example — not validated.** Template for the `README.md` at the top of an evidence bundle.
> Adapt it to the departmental records format. Remove this note in the completed copy.

Read this file first. It says what the bundle covers, who produced it, and where the evidence
for each control is. Collection procedure: Phase 5, *Evidence collection*.

## 1. Metadata

| Field | Value |
|---|---|
| Cluster | `ocp1` (`oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}'`: `<infra-id>`) |
| Period covered | `<YYYY-MM-DD>` to `<YYYY-MM-DD>` |
| Collected (UTC) | `<YYYY-MM-DDThh:mm:ssZ>` |
| Collector (IdP user, group) | `<user>`, `ocp-security-auditors` |
| Raw ARF retrieved by | `<user>`, `ocp-platform-admins`, ticket `<ticket>` |
| Evidence custodian | `<name>` |
| Custodian key fingerprint | `<40-hex fingerprint>` (as recorded in the SSP) |
| OpenShift version | `<4.22.z>` (`00-metadata/clusterversion.yaml`) |
| Repository commit (this repository, departmental Git) | `<commit>` (`00-metadata/repo-commit.txt`), matches Argo CD revision: yes / no |
| Compliance Operator version | `<1.x.y>` (`00-metadata/operators.txt`) |
| Compliance content | `ocp4`, `rhcos4` content images `<digest>` (`00-metadata/compliance-content.txt`) |
| Profiles scanned | `ocp4-itsg33-pbmm` (extends `ocp4-moderate`), `ocp4-moderate-node`, `rhcos4-moderate` |
| RHACS version / last vulnerability data import | `<4.11.z>` / `<YYYY-MM-DD>`, ticket `<ticket>` |
| ACM version | `<2.16.z>` |
| Related documents | SSP `<version>`, SRTM `<version>`, POA&M `<version>`, previous bundle `<YYYY-MM-DD>` |
| Classification | PROTECTED B |

## 2. Summary

| Item | Value |
|---|---|
| Check results (all scans) | PASS `<n>`, FAIL `<n>` (high `<n>`, medium `<n>`, low `<n>`), MANUAL `<n>`, INCONSISTENT `<n>`, ERROR `<n>` |
| Exceptions in the tailored profile | `<n>` disabled rules, `<n>` set values (`01-compliance-operator/scan-configuration.yaml`) |
| ACM policies non-compliant at collection | `<list or none>` |
| AIDE failures in the period | `<n>`, all explained: yes / no |
| Open POA&M items | `<n>` (`11-poam/`) |
| Artifacts missing or partial, with reason | `<list or none>` |

## 3. Artifacts and controls

| Folder / file | Content | ITSG-33 controls |
|---|---|---|
| `00-metadata/` | Cluster version, operators, nodes, content versions, GitOps revisions, repository commit | CM-8, SA-22 |
| `01-compliance-operator/check-results.csv` | One row per check: scan, rule, status, severity, NIST SP 800-53 controls | CA-2, CA-7, CM-6, SI-6, and the controls listed per row |
| `01-compliance-operator/check-results.yaml` | Full results with descriptions and instructions | CA-2 |
| `01-compliance-operator/scan-configuration.yaml` | `ScanSetting`, `ScanSettingBinding`, `TailoredProfile` with every rationale | CM-6, CA-2 |
| `01-compliance-operator/remediations-current.json` | Remediation payloads offered by the content | CM-6 |
| `01-compliance-operator/manual-assessments/` | Results and evidence of `MANUAL` checks | Per check |
| `02-raw-arf/` | Raw ARF results per scan and node | CA-2, CA-2(1) |
| `03-acm-governance/` | Policies, status per cluster, history | CA-7, CM-6, and the control of each policy |
| `04-rhacs/` | Vulnerability report, data import record, RHACS configuration | RA-5, RA-5(2), SI-2, SI-4 |
| `05-configuration/` | Platform configuration exports, network isolation, machine configuration | CM-2, CM-6, AC-4, AC-8, AC-12, SC-7, SC-8, SC-13, SC-28 |
| `06-access/` | Role bindings, groups, SCC use, IdP export | AC-2, AC-3, AC-5, AC-6, AC-14, IA-2 |
| `07-logging/` | Log forwarding, LokiStack, audit profile, SIEM receipt record | AU-2, AU-4, AU-9, AU-12 |
| `08-integrity/` | AIDE status, failure logs, events, explaining tickets | SI-7, SI-7(1) |
| `09-backup/` | Backup schedules and results, restore test record | CP-9, CP-10, CP-4 |
| `10-change/` | Argo CD sync history, Git log, install plans, ClusterVersion history, pull requests, tickets | CM-3, CM-4, CM-5, SI-2 |
| `11-poam/` | POA&M extract for the period | CA-5 |

## 4. Integrity and signature

This file is complete before the manifest is written and is not changed afterwards; the
signature date, the archive hash, and the storage location go in the custodian register.

| Field | Value |
|---|---|
| Manifest | `SHA256SUMS` (SHA-256 of every file except `SHA256SUMS*`, including this file) |
| Signature | `SHA256SUMS.asc`, detached, ASCII-armoured, by the evidence custodian (key above) |
| Archive | `evidence-ocp1-<YYYY-MM-DD>.tar`; hash and location in the custodian register |

To verify (custodian public key imported, fingerprint checked against the SSP):

```bash
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum --check --strict --quiet SHA256SUMS
find . -type f ! -name 'SHA256SUMS*' | sort | diff <(awk '{print $2}' SHA256SUMS | sort) -
```

## 5. Sign-off

Sign-off is recorded in the ticket `<ticket>` (collector, custodian, ISSO review), so that this
file does not change after the manifest is written.
