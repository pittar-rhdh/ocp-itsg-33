# Compliance Automation and Evidence

[← Phase 5 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

ITSG-33 assessments need **evidence** that controls are implemented and working as intended.
OpenShift produces much of it automatically and continuously. This page describes the sources
and what each one proves. How to review results is in
[Scan review and remediation](scan-review-and-remediation.md), how to report them in
[Reporting](reporting.md), and how to package them in [Evidence collection](evidence-collection.md).

## Evidence strategy

| Evidence type | Source | Example controls |
|---|---|---|
| **Configuration state** | Exports of cluster configuration (`oc get ... -o yaml`), the Git repository | CM-2, CM-6, AC-3, SC-8 |
| **Automated compliance scans** | Compliance Operator (`ComplianceCheckResult`, raw ARF results) | CA-2, CA-7, CM-6, SI-6 |
| **Policy compliance status** | ACM governance policies (status and history) | CA-7, CM-6 |
| **Logs and audit records** | API audit logs, node audit logs, SIEM queries | AU-2, AU-3, AU-6, AU-12 |
| **Vulnerability reports** | RHACS (offline vulnerability data) | RA-5, SI-2 |
| **Integrity reports** | File Integrity Operator `FileIntegrityNodeStatus` and failure ConfigMaps | SI-7 |
| **Change records** | Git history and pull requests, Argo CD sync history, `ClusterVersion` history, change tickets | CM-3, CM-4, CM-5 |
| **Procedures and plans** | SSP, IR plan, CP plan, operations runbooks | IR-8, CP-2, PL-2 |
| **Test results** | DR test reports, restore test logs, penetration test reports | CP-4, CA-2, CA-8 |

## Compliance Operator

The Compliance Operator runs OpenSCAP scans against the cluster API (platform scans) and against
each node role (node scans), and reports each rule as a `ComplianceCheckResult`.

### Profiles relevant to ITSG-33

| Profile | Type | Notes |
|---|---|---|
| `ocp4-moderate` | Platform | NIST SP 800-53 Moderate. **Main baseline for PBMM**; extended here by the tailored profile `ocp4-itsg33-pbmm`. |
| `ocp4-moderate-node` | Node | Node-level OpenShift checks (kubelet and file permissions) for Moderate |
| `rhcos4-moderate` | Node | RHCOS operating system checks for Moderate |
| `ocp4-high`, `ocp4-high-node`, `rhcos4-high` | Platform / node | NIST SP 800-53 High. Useful where the departmental profile selects high-baseline enhancements. |
| `ocp4-cis`, `ocp4-cis-node` | Platform / node | CIS Benchmark. Good extra hardening evidence. |

> List the profiles available in your cluster with
> `oc get profiles.compliance -n openshift-compliance`. Profile content changes between Compliance
> Operator releases; see [Handling content updates](scan-review-and-remediation.md#handling-content-updates).

### Configuration in Git

All of it is in Git and applied by Argo CD; see
[Platform configuration](../04-itsg33-configuration/platform-configuration.md).

| What | File | Summary |
|---|---|---|
| Subscription | `04-gitops/components/operators/compliance-operator/operator.yaml` | Mirrored catalog, manual install plan approval ([Operators](../04-itsg33-configuration/operators.md)) |
| `ScanSetting` `itsg33-pbmm` | `04-gitops/components/compliance-scans/compliance.yaml` | Daily at 01:00, roles `master` and `worker`, 90 raw result sets kept, `autoApplyRemediations: false`, `autoUpdateRemediations: false` |
| `TailoredProfile` `ocp4-itsg33-pbmm` | same file | Extends `ocp4-moderate`; sets the session inactivity timeout to 15 minutes; holds every exception with its rationale |
| `ScanSettingBinding` `itsg33-pbmm` | same file | Binds `ocp4-itsg33-pbmm`, `ocp4-moderate-node`, and `rhcos4-moderate` to the `ScanSetting` |

The binding creates a `ComplianceSuite` named `itsg33-pbmm` with one `ComplianceScan` per
profile and node role: `ocp4-itsg33-pbmm`, `ocp4-moderate-node-master`,
`ocp4-moderate-node-worker`, `rhcos4-moderate-master`, and `rhcos4-moderate-worker`. If you add a
custom node pool (for example `infra`), add it to `roles`; node scans run once per role.

### Tailoring the profile to ITSG-33 PBMM

Use the `TailoredProfile` to:

- set variables to GC values (`setValues`, for example banner text and session timeouts),
- disable rules for controls your PBMM profile does not select, or that you meet another way
  (`disableRules`, with a rationale that points to the compensating control in the SSP), and
- give the profile a clear ITSG-33 name for reporting.

The procedure and the rules for exceptions are in
[Scan review and remediation](scan-review-and-remediation.md#exceptions-in-the-tailoredprofile).
Variable and rule names change between content releases; list them with
`oc get variables.compliance -n openshift-compliance` and
`oc get rules.compliance -n openshift-compliance`.

### Map rules to ITSG-33 controls

Each Compliance Operator `Rule` carries a `control.compliance.openshift.io/NIST-800-53`
annotation, a `;`-separated list such as `AU-2(d);AU-12(c);AC-6(9);CM-6(a)`. Because ITSG-33 uses
the same identifiers, you can build an ITSG-33 view straight from the cluster:

```bash
# Rules that support a control or one of its enhancements (example: AU-9)
oc get rules.compliance -n openshift-compliance -o json \
  | jq -r '.items[]
      | select((.metadata.annotations["control.compliance.openshift.io/NIST-800-53"] // "")
               | split(";") | any(. == "AU-9" or startswith("AU-9(")))
      | .metadata.name'

# Rule -> NIST SP 800-53 / ITSG-33 controls, for the whole content
oc get rules.compliance -n openshift-compliance -o json \
  | jq -r '.items[]
      | [.metadata.name,
         (.metadata.annotations["control.compliance.openshift.io/NIST-800-53"] // "")]
      | @csv' > rule-to-control-map.csv
```

The annotation reflects NIST SP 800-53 as used by the content, not your departmental profile:
check every mapping you rely on in the SRTM against the controls your profile selects. Each
`ComplianceCheckResult` carries the rule name in its `compliance.openshift.io/rule` annotation, so
results can be joined to this map (see [Evidence collection](evidence-collection.md#01-compliance-operator)).

## Red Hat Advanced Cluster Management — governance

ACM policies check configuration and report compliance status and history centrally. Each policy
carries `policy.open-cluster-management.io/standards`, `categories`, and `controls` annotations,
set here to ITSG-33 identifiers so that the Governance dashboard reports in ITSG-33 terms.

**Configuration — ITSG-33 policies:** in Git. Files: `04-gitops/acm-policies/`. Plain `Policy`,
`Placement`, and `PlacementBinding` resources, `inform` only, in namespace `itsg33-policies`,
placed on `local-cluster`. See [ACM governance](../04-itsg33-configuration/acm-governance.md).

One policy, `itsg33-ca-7-no-high-severity-failures`, looks at `ComplianceCheckResult` objects and
becomes non-compliant when a high-severity check fails, which puts scan results in the same
view as the configuration checks (CA-7).

> **Authoring policies (AD-23):** the policies are written as plain resources. Do not run the
> `PolicyGenerator` Kustomize plugin in the cluster: its documented OpenShift GitOps integration
> copies a plugin binary labelled not FIPS-compliant into the Argo CD repo server. If you want
> PolicyGenerator, run it in CI on the low side and commit its output to `04-gitops/acm-policies/`,
> so the cluster only sees plain resources.

## Red Hat Advanced Cluster Security

RHACS Central runs on the same cluster in offline mode (`stackrox`, AD-04), with vulnerability
data imported at least daily. It provides:

- **Vulnerability management and reports** for workload images, platform components, and nodes
  (RA-5, SI-2)
- **Compliance** views and reports built on Compliance Operator scans (CA-2, CA-7); see
  [Reporting](reporting.md#rhacs) for how they relate to the Git-managed scans
- **Policy enforcement** at build time (`roxctl` in CI), deploy time (admission controller), and
  runtime (SI-3, SI-4, CM-7)
- **Network graph** and generated `NetworkPolicy` suggestions (AC-4, SC-7)
- **Integration** with the SIEM and notification systems available on the high side (IR-5, IR-6)

## Evidence bundle structure (proposed)

The bundle layout, the collection commands, signing, and handling rules moved to
[Evidence collection](evidence-collection.md#bundle-layout).
