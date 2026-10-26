# CA — Security Assessment and Authorization

[← Back to control families](index.md) · [← Back to main](../index.md)

The CA family is mostly process-based. OpenShift helps by providing **continuous, automated
assessment data**, which makes SA&A and ongoing authorization much easier to sustain.

---

### CA-2 Security Assessments

| Attribute | Value |
|---|---|
| **Responsibility** | Org (assessor), Platform (evidence) |
| **OpenShift capabilities** | Compliance Operator, RHACS compliance, ACM governance, evidence bundle |
| **Automated check** | Yes — scheduled scans |

**Implementation guidance:**

- Build the assessment plan from the [traceability matrix](../05-control-traceability-matrix.md).
- Give assessors **read-only** access (`cluster-reader` through the `ocp-security-auditors` group)
  and the evidence bundle described in
  [04 — Compliance automation](../04-compliance-automation-and-evidence.md#evidence-bundle-structure-proposed).
- **CA-2(1) Independent assessors:** the assessor reviews results that are produced automatically
  and are hard to tamper with (ARF reports with checksums), in addition to doing their own manual
  testing.
- **CA-2(2) Specialized assessments:** include container-specific penetration testing (namespace
  escape, SCC bypass, network policy bypass) in the scope of CA-8 testing.

**Evidence:** assessment plan; Compliance Operator ARF results; RHACS compliance report; assessment
report.

---

### CA-3 Information System Connections

**Implementation guidance:** Record every external connection of the platform in the SSP:

- IdP
- SIEM
- Red Hat update and registry endpoints (or the mirror registry)
- Telemetry and Insights (if enabled)
- backup target
- the external services each tenant connects to

`EgressFirewall` and `AdminNetworkPolicy` resources, plus cluster-wide proxy settings, are the
technical evidence that only approved connections exist (see AC-4, SC-7).

```bash
oc get proxy cluster -o yaml
oc get egressfirewalls -A -o yaml
oc get adminnetworkpolicies -o yaml
```

---

### CA-5 Plan of Action and Milestones

**Implementation guidance:**

- Feed failed and manual-review Compliance Operator checks into the POA&M automatically.
- Feed fixable critical and high vulnerabilities from RHACS in the same way.
- Use ACM policy violations as tracking items.
- Record exceptions with a rationale and an expiry date. For Compliance Operator exceptions, also
  record them in the `TailoredProfile` (`disableRules` with a rationale).

```bash
oc get compliancecheckresults -n openshift-compliance \
  -l 'compliance.openshift.io/check-status in (FAIL,MANUAL)' \
  -o custom-columns=NAME:.metadata.name,STATUS:.status,SEVERITY:.severity
```

---

### CA-6 Security Authorization

**Implementation guidance:** This is an Org control. The authorizer signs off on the platform as a
common control provider. Re-authorize after significant changes, such as a major version upgrade,
a new connectivity model, or a new security domain. Minor z-stream updates within the authorized
minor version are handled through continuous monitoring (CA-7) and change control (CM-3).

---

### CA-7 Continuous Monitoring

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org |
| **OpenShift capabilities** | Scheduled Compliance Operator scans, ACM governance dashboard, RHACS, File Integrity Operator, cluster alerts |
| **Automated check** | Yes |

**Implementation guidance:**

| Activity | Tool | Frequency |
|---|---|---|
| Configuration compliance scan | Compliance Operator | Daily |
| Fleet policy compliance | ACM governance | Continuous (each policy evaluation interval) |
| Vulnerability scan of images and nodes | RHACS, Quay/Clair | Continuous / daily |
| File integrity check | File Integrity Operator | Every `gracePeriod` (for example, 15 minutes) |
| Platform health and security alerts | OpenShift Monitoring / Alertmanager | Continuous |
| Evidence bundle generation | Evidence script / pipeline | Monthly or quarterly |
| Compliance report to the authorizer | Report from ACM/RHACS/GRC tool | Quarterly |

**Configuration example — ACM policy that flags failing Compliance Operator checks:**

```yaml
apiVersion: policy.open-cluster-management.io/v1
kind: Policy
metadata:
  name: itsg33-ca-7-compliance-scan-results
  namespace: itsg33-policies
  annotations:
    policy.open-cluster-management.io/standards: ITSG-33
    policy.open-cluster-management.io/categories: CA Security Assessment and Authorization
    policy.open-cluster-management.io/controls: CA-7 Continuous Monitoring
spec:
  remediationAction: inform
  disabled: false
  policy-templates:
    - objectDefinition:
        apiVersion: policy.open-cluster-management.io/v1
        kind: ConfigurationPolicy
        metadata:
          name: itsg33-no-high-severity-failures
        spec:
          remediationAction: inform
          severity: high
          object-templates:
            - complianceType: mustnothave
              objectDefinition:
                apiVersion: compliance.openshift.io/v1alpha1
                kind: ComplianceCheckResult
                metadata:
                  namespace: openshift-compliance
                  labels:
                    compliance.openshift.io/check-status: FAIL
                    compliance.openshift.io/check-severity: high
```

**Evidence:** ACM governance dashboard export; a continuous monitoring strategy document.

---

### CA-8 Penetration Testing

**Implementation guidance:** If selected, scope the test to include:

- the API server and OAuth endpoints,
- ingress (PAZ) routes,
- tenant escape attempts (a privileged pod, host path mounts, kernel exploits under the SCC
  restrictions), and
- lateral movement between namespaces under the default-deny policies.

Coordinate with Red Hat support policies for testing a supported product.

---

### CA-9 Internal System Connections

**Implementation guidance:** Record internal connections between platform components, such as:

- spoke cluster to hub (ACM agent, RHACS Secured Cluster),
- collector to SIEM, and
- cluster to mirror registry.

These connections are authenticated with certificates and service accounts. Show them in the
architecture diagram and the network flow matrix.
