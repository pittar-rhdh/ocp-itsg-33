# Scan Review and Remediation

[← Phase 5 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

The Compliance Operator scans the cluster every day at 01:00 (`ScanSetting` `itsg33-pbmm`). This
page is the review loop: read the results, decide what each finding is, fix it **through Git**,
record exceptions in the `TailoredProfile`, put everything that stays open in the POA&M, and
rescan. Remediations are never applied by the operator (`autoApplyRemediations: false`,
`autoUpdateRemediations: false`): Git is the only writer (AD-22), and every fix is a reviewed
change (CM-3).

Reading results needs only read access (`ocp-security-auditors`). Rescans and raw result
retrieval change cluster objects and are done by `ocp-platform-admins`.

## Check the scan ran

```bash
# Suite phase and overall result (DONE / COMPLIANT, NON-COMPLIANT, INCONSISTENT, ERROR)
oc get compliancesuite itsg33-pbmm -n openshift-compliance \
  -o jsonpath='{.status.phase}{" "}{.status.result}{"\n"}'

# One scan per profile and node role
oc get compliancescans -n openshift-compliance
```

If a scan is not `DONE` the morning after, look at the scan pods and events in
`openshift-compliance` before reviewing results; an incomplete scan is itself a CA-7 finding.

## Read the results

Each rule produces one `ComplianceCheckResult`, named `<scan>-<rule>`, labelled with
`compliance.openshift.io/scan-name`, `compliance.openshift.io/check-status`, and
`compliance.openshift.io/check-severity`, and carrying the rule name in the
`compliance.openshift.io/rule` annotation.

| Status | Meaning | What to do |
|---|---|---|
| `PASS` | The check ran and passed | Nothing; it is evidence |
| `FAIL` | The check ran and failed | Triage (below): fix through Git, or exception, or POA&M |
| `MANUAL` | The check cannot be automated | Assess by hand; record the result and evidence; POA&M until assessed |
| `INCONSISTENT` | Nodes in one pool returned different results | Find the differing nodes, fix the drift, rescan |
| `ERROR` | The check could not complete | Investigate the scan; treat as not assessed |
| `INFO` | Information only | Review once; no action unless it reveals a problem |
| `NOT-APPLICABLE` | The rule does not apply, or is not selected | Nothing |

```bash
# Failing checks, high severity first
oc get compliancecheckresults -n openshift-compliance \
  -l 'compliance.openshift.io/check-status=FAIL,compliance.openshift.io/check-severity=high'
oc get compliancecheckresults -n openshift-compliance \
  -l 'compliance.openshift.io/check-status=FAIL,compliance.openshift.io/check-severity=medium'

# Failing checks that have a generated remediation, and those that must be fixed by hand
oc get compliancecheckresults -n openshift-compliance \
  -l 'compliance.openshift.io/check-status=FAIL,compliance.openshift.io/automated-remediation'
oc get compliancecheckresults -n openshift-compliance \
  -l 'compliance.openshift.io/check-status=FAIL,!compliance.openshift.io/automated-remediation'

# Checks that need a person
oc get compliancecheckresults -n openshift-compliance \
  -l compliance.openshift.io/check-status=MANUAL

# What one check verifies and how to fix it (description, rationale, instructions)
oc get compliancecheckresult <name> -n openshift-compliance -o yaml

# INCONSISTENT: the most common status and the nodes that differ
oc get compliancecheckresult <name> -n openshift-compliance -o json \
  | jq '.metadata.annotations | with_entries(select(.key | test("most-common-status|inconsistent-source")))'
```

To see which ITSG-33 controls a failing rule supports, look up its `Rule`
(`oc get rules.compliance <bundle>-<rule> -n openshift-compliance -o yaml`, where `<bundle>` is
`ocp4` or `rhcos4`) and read the `control.compliance.openshift.io/NIST-800-53` annotation.

## Triage

Record a decision for every `FAIL`, `MANUAL`, `INCONSISTENT`, and `ERROR` result in the review
log or ticket (the weekly review in [Reporting](reporting.md#reporting-cadence)).

| Decision | When | Result |
|---|---|---|
| **Fix** | The setting should be as the rule says | Change in Git; [remediation workflow](#remediate-through-git) |
| **Exception** | Your PBMM profile does not select the control, or a compensating control meets it | `disableRules` or `setValues` in the `TailoredProfile`, with rationale; [exceptions](#exceptions-in-the-tailoredprofile) |
| **Risk accepted / planned** | It cannot be fixed now | POA&M entry with owner, milestones, and a target date; [POA&M](#record-in-the-poam-ca-5) |
| **False positive** | The check is wrong for this platform | Evidence of why; exception with a rationale that names the evidence; report the content defect to Red Hat support |
| **Manual pass / fail** | `MANUAL` checks | Record the manual result and its evidence in the bundle (`01-compliance-operator/manual-assessments/`) |

Suggested response times, unless the departmental policy sets others: `high` in 30 days,
`medium` in 90 days, `low` at the next planned change. A high-severity failure also turns the ACM
policy `itsg33-ca-7-no-high-severity-failures` non-compliant.

## Remediate through Git

Never set `spec.apply: true` on a `ComplianceRemediation`, and never `oc apply` a remediation
directly: the change would bypass review, and Argo CD would not know the object.

1. **Read the remediation.** It has the same name as the check. Look for remediations that need
   a value or another remediation first.

   ```bash
   oc get complianceremediations -n openshift-compliance
   oc get complianceremediations -n openshift-compliance -l compliance.openshift.io/has-unset-variable
   oc get complianceremediations -n openshift-compliance -l compliance.openshift.io/has-unmet-dependencies
   oc get complianceremediation <name> -n openshift-compliance -o json | jq '.spec.current.object'
   ```

2. **Turn the payload into a Git-managed object.** The payload in `.spec.current.object` has no
   name and none of the repository's annotations. Add them, then render it as YAML (the role
   label applies to `MachineConfig` payloads only):

   ```bash
   oc get complianceremediation <name> -n openshift-compliance -o json \
     | jq '.spec.current.object
           | .metadata.name = "75-itsg33-<short-rule-name>-worker"
           | .metadata.labels["machineconfiguration.openshift.io/role"] = "worker"
           | .metadata.annotations["itsg33/controls"] = "<controls from the rule>"' \
     | oc create --dry-run=client -o yaml -f -
   ```

   File contents in a `MachineConfig` are URL-encoded; decode them to review what changes on
   the node.

3. **Put it in the right place in `04-gitops/`**; see [where remediations go](#where-remediations-go).
4. **Open a pull request** that names the rule, the check result, the controls, the change
   ticket, and the expected impact. Run the
   [validation](../04-itsg33-configuration/repository-layout.md#validation-and-ci) and get a
   review from someone other than the author (CM-3, CM-4, AC-5).
5. **Merge and sync.** `MachineConfig` and `KubeletConfig` changes drain and reboot every node in
   the pool, one at a time: merge them in a maintenance window, and batch several remediations
   into one change to avoid repeated reboots. Watch the rollout:

   ```bash
   oc get applications.argoproj.io -n openshift-gitops
   oc get machineconfigpools
   ```

6. **Rescan** ([below](#rescan)) and confirm the check is `PASS`. The Compliance Operator does
   not resolve dependencies between remediations, so a second rescan can be needed. Close the
   POA&M entry or ticket and reference the commit.

### Where remediations go

| Payload | Where in `04-gitops/` |
|---|---|
| `MachineConfig` (node scans) | A node hardening component, for example `components/node-hardening/`, with one object per role (`master` and `worker`). If the component is new, add it to `overlays/ocp1/config/kustomization.yaml`. |
| `KubeletConfig` (node scans) | Merge the settings into the existing objects in `components/kubelet-tls/kubeletconfig.yaml` rather than adding another `KubeletConfig` per pool. For `evictionHard`, set all five thresholds, not only the one the rule names. |
| Change to a cluster singleton (`APIServer`, `OAuth`, `Image`, `IngressController`, ...) | The component that already owns that object (for example `components/api-server/apiserver.yaml`), so that each object keeps one owner |
| New object (for example a `ConfigMap`, `PrometheusRule`, `NetworkPolicy`) | The component for that capability, with an `itsg33/controls` annotation |
| No remediation (manual fix) | Use the check's `instructions` and the rule's `warnings` to find the object, then change it in its component as above |

## Exceptions in the TailoredProfile

Exceptions live in `04-gitops/components/compliance-scans/compliance.yaml`, in the
`TailoredProfile` `ocp4-itsg33-pbmm`, so they are reviewed, versioned, and visible to the
assessor. Every entry needs a `rationale` that names the control, the reason, and the SSP
section or compensating control. Two kinds:

- `disableRules` — the rule is not assessed. Use it when the control is not selected in your
  PBMM profile, or a compensating control meets it.
- `setValues` — the rule is assessed against a GC or departmental value instead of the content
  default.

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

The `TailoredProfile` here extends the platform profile only. To make an exception for a node
rule (`ocp4-moderate-node` or `rhcos4-moderate`), add a second `TailoredProfile` that extends that
profile (its name ending in `-node`, or with the annotation
`compliance.openshift.io/product-type: Node`) and point the `ScanSettingBinding` at it instead of
the plain profile. After the change, check `oc get tailoredprofiles -n openshift-compliance`
shows `READY`.

Review the list of exceptions at least yearly and at every reauthorization. An exception
without a current rationale goes back to triage.

## Record in the POA&M (CA-5)

Open a POA&M entry for every finding that is not fixed within the response time, every `MANUAL`
check not yet assessed, and every exception that relies on a planned compensating control. Use
the columns in `05-evidence/poam-example.csv`: an ID, the control, the finding source (the
Compliance Operator rule name, ACM policy, RHACS CVE, or AIDE result), description, risk, owner,
planned remediation, milestone dates, status, and change ticket. Close the entry only when a
rescan or the policy status shows the fix, and keep the closing evidence in the next bundle.

## Rescan

Rescan after every remediation and after you change the `TailoredProfile`, rather than waiting
for 01:00.

```bash
# One scan
oc annotate compliancescans/rhcos4-moderate-worker -n openshift-compliance \
  compliance.openshift.io/rescan=

# Every scan of the binding, with the oc-compliance plugin (see Evidence collection)
oc compliance rerun-now scansettingbindings itsg33-pbmm -n openshift-compliance
```

## Handling content updates

Compliance Operator updates (installed through a manual install plan approval) can bring new
content: rules are added, renamed, or removed, and remediation payloads change. After each
update, before the next review:

1. Record the new operator and content versions in the bundle metadata:

   ```bash
   oc get csv -n openshift-compliance
   oc get profilebundles -n openshift-compliance \
     -o custom-columns=NAME:.metadata.name,IMAGE:.spec.contentImage,STATUS:.status.dataStreamStatus
   ```

2. Check that `ocp4-itsg33-pbmm` is still `READY` and that every rule in `disableRules` and every
   variable in `setValues` still exists (`oc get rules.compliance <name>`,
   `oc get variables.compliance <name>`).
3. Look for remediation payloads that changed. The operator marks only *applied* remediations
   as `Outdated`, and none are applied here, so compare the payloads with the previous bundle
   instead, and bring the matching objects in Git up to date through a pull request:

   ```bash
   oc get complianceremediations -n openshift-compliance -o json \
     | jq -S '[.items[] | {name: .metadata.name, object: .spec.current.object}]' \
     > remediations-current.json
   diff <previous-bundle>/01-compliance-operator/remediations-current.json remediations-current.json
   ```

4. Compare the result counts with the previous bundle. New `FAIL` results after an update are new
   findings, not regressions of the platform; triage them the same way and note the content
   change in the POA&M entry.

Do not use the `compliance.openshift.io/remove-outdated` annotation or `autoUpdateRemediations`:
both make the operator change the cluster outside Git.
