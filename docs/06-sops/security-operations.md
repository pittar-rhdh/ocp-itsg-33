# Security Operations

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Routine security monitoring and the platform side of incident response. The SIEM is authoritative
for alerts and logs (AD-07); these checks confirm its sources are healthy and fill rule gaps.

## Cadence

| Activity | Frequency | Role | SOP | Controls |
|---|---|---|---|---|
| RHACS vulnerability data import | Daily (Red Hat's minimum for offline mode) | Platform operator | [RHACS vulnerability data](#rhacs-vulnerability-data-import) | RA-5, SI-5 |
| RHACS violations and CVEs; log forwarding and SIEM receipt; ACM policy compliance | Daily | Security analyst, platform operator, SOC | [Daily security review](#daily-security-review) | RA-5, SI-4, AU-5, AU-6, CA-7, CM-6 |
| File integrity status | Daily, and on every `NodeHasIntegrityFailure` alert | Platform operator | [File integrity alerts](#file-integrity-alerts) | SI-7, IR-5 |
| Compliance Operator results and POA&M | Weekly (scans run daily) | Security officer | [Compliance scan review](#compliance-scan-review-and-poam-update) | CA-2, CA-5, CA-7 |
| Audit log review queries | Weekly, and during an incident | Security analyst | [Audit log review](#audit-log-review) | AU-6, AC-2(4), AC-6(9) |
| Incident support | On demand | Platform on-call | [Incident response](#incident-response-platform-actions) | IR-4, IR-5, IR-6 |

## RHACS vulnerability data import

The procedure is [Content import → Daily RHACS vulnerability data import](content-import.md#daily-rhacs-vulnerability-data-import);
commands and TLS handling are in [Platform configuration → RHACS](../04-itsg33-configuration/platform-configuration.md#rhacs).
If transfers can't run daily, record the data-age gap as a risk in the POA&M and SSP (RA-5).
Controls: RA-5, RA-5(2), SI-5, SA-12.

## Daily security review

| | |
|---|---|
| **Purpose** | One pass through the security signals that need a human every day |
| **When** | Daily |
| **Roles** | Security analyst and platform operator; escalate to the SOC (IR-6) |
| **Prerequisites** | `ocp-security-auditors` (read-only) access; RHACS Analyst role |
| **Controls** | SI-4, RA-5, AU-5, AU-6, CA-7, IR-5 |

### Procedure

1. **RHACS** portal: **Violations** (Critical/High, last 24 h): each is a known exception with
   expiry or gets a ticket; runtime violations in platform namespaces go to the SOC.
   **Vulnerability Management** (Critical, fixable): ticket the tenant image owner, or the next
   content import for platform images.
2. **Cluster checks:** log forwarder ready and all collectors running; every ACM policy `Compliant`
   ([ACM governance](../04-itsg33-configuration/acm-governance.md)); no `Failed`/`Errored` file
   integrity status (else [File integrity alerts](#file-integrity-alerts)):

   ```bash
   oc get clusterlogforwarder itsg33-siem -n openshift-logging \
     -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
   oc get daemonset -n openshift-logging            # DESIRED = READY = number of nodes
   oc get pods -n openshift-logging -o wide | grep -v -E 'Running|Completed'   # expect nothing
   oc get policies -n local-cluster \
     -o custom-columns=POLICY:.metadata.name,STATE:.status.compliant | grep -v -w Compliant
   oc get fileintegritynodestatuses -n openshift-file-integrity
   ```

3. **SIEM receipt:** the SOC confirms the newest audit event from each control plane node is under
   15 minutes old. A gap is an AU-5 event: open an incident.

### Verification

Every finding has a ticket or a recorded exception.

### Rollback

Not applicable (read-only).

### Records

Daily review log: date, reviewer, findings, tickets.

## Compliance scan review and POA&M update

| | |
|---|---|
| **Purpose** | Turn the daily Compliance Operator results (`itsg33-pbmm`) into tracked actions |
| **When** | Weekly |
| **Roles** | Platform operator collects; security officer decides; change board approves remediations |
| **Prerequisites** | Last scheduled scan `DONE` ([Check the scan ran](../05-compliance-evidence/scan-review-and-remediation.md#check-the-scan-ran)) |
| **Controls** | CA-2, CA-5, CA-7, CM-6, SI-6 |

### Procedure

1. Export the results and diff the failures against last week's:

   ```bash
   W=~/compliance/$(date -u +%Y%m%d); mkdir -p "${W}"; cd "${W}"
   oc get compliancecheckresults -n openshift-compliance -o json \
     | jq -r '.items[] | [.metadata.name, .status, .severity] | @csv' | sort > results.csv
   diff <(grep '"FAIL"' ../<last-week>/results.csv) <(grep '"FAIL"' results.csv) > new-failures.diff
   oc get complianceremediations -n openshift-compliance > remediations.txt; sha256sum * > SHA256SUMS
   ```

2. [Triage](../05-compliance-evidence/scan-review-and-remediation.md#triage) each new `FAIL` and
   `MANUAL`: fix through a Git pull request (never apply a `ComplianceRemediation` directly), accept
   the risk ([Exceptions](../05-compliance-evidence/scan-review-and-remediation.md#exceptions-in-the-tailoredprofile)),
   or add a POA&M item with owner and date (CA-5).

### Verification

Every `FAIL` and `MANUAL` maps to a fix, an accepted risk, or a POA&M item.

### Rollback

Not applicable.

### Records

The weekly directory, POA&M updates, and the fixing pull requests.

## File integrity alerts

| | |
|---|---|
| **Purpose** | Investigate a `Failed` `FileIntegrityNodeStatus`; re-initialize AIDE after an approved change outside the MCO (MachineConfig changes re-initialize automatically) |
| **When** | `NodeHasIntegrityFailure` alert or daily review finding |
| **Roles** | Platform operator with security analyst investigate; security officer approves re-initialization |
| **Prerequisites** | `cluster-admin` for re-initialization |
| **Controls** | SI-7, SI-7(1), AU-6, IR-5, CM-3 |

### Procedure

1. Find the failing node and its result config map (`resultConfigMapName`), and read the AIDE log
   (over 1 MB it is gzipped, annotation `file-integrity.openshift.io/compressed`: pipe through
   `base64 -d | gunzip`):

   ```bash
   oc get fileintegritynodestatuses -n openshift-file-integrity
   oc get fileintegritynodestatuses <name> -n openshift-file-integrity -o jsonpath='{.results}' | jq
   oc get events -n openshift-file-integrity --field-selector reason=NodeIntegrityStatus
   CM=aide-ds-worker-fileintegrity-<node>-failed
   oc get cm "${CM}" -n openshift-file-integrity -o jsonpath='{.data.integritylog}' > aide.log
   ```

2. Match each changed file to an approved change (ticket, MachineConfig, upgrade). **Unexplained
   change = security incident**: do not re-initialize; go to [Incident response](#incident-response-platform-actions).
3. Approved change only: re-initialize the affected `FileIntegrity` (`worker-fileintegrity` or
   `master-fileintegrity`; Argo CD does not own this annotation):

   ```bash
   oc annotate fileintegrities/worker-fileintegrity -n openshift-file-integrity file-integrity.openshift.io/re-init=
   ```

4. Keep `${CM}` as evidence (it is not owned by the `FileIntegrity`), then delete it when the record is complete.

### Verification

`oc get fileintegrities -n openshift-file-integrity` returns to `Active`; the node's next result is `Succeeded`.

### Rollback

Not applicable: AIDE keeps previous databases and logs on the node under `/etc/kubernetes` (`maxBackups`).

### Records

`aide.log`, the change ticket or incident number, the re-initialization approval.

## Audit log review

| | |
|---|---|
| **Purpose** | Targeted triage of API audit events, and a check that the SIEM ([AU-6](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-6-audit-review-analysis-and-reporting)) has them; on-cluster files hold only recent events |
| **When** | Weekly, and during an incident |
| **Roles** | Platform operator performs; security analyst reviews (node logs need node-admin rights, not `cluster-reader`; analysts without them use the SIEM) |
| **Prerequisites** | `cluster-admin`; the export is Protected B, keep it in the evidence area |
| **Controls** | AU-6, AU-6(1), AU-12, AC-2(4), AC-6(9) |

### Procedure

1. Export the API server audit logs from the control plane nodes and run the review queries
   (each prints time, user, verb, object):

   ```bash
   umask 077; A=~/audit/$(date -u +%Y%m%dT%H%M%SZ).jsonl
   for n in $(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[*].metadata.name}'); do
     oc adm node-logs "${n}" --path=kube-apiserver/audit.log
   done > "${A}"
   Q='[.requestReceivedTimestamp,.user.username,.verb,.objectRef.namespace,.objectRef.name] | @tsv'
   # exec, attach, port-forward
   jq -rR "fromjson? | select(.objectRef.subresource==\"exec\" or .objectRef.subresource==\"attach\" or .objectRef.subresource==\"portforward\") | select(.stage==\"ResponseComplete\") | ${Q}" "${A}"
   # Secret reads by people
   jq -rR "fromjson? | select(.objectRef.resource==\"secrets\" and (.verb==\"get\" or .verb==\"list\" or .verb==\"watch\")) | select(.user.username|startswith(\"system:\")|not) | ${Q}" "${A}"
   # RBAC changes
   jq -rR "fromjson? | select(.objectRef.apiGroup==\"rbac.authorization.k8s.io\" and (.verb|test(\"create|update|patch|delete\"))) | select(.stage==\"ResponseComplete\") | ${Q}" "${A}"
   ```

2. Match each event to a ticket or known automation account (e.g. Argo CD controller for RBAC).
   Unexplained events become incidents.

### Verification

Sample three events in the SIEM; missing events are an AU-5 finding.

### Rollback

Not applicable.

### Records

Query output, review notes, tickets. Delete the raw export when closed unless an incident needs it.

## Incident response: platform actions

| | |
|---|---|
| **Purpose** | Platform steps of the IR plan for a suspected workload or node compromise ([IR guidance](../04-itsg33-configuration/controls/ir-incident-response.md)): preserve evidence, then contain |
| **When** | On demand, led by the incident handler |
| **Roles** | Incident handler (SOC/CSIRT) leads; platform on-call performs; system owner approves service-affecting containment; security officer reports (GC CSEMP, IR-6) |
| **Prerequisites** | Incident ticket. Containment outside Git is an emergency change (CM-3): record it and reconcile Git afterwards |
| **Controls** | IR-4, IR-5, IR-6, AU-9, CM-3, SC-7 |

### Procedure

1. **Preserve** before changing anything; ask the SOC to preserve SIEM records and RHACS
   violations, and collect [must-gather with audit logs](troubleshooting.md#collect-must-gather-on-the-high-side):

   ```bash
   NS=<namespace>; E=~/ir/<ticket>; umask 077; mkdir -p "${E}"
   oc get all,networkpolicy,rolebinding,serviceaccount -n "${NS}" -o yaml > "${E}/objects.yaml"
   oc get secrets -n "${NS}" -o custom-columns=NAME:.metadata.name,TYPE:.type,CHANGED:.metadata.managedFields[-1].time > "${E}/secrets.txt"
   oc get events -n "${NS}" -o yaml > "${E}/events.yaml"
   for p in $(oc get pods -n "${NS}" -o name); do oc logs -n "${NS}" "${p}" --all-containers --timestamps > "${E}/$(basename ${p}).log"; done
   ```

2. **Isolate the namespace** with an `AdminNetworkPolicy` (a tenant deny-all `NetworkPolicy`
   would not cancel existing allow policies):

   ```bash
   oc apply -f - <<'EOF'
   apiVersion: policy.networking.k8s.io/v1alpha1
   kind: AdminNetworkPolicy
   metadata: {name: ir-quarantine}
   spec:
     priority: 1
     subject: {namespaces: {matchLabels: {itsg33/quarantine: "true"}}}
     ingress: [{name: deny-all-ingress, action: Deny, from: [{namespaces: {}}]}]
     egress: [{name: deny-all-egress, action: Deny, to: [{namespaces: {}}, {networks: ["0.0.0.0/0"]}]}]
   EOF
   oc label namespace "${NS}" itsg33/quarantine=true
   ```

   Test from a pod in another namespace. Host-network sources (e.g. routers) may not match; scale
   down the route's backends if needed.
3. **Contain a node:** `oc adm cordon <node>`. Don't drain or reboot until the handler decides on
   memory/disk evidence; then [Node maintenance](node-management.md#drain-and-cordon-for-maintenance).
4. **Stop a workload** only on the handler's decision: `oc scale deployment/<name> -n "${NS}" --replicas=0`.
5. **Report** through the SOC to GC CSEMP and the Cyber Centre ([IR-5 / IR-6](../04-itsg33-configuration/controls/ir-incident-response.md#ir-5-incident-monitoring-ir-6-incident-reporting)).
6. **Recover:** rotate exposed credentials, redeploy a rebuilt image through Git, and remove the
   label (`oc label namespace "${NS}" itsg33/quarantine-`) when the handler closes containment.

### Verification

Traffic to and from the namespace fails; the node shows `SchedulingDisabled`; evidence is
checksummed: `sha256sum "${E}"/* > "${E}/SHA256SUMS"`.

### Rollback

Remove the namespace label, `oc adm uncordon <node>`, scale workloads back.

### Records

Evidence directory with checksums (Protected B, chain of custody), incident ticket, emergency change record.
