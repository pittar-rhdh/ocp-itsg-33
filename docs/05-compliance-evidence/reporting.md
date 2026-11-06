# Reporting

[← Phase 5 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

What each tool reports, how to get the report on an air-gapped cluster, and who receives it how
often. The commands work with the read-only `ocp-security-auditors` access unless noted.
Reports that are kept as evidence go into the bundle described in
[Evidence collection](evidence-collection.md).

## Compliance Operator

Reports the result of every rule of the PBMM profiles from the last scan (daily, 01:00).

```bash
# Suite status and result
oc get compliancesuite itsg33-pbmm -n openshift-compliance \
  -o jsonpath='{.status.phase}{" "}{.status.result}{"\n"}'

# Count of results per scan and status
oc get compliancecheckresults -n openshift-compliance -o json \
  | jq -r '[.items[] | {scan: .metadata.labels["compliance.openshift.io/scan-name"], status}]
      | group_by(.scan)[]
      | [.[0].scan, (group_by(.status) | map("\(.[0].status)=\(length)") | join(" "))] | @tsv'

# Failing checks by severity (feeds the weekly review and the POA&M)
oc get compliancecheckresults -n openshift-compliance \
  -l compliance.openshift.io/check-status=FAIL \
  -o custom-columns=NAME:.metadata.name,SEVERITY:.severity

# Exceptions in force (the tailored profile, with rationale)
oc get tailoredprofile ocp4-itsg33-pbmm -n openshift-compliance -o yaml
```

The full per-rule CSV with ITSG-33 controls and the raw ARF results are collected in the
bundle ([01-compliance-operator](evidence-collection.md#01-compliance-operator)). With `oscap`
on the admin host, the oc-compliance plugin can render the raw results as HTML
(`oc compliance fetch-raw ... --html`) for a human-readable report.

## ACM governance

Reports, for each ITSG-33 policy, whether `local-cluster` is compliant, and a short history of
compliance messages per policy template. The policies are inform only, so the report is an
independent check of what Argo CD applied.

**Console:** the ACM **Governance** dashboard and policy list group results by the policies'
standards, categories, and controls annotations (`ITSG-33`, family, control); open a policy to
see its status per cluster and its history. Use the console for the daily check and the
commands below for evidence.

```bash
# Root policies (itsg33-policies) and their aggregate status
oc get policies -n itsg33-policies

# Replicated policies with per-cluster status; their names are <namespace>.<policy>
oc get policies -n local-cluster

# Per policy: ITSG-33 control and status on each cluster
oc get policies -n itsg33-policies -o json \
  | jq -r '.items[] | .metadata as $m | .status.status[]?
      | [$m.name, $m.annotations["policy.open-cluster-management.io/controls"], .clustername, .compliant]
      | @csv'

# Compliance history of one policy (recent messages per template)
oc get policy itsg33-policies.itsg33-ca-7-no-high-severity-failures -n local-cluster -o json \
  | jq -r '.status.details[] | .templateMeta.name as $t | .history[]?
      | [$t, .lastTimestamp, .message] | @tsv'
```

The history in `.status.details[].history` keeps only recent messages. Export it on the reporting
cadence below so that the bundle holds the full period. Expected non-compliance before the
access lock-down and before operators are installed is described in
[ACM governance](../04-itsg33-configuration/acm-governance.md#policies).

## RHACS

RHACS Central runs offline in `stackrox`. All reports are produced in the RHACS portal on the
high side; nothing leaves the cluster unless you configure an email notifier to a high-side mail
server. Downloads are ZIP files containing CSV.

### Vulnerability reports (RA-5, SI-2)

- **On demand:** **Vulnerability Management → Results**, apply filters (for example the
  **Platform** view, or severity Critical and Important, fixable), then **Create report → Export
  report as CSV**, and download it from the reports table.
- **Saved and scheduled:** **Vulnerability Management → Reports → Report configurations →
  Create report**: scope (clusters, namespaces), CVE severity, fixable / unfixable, vulnerability
  state (observed, deferred, false positive), and optionally an email schedule. Use **Generate
  download** for the evidence copy.
- A user can only download reports they generated, and creating or downloading reports needs
  `WorkflowAdministration` write permission in RHACS. Give the evidence collector an RHACS role
  with `Image` read and `WorkflowAdministration` read and write, and nothing more.
- Reports are truncated at 1,000,000 rows by default; scope them (for example by severity) rather
  than raising the limit.

Vulnerability results are only as recent as the last import of vulnerability data
(`roxctl scanner upload-db`, at least daily, see
[Platform configuration](../04-itsg33-configuration/platform-configuration.md#rhacs)). Record the
date of the last import with every vulnerability report (RA-5(2)).

### Compliance reports (CA-2, CA-7)

RHACS **Compliance → OpenShift Coverage** shows Compliance Operator results by profile, check,
and cluster, with the controls of each check. Reports are tied to an RHACS scan schedule
(**Compliance → OpenShift Schedules**): **Generate download** produces a CSV and **Send report**
emails it.

An RHACS scan schedule creates its own `ScanSettingBinding` on the cluster, outside Git. This
repository schedules the scans in Git (`itsg33-pbmm`), so by default the Compliance Operator
exports are the authoritative compliance evidence and the RHACS compliance report is optional.
If the department wants RHACS compliance reports:

- record it as a decision, because a second binding outside Git scans the same profiles again;
- prefer the built-in profiles in the RHACS schedule: in RHACS CSV reports the
  **Control Reference** column shows `N/A` for tailored profiles such as `ocp4-itsg33-pbmm`.

### Policy violations (SI-4, CM-7)

**Violations** lists build, deploy, and runtime policy violations; review them for the period in
the weekly review. Runtime alerts also go to the SIEM through the configured integration, which
is the system of record for AU-6.

## File Integrity Operator

Reports, per node, the latest AIDE result: `Succeeded`, `Failed` (files added, changed, or removed
since the database was initialized), or `Errored`.

```bash
# Latest status per node
oc get fileintegritynodestatuses -n openshift-file-integrity

# Results with timestamps; a Failed result names a ConfigMap with the AIDE log
oc get fileintegritynodestatuses -n openshift-file-integrity -o json \
  | jq -r '.items[] | .nodeName as $n | .results[]
      | [$n, .condition, .lastProbeTime, (.filesChanged // ""), (.resultConfigMapName // "")] | @tsv'

# Failure logs (one ConfigMap per failed node)
oc get configmaps -n openshift-file-integrity -l file-integrity.openshift.io/result-log \
  -o custom-columns='NAME:.metadata.name,NODE:.metadata.labels.file-integrity\.openshift\.io/node'

# Status transitions and change counts as events
oc get events -n openshift-file-integrity --field-selector reason=NodeIntegrityStatus
```

Logs larger than 1 MB are stored gzip-compressed and base64-encoded (the ConfigMap then has the
`file-integrity.openshift.io/compressed` annotation):
`oc get cm <name> -n openshift-file-integrity -o json | jq -r '.data.integritylog' | base64 -d | gunzip`.

Every `Failed` result is investigated as a possible incident (SI-7, IR-4) until it is matched to an
approved change (for example a `MachineConfig` rollout). If an approved change keeps being
reported, re-initialize the AIDE database as described in the File Integrity Operator
documentation, under the change ticket, and keep the failure log in the bundle first.

## Reporting cadence

| Cadence | Report | Source | Owner | Audience |
|---|---|---|---|---|
| Daily | Scan completed; new high-severity `FAIL`; ACM non-compliant policies; AIDE `Failed` or `Errored`; RHACS data import done | Compliance Operator, ACM, File Integrity Operator, RHACS | Platform operations | Platform team |
| Weekly | Triage of all `FAIL`, `MANUAL`, `INCONSISTENT`, `ERROR`; new critical / important fixable CVEs; RHACS runtime violations | Compliance Operator, RHACS | Platform team with the ISSO | Platform team, ISSO |
| Monthly | Continuous monitoring report: result counts and trend, ACM status and history export, vulnerability report, AIDE summary, open POA&M items, changes merged | All tools, Git, POA&M | ISSO | System owner, departmental IT security |
| Quarterly | Signed evidence bundle; exception (tailored profile) review; SRTM evidence column updated | [Evidence collection](evidence-collection.md) | Evidence custodian, ISSO | Assessor, system owner |
| Before authorization or reauthorization | Full bundle for the period, raw ARF results, SRTM, POA&M, exceptions with rationale | All of the above | ISSO | Assessor, authorizing official |

Adjust the cadence to the departmental continuous monitoring strategy (CA-7). Each report names
its period, the cluster (`ocp1`), the repository commit, and the person who produced it.
