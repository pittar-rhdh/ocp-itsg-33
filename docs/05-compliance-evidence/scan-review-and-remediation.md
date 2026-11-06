# Scan Review and Remediation

[← Phase 5 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

The Compliance Operator scans daily at 01:00 (`ScanSetting` `itsg33-pbmm`; setup in
[Compliance automation and evidence](compliance-automation-and-evidence.md)). This page is the
review loop: read results, triage, fix **through Git**, record exceptions in the
`TailoredProfile`, put what stays open in the POA&M, and rescan. The operator never applies
remediations (`autoApplyRemediations: false`, `autoUpdateRemediations: false`): Git is the only
writer (AD-22) and every fix is a reviewed change (CM-3). Reading needs `ocp-security-auditors`;
rescans and raw result retrieval are done by `ocp-platform-admins`.

## Check the scan ran

```bash
oc get compliancesuite itsg33-pbmm -n openshift-compliance -o jsonpath='{.status.phase} {.status.result}{"\n"}'
oc get compliancescans -n openshift-compliance     # one per profile and node role
```

Expect `DONE` with `COMPLIANT` or `NON-COMPLIANT`; investigate `INCONSISTENT` or `ERROR`. A scan
not `DONE` the morning after is itself a CA-7 finding: check scan pods and events first.

## Read the results

Each rule produces one `ComplianceCheckResult` named `<scan>-<rule>`, labelled
`compliance.openshift.io/scan-name`, `/check-status`, and `/check-severity`, with the rule name in
the `compliance.openshift.io/rule` annotation.

| Status | Meaning | Action |
|---|---|---|
| `PASS` | Ran and passed | None; it is evidence |
| `FAIL` | Ran and failed | [Triage](#triage) |
| `MANUAL` | Cannot be automated | Assess by hand and record evidence; POA&M until assessed |
| `INCONSISTENT` | Nodes in one pool differ | Find the differing nodes, fix the drift, rescan |
| `ERROR` | Could not complete | Investigate; treat as not assessed |
| `INFO` | Information only | Review once |
| `NOT-APPLICABLE` | Does not apply or not selected | None |

```bash
NS='-n openshift-compliance'; S=compliance.openshift.io/check-status
oc get compliancecheckresults $NS -l "$S=FAIL,compliance.openshift.io/check-severity=high"  # then medium, low
oc get compliancecheckresults $NS -l "$S=FAIL,compliance.openshift.io/automated-remediation"  # has a remediation
oc get compliancecheckresults $NS -l "$S=FAIL"',!compliance.openshift.io/automated-remediation'  # fix by hand
oc get compliancecheckresults $NS -l "$S=MANUAL"
oc get compliancecheckresult <name> $NS -o yaml          # description, rationale, instructions
# INCONSISTENT: most common status and the differing nodes
oc get compliancecheckresult <name> $NS -o json \
  | jq '.metadata.annotations | with_entries(select(.key | test("most-common-status|inconsistent-source")))'
# Controls a rule supports (<bundle> is ocp4 or rhcos4)
oc get rules.compliance <bundle>-<rule> $NS -o jsonpath='{.metadata.annotations.control\.compliance\.openshift\.io/NIST-800-53}{"\n"}'
```

## Triage

Record a decision for every `FAIL`, `MANUAL`, `INCONSISTENT`, and `ERROR` result in the review
log or ticket (weekly review, [Reporting](reporting.md#reporting-cadence)).

| Decision | When | Result |
|---|---|---|
| **Fix** | The setting should be as the rule says | [Remediate through Git](#remediate-through-git) |
| **Exception** | Control not selected in your PBMM profile, or met by a compensating control | `disableRules` / `setValues` with rationale ([exceptions](#exceptions-in-the-tailoredprofile)) |
| **Risk accepted / planned** | Cannot be fixed now | [POA&M](#record-in-the-poam-ca-5) entry with owner, milestones, target date |
| **False positive** | Check is wrong for this platform | Exception whose rationale names the evidence; report the content defect to Red Hat support |
| **Manual pass / fail** | `MANUAL` checks | Result and evidence in `01-compliance-operator/manual-assessments/` ([Evidence collection](evidence-collection.md#bundle-layout)) |

Suggested response times unless departmental policy differs: `high` 30 days, `medium` 90 days,
`low` next planned change. A high-severity failure also makes ACM policy
`itsg33-ca-7-no-high-severity-failures` non-compliant.

## Remediate through Git

Never set `spec.apply: true` on a `ComplianceRemediation` or `oc apply` its payload: that bypasses
review and Argo CD would not know the object. The settings already managed in Git are described
in [Platform configuration](../04-itsg33-configuration/platform-configuration.md).

1. **Read the remediation** (same name as the check). List those needing a value or another
   remediation first with `oc get complianceremediations -n openshift-compliance -l
   compliance.openshift.io/has-unset-variable` (or `has-unmet-dependencies`).

2. **Turn the payload into a Git-managed object** — it has no name or repository annotations
   (the role label is for `MachineConfig` only). Decode URL-encoded `MachineConfig` file contents
   to review what changes on the node.

   ```bash
   oc get complianceremediation <name> -n openshift-compliance -o json \
     | jq '.spec.current.object
           | .metadata.name = "75-itsg33-<short-rule-name>-worker"
           | .metadata.labels["machineconfiguration.openshift.io/role"] = "worker"
           | .metadata.annotations["itsg33/controls"] = "<controls from the rule>"' \
     | oc create --dry-run=client -o yaml -f -
   ```

3. **Place it in `04-gitops/`** ([where remediations go](#where-remediations-go)).
4. **Open a pull request** naming the rule, check result, controls, change ticket, and expected
   impact; run the [validation](../04-itsg33-configuration/repository-layout.md#validation-and-ci)
   and get review from someone other than the author (CM-3, CM-4, AC-5).
5. **Merge and sync.** `MachineConfig` and `KubeletConfig` changes drain and reboot each node in
   the pool: merge in a maintenance window and batch remediations to avoid repeated reboots.
   Watch `oc get applications.argoproj.io -n openshift-gitops` and `oc get machineconfigpools`.
6. **[Rescan](#rescan)** and confirm `PASS`. The operator does not resolve dependencies between
   remediations, so a second rescan may be needed. Close the POA&M entry or ticket, citing the commit.

### Where remediations go

| Payload | Where in `04-gitops/` |
|---|---|
| `MachineConfig` | A node hardening component (for example `components/node-hardening/`), one object per role (`master`, `worker`); add a new component to `overlays/ocp1/config/kustomization.yaml` |
| `KubeletConfig` | Merge into `components/kubelet-tls/kubeletconfig.yaml`, not a new object per pool; for `evictionHard` set all five thresholds |
| Cluster singleton (`APIServer`, `OAuth`, `Image`, `IngressController`, ...) | The component that already owns it (for example `components/api-server/apiserver.yaml`), so each object has one owner |
| New object (`ConfigMap`, `PrometheusRule`, `NetworkPolicy`, ...) | The component for that capability, with an `itsg33/controls` annotation |
| None (manual fix) | Use the check's `instructions` and the rule's `warnings` to find the object; change it in its component |

## Exceptions in the TailoredProfile

Exceptions live in the `TailoredProfile` `ocp4-itsg33-pbmm` in
`04-gitops/components/compliance-scans/compliance.yaml`, so they are reviewed, versioned, and
visible to the assessor. Every entry needs a `rationale` naming the control, the reason, and the
SSP section or compensating control. `disableRules` stops assessing a rule (control not selected,
or compensating control); `setValues` assesses against a GC or departmental value.

```yaml
spec:
  extends: ocp4-moderate
  disableRules:
    - name: <ocp4-rule-name>
      rationale: "<control>: <why>. Compensating control: <SSP section / control>. Approved: <ticket>"
  setValues:
    - name: ocp4-var-oauth-inactivity-timeout
      rationale: "AC-11 / AC-12: departmental session inactivity limit of 15 minutes"
      value: "15m0s"
```

This profile extends the platform profile only. For node rules (`ocp4-moderate-node`,
`rhcos4-moderate`), add a second `TailoredProfile` extending that profile (name ending in `-node`,
or annotation `compliance.openshift.io/product-type: Node`) and point the `ScanSettingBinding` at
it. Check `oc get tailoredprofiles -n openshift-compliance` shows `READY`. Review exceptions at
least yearly and at every reauthorization; one without a current rationale goes back to triage.

## Record in the POA&M (CA-5)

Open an entry for every finding not fixed within the response time, every unassessed `MANUAL`
check, and every exception relying on a planned compensating control. Use the columns in
`05-evidence/poam-example.csv` (ID, control, source — rule, ACM policy, RHACS CVE, or AIDE result —
description, risk, owner, planned remediation, milestones, status, ticket). Close it only when a
rescan or policy status shows the fix, and keep the closing evidence in the next bundle.

## Rescan

After every remediation or `TailoredProfile` change, rather than waiting for 01:00:

```bash
oc annotate compliancescans/rhcos4-moderate-worker -n openshift-compliance compliance.openshift.io/rescan=
oc compliance rerun-now scansettingbindings itsg33-pbmm -n openshift-compliance   # all scans; plugin per Evidence collection
```

## Handling content updates

Compliance Operator updates (manual install plan approval) can add, rename, or remove rules and
change remediation payloads. After each update, before the next review:

1. Record operator and content versions (`oc get csv,profilebundles -n openshift-compliance`) in
   the bundle `00-metadata/`.
2. Check `ocp4-itsg33-pbmm` is still `READY` and every `disableRules` rule and `setValues`
   variable still exists (`oc get rules.compliance <name>`, `oc get variables.compliance <name>`).
3. Find changed payloads. The operator marks only *applied* remediations `Outdated`, and none are
   applied here, so diff against the previous bundle and update the Git objects by pull request:

   ```bash
   oc get complianceremediations -n openshift-compliance -o json \
     | jq -S '[.items[] | {name: .metadata.name, object: .spec.current.object}]' > remediations-current.json
   diff <previous-bundle>/01-compliance-operator/remediations-current.json remediations-current.json
   ```

4. Compare result counts with the previous bundle. New `FAIL` results after an update are new
   findings, not platform regressions; triage them and note the content change in the POA&M.

Do not use the `compliance.openshift.io/remove-outdated` annotation or `autoUpdateRemediations`:
both change the cluster outside Git.
