# Security Operations

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Routine security monitoring of the cluster, and the platform steps that support incident response.
The SIEM is the authoritative place for alerts and logs (AD-07); the cluster-side checks below
confirm that the sources feeding it are healthy and catch what the SIEM rules don't yet cover.

## Cadence

| Activity | Frequency | Role | SOP | Controls |
|---|---|---|---|---|
| RHACS vulnerability data import | Daily (Red Hat's minimum for offline mode) | Platform operator | [RHACS vulnerability data](#rhacs-vulnerability-data-import) | RA-5, SI-5 |
| RHACS violations and critical fixable CVEs | Daily | Security analyst | [Daily security review](#daily-security-review) | RA-5, SI-4, IR-5 |
| File integrity status | Daily, and on every `NodeHasIntegrityFailure` alert | Platform operator | [File integrity alerts](#file-integrity-alerts) | SI-7, IR-5 |
| Log forwarding health and SIEM receipt | Daily | Platform operator, SOC | [Daily security review](#daily-security-review) | AU-5, AU-6 |
| ACM policy non-compliance | Daily | Platform operator | [Daily security review](#daily-security-review) | CA-7, CM-6 |
| Compliance Operator results and POA&M | Weekly (scans run daily) | Security officer | [Compliance scan review](#compliance-scan-review-and-poam-update) | CA-2, CA-5, CA-7 |
| Audit log review queries | Weekly, and during an incident | Security analyst | [Audit log review](#audit-log-review) | AU-6, AC-2(4), AC-6(9) |
| Incident support | On demand | Platform on-call | [Incident response](#incident-response-platform-actions) | IR-4, IR-5, IR-6 |

## RHACS vulnerability data import

### Purpose and scope

Load the offline vulnerability definitions that arrive with each transfer, so image scans include
recent CVEs. Commands and TLS handling: [Platform configuration → RHACS](../04-itsg33-configuration/platform-configuration.md#rhacs).

### Roles

Performs: platform operator. Informed: security analyst.

### Prerequisites

An accepted transfer containing `scanner-vuln-updates-<version>-<date>.zip`, copied to
`/data/ocp/rhacs/` ([Accept a transfer](../02-high-side/accept-transfer.md)); the RHACS API token file.

### Procedure

1. Check that the file's SHA-256 matches the transfer's `SHA256SUMS`, and that its `<version>`
   matches the installed RHACS version (`oc get csv -n rhacs-operator`).
2. Upload it with `roxctl ... scanner upload-db --scanner-db-file=<file>` as shown on the RHACS page.
3. Add a row to the import log: `rhacs-uploaded`, file name, SHA-256.

### Verification

`roxctl` reports success. In the portal, the vulnerability definitions date (**Platform
Configuration → System Health**) is the date of the file.

### Rollback

Upload the previous file again if the new one is rejected or damaged.

### Records and evidence

Import log rows; the definitions age, sampled weekly. If transfers can't run daily, the gap
between data date and use is a risk: record it in the POA&M and the SSP (RA-5).

### Related controls

RA-5, RA-5(2), SI-5, SA-12.

## Daily security review

### Purpose and scope

One pass through the security signals that need a human every day.

### Roles

Performs: security analyst and platform operator together. Escalates: to the SOC (IR-6).

### Prerequisites

`ocp-security-auditors` access (read-only) and an RHACS account with the Analyst role.

### Procedure

1. **RHACS violations.** Portal → **Violations**, filter severity Critical and High, last 24 hours.
   For each: confirm it is known (exception with expiry) or open a ticket; runtime violations in
   platform namespaces go straight to the SOC.
2. **Critical fixable CVEs.** Portal → **Vulnerability Management**, filter Critical, fixable.
   Each finding becomes a ticket for the image owner (tenant) or for the next content import
   (platform images, see the import and upgrade SOPs).
3. **Log forwarding.** The forwarder must be ready and every collector pod running:

   ```bash
   oc get clusterlogforwarder itsg33-siem -n openshift-logging \
     -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
   oc get daemonset -n openshift-logging            # DESIRED = READY = number of nodes
   oc get pods -n openshift-logging -o wide | grep -v -E 'Running|Completed'   # expect nothing
   ```

   Then ask the SOC to confirm receipt in the SIEM: the newest audit event from each control plane
   node is less than 15 minutes old. A gap is an AU-5 event: open an incident.
4. **ACM governance.** Every policy must be `Compliant` ([ACM governance](../04-itsg33-configuration/acm-governance.md)):

   ```bash
   oc get policies -n local-cluster \
     -o custom-columns=POLICY:.metadata.name,STATE:.status.compliant | grep -v -w Compliant
   ```

5. **File integrity:** any `Failed` or `Errored` in `oc get fileintegritynodestatuses -n openshift-file-integrity`
   goes to [File integrity alerts](#file-integrity-alerts).

### Verification

Every finding has a ticket or a recorded exception.

### Rollback

Not applicable (read-only review).

### Records and evidence

Daily review log (date, reviewer, findings, tickets).

### Related controls

SI-4, RA-5, AU-5, AU-6, CA-7, IR-5.

## Compliance scan review and POA&M update

### Purpose and scope

Turn the daily Compliance Operator results (`ScanSettingBinding` `itsg33-pbmm`) into tracked
actions. Reporting, evidence bundles, and the SRTM are covered in [Phase 5](../05-compliance-evidence/index.md).

### Roles

Collects: platform operator. Decides: security officer. Approves remediations: change board.

### Prerequisites

The last scheduled scan finished: `oc get compliancesuites -n openshift-compliance` shows `DONE`.

### Procedure

1. Export the results and compare the failures with last week's export:

   ```bash
   W=~/compliance/$(date -u +%Y%m%d); mkdir -p "${W}"; cd "${W}"
   oc get compliancecheckresults -n openshift-compliance -o json \
     | jq -r '.items[] | [.metadata.name, .status, .severity] | @csv' | sort > results.csv
   diff <(grep '"FAIL"' ../<last-week>/results.csv) <(grep '"FAIL"' results.csv) > new-failures.diff
   oc get complianceremediations -n openshift-compliance > remediations.txt; sha256sum * > SHA256SUMS
   ```

2. For each new `FAIL`: fix it through Git (preferred), accept the risk, or record a POA&M item
   with owner and date (CA-5). Never apply a `ComplianceRemediation` directly: copy its object
   into the GitOps repository through a pull request.
3. For `MANUAL` checks, attach the evidence the rule asks for, or mark them for the next assessment.

### Verification

Every `FAIL` and `MANUAL` result maps to a fix, an accepted risk, or a POA&M item.

### Rollback

Not applicable.

### Records and evidence

The weekly directory, POA&M updates, and the pull requests that fixed findings.

### Related controls

CA-2, CA-5, CA-7, CM-6, SI-6.

## File integrity alerts

### Purpose and scope

Investigate a `Failed` `FileIntegrityNodeStatus` (AIDE found added, changed, or removed files),
and re-initialize the AIDE database after an **approved** change outside the Machine Config
Operator. Changes delivered through MachineConfigs pause the scans and re-initialize automatically.

### Roles

Investigates: platform operator with the security analyst. Approves re-initialization: security officer.

### Prerequisites

The alert or daily review finding; `cluster-admin` for re-initialization.

### Procedure

1. Find the failing node and its result config map:

   ```bash
   oc get fileintegritynodestatuses -n openshift-file-integrity
   oc get fileintegritynodestatuses <name> -n openshift-file-integrity -o jsonpath='{.results}' | jq
   oc get events -n openshift-file-integrity --field-selector reason=NodeIntegrityStatus
   ```

2. Read the AIDE log from the config map named in `resultConfigMapName`. Logs over 1 MB are
   gzip-compressed (annotation `file-integrity.openshift.io/compressed`): pipe through
   `base64 -d | gunzip`.

   ```bash
   CM=aide-ds-worker-fileintegrity-<node>-failed
   oc get cm "${CM}" -n openshift-file-integrity -o jsonpath='{.data.integritylog}' > aide.log
   ```

3. Match each changed file with an approved change (ticket, MachineConfig, upgrade). **Unexplained
   change = security incident**: do not re-initialize; go to [Incident response](#incident-response-platform-actions).
4. Explained and approved change only: re-initialize the database for the affected `FileIntegrity`
   (`worker-fileintegrity` or `master-fileintegrity`). The annotation is an operational action;
   Argo CD's server-side apply does not own it.

   ```bash
   oc annotate fileintegrities/worker-fileintegrity -n openshift-file-integrity file-integrity.openshift.io/re-init=
   ```

5. The failure config maps are not owned by the `FileIntegrity` (Red Hat): keep `${CM}` as
   evidence, then delete it when the record is complete.

### Verification

`oc get fileintegrities -n openshift-file-integrity` returns to `Active` and the node's next result
is `Succeeded`.

### Rollback

Not applicable: AIDE keeps the previous database and logs on the node under `/etc/kubernetes`
(`maxBackups`).

### Records and evidence

`aide.log`, the matching change ticket or incident number, the approval for re-initialization.

### Related controls

SI-7, SI-7(1), AU-6, IR-5, CM-3.

## Audit log review

### Purpose and scope

Targeted review of API audit events that the SIEM use cases in
[AU-6](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-6-audit-review-analysis-and-reporting)
also cover. The on-cluster files only hold recent events: use them for triage and to check the SIEM.

### Roles

Performs: platform operator, with the security analyst reviewing. Node logs are limited to node
administrators (`oc adm node-logs --help`), so `cluster-reader` (`ocp-security-auditors`) is not
enough; analysts without it use the same queries in the SIEM. Informed: system owner.

### Prerequisites

Cluster-admin. The export is Protected B: keep it in the evidence area.

### Procedure

1. Export the current Kubernetes API server audit logs from the control plane nodes (Red Hat:
   `oc adm node-logs --role=master --path=kube-apiserver/` lists the files):

   ```bash
   umask 077; A=~/audit/$(date -u +%Y%m%dT%H%M%SZ).jsonl
   for n in $(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[*].metadata.name}'); do
     oc adm node-logs "${n}" --path=kube-apiserver/audit.log
   done > "${A}"
   ```

2. Run the review queries. Each prints time, user, verb, and object:

   ```bash
   Q='[.requestReceivedTimestamp,.user.username,.verb,.objectRef.namespace,.objectRef.name] | @tsv'
   # Interactive access to workloads: exec, attach, port-forward
   jq -rR "fromjson? | select(.objectRef.subresource==\"exec\" or .objectRef.subresource==\"attach\" or .objectRef.subresource==\"portforward\") | select(.stage==\"ResponseComplete\") | ${Q}" "${A}"
   # Secret reads by people (not service accounts or system components)
   jq -rR "fromjson? | select(.objectRef.resource==\"secrets\" and (.verb==\"get\" or .verb==\"list\" or .verb==\"watch\")) | select(.user.username|startswith(\"system:\")|not) | ${Q}" "${A}"
   # RBAC changes
   jq -rR "fromjson? | select(.objectRef.apiGroup==\"rbac.authorization.k8s.io\" and (.verb|test(\"create|update|patch|delete\"))) | select(.stage==\"ResponseComplete\") | ${Q}" "${A}"
   ```

3. Check each event against a ticket or a known automation account (for example the Argo CD
   application controller for RBAC changes). Unexplained events become incidents.

### Verification

The same events appear in the SIEM (sample three). Missing events are an AU-5 finding.

### Rollback

Not applicable.

### Records and evidence

The query output, the review notes, and tickets raised. Delete the raw export when the review is
closed, unless an incident needs it.

### Related controls

AU-6, AU-6(1), AU-12, AC-2(4), AC-6(9).

## Incident response: platform actions

### Purpose and scope

The platform steps of the departmental IR plan for a suspected compromise of a workload or node
([IR guidance](../04-itsg33-configuration/controls/ir-incident-response.md)). The incident handler
leads; these steps preserve evidence first, then contain.

### Roles

Leads: incident handler (SOC/CSIRT). Performs: platform on-call. Approves containment that affects
service: system owner. Reports: security officer (GC CSEMP, IR-6).

### Prerequisites

An incident ticket. Containment actions outside Git are emergency changes (CM-3): record them in
the ticket and reconcile Git afterwards.

### Procedure

1. **Preserve** before changing anything:

   ```bash
   NS=<namespace>; E=~/ir/<ticket>; umask 077; mkdir -p "${E}"
   oc get all,networkpolicy,rolebinding,serviceaccount -n "${NS}" -o yaml > "${E}/objects.yaml"
   oc get secrets -n "${NS}" -o custom-columns=NAME:.metadata.name,TYPE:.type,CHANGED:.metadata.managedFields[-1].time > "${E}/secrets.txt"
   oc get events -n "${NS}" -o yaml > "${E}/events.yaml"
   for p in $(oc get pods -n "${NS}" -o name); do oc logs -n "${NS}" "${p}" --all-containers --timestamps > "${E}/$(basename ${p}).log"; done
   ```

   Ask the SOC to preserve the SIEM records and RHACS violations for the period. For the
   platform, collect `must-gather` with audit logs ([Collect must-gather](troubleshooting.md#collect-must-gather-on-the-high-side)).
2. **Isolate the namespace.** Kubernetes `NetworkPolicy` only allows traffic, so an added deny-all
   policy does **not** cancel the tenant's existing allow policies. Use an `AdminNetworkPolicy`,
   which tenants can't override, and label the namespace:

   ```bash
   oc apply -f - <<'EOF'
   apiVersion: policy.networking.k8s.io/v1alpha1
   kind: AdminNetworkPolicy
   metadata:
     name: ir-quarantine
   spec:
     priority: 1
     subject:
       namespaces:
         matchLabels:
           itsg33/quarantine: "true"
     ingress:
       - name: deny-all-ingress
         action: Deny
         from:
           - namespaces: {}
     egress:
       - name: deny-all-egress
         action: Deny
         to:
           - namespaces: {}
           - networks: ["0.0.0.0/0"]
   EOF
   oc label namespace "${NS}" itsg33/quarantine=true
   ```

   Test it from a pod in another namespace. Traffic from host-network sources (for example
   routers on host network) may not be matched by a namespace peer: also remove or scale the
   route's backends if needed.
3. **Contain a node** suspected of compromise: `oc adm cordon <node>` (no new pods). Don't drain
   or reboot until the handler has decided what memory or disk evidence to take; then follow
   [Node maintenance](node-management.md#drain-and-cordon-for-maintenance).
4. **Stop a workload** only when the handler decides: `oc scale deployment/<name> -n "${NS}" --replicas=0`
   (keeps the objects for analysis).
5. **Report** through the SOC to GC CSEMP and the Cyber Centre as the IR plan requires
   ([IR-5 / IR-6](../04-itsg33-configuration/controls/ir-incident-response.md#ir-5-incident-monitoring-ir-6-incident-reporting)).
6. **Recover:** rotate exposed credentials, redeploy from a rebuilt image through Git, remove the
   label (`oc label namespace "${NS}" itsg33/quarantine-`) when the handler closes containment.

### Verification

Connections to and from the namespace fail in the test; the cordoned node shows
`SchedulingDisabled`; evidence files have checksums: `sha256sum "${E}"/* > "${E}/SHA256SUMS"`.

### Rollback

Remove the namespace label, `oc adm uncordon <node>`, scale workloads back.

### Records and evidence

The evidence directory with checksums (Protected B, chain of custody), the incident ticket, and
the emergency change record.

### Related controls

IR-4, IR-5, IR-6, AU-9, CM-3, SC-7.
