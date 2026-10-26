# 04 — Compliance Automation and Evidence

[← Back to main](index.md)

ITSG-33 assessments need **evidence** that controls are implemented and working as intended.
OpenShift can produce much of this evidence automatically and continuously. This section
describes the tools, how they map to ITSG-33, and how to package evidence.

## Evidence strategy

| Evidence type | Source | Example controls |
|---|---|---|
| **Configuration state** | Exports of cluster configuration (`oc get ... -o yaml`), Git repositories | CM-2, CM-6, AC-3, SC-8 |
| **Automated compliance scans** | Compliance Operator (`ComplianceCheckResult`, ARF/XCCDF reports) | CA-2, CA-7, CM-6, SI-6 |
| **Policy compliance status** | ACM governance policies, RHACS compliance | CA-7, CM-3, CM-6 |
| **Logs and audit records** | API audit logs, node audit logs, SIEM queries | AU-2, AU-3, AU-6, AU-12 |
| **Vulnerability reports** | RHACS, Quay/Clair, Insights Advisor | RA-5, SI-2 |
| **Integrity reports** | File Integrity Operator `FileIntegrityNodeStatus` | SI-7 |
| **Change records** | Git pull requests, Argo CD sync history, `ClusterVersion` history | CM-3, CM-4, CM-5 |
| **Procedures and plans** | SSP, IR plan, CP plan, operations runbooks | IR-8, CP-2, PL-2 |
| **Test results** | DR test reports, restore test logs, penetration test reports | CP-4, CA-2, CA-8 |

## Compliance Operator

The Compliance Operator runs OpenSCAP scans against the cluster API (platform scans) and against
each node (node scans). It reports results as Kubernetes resources.

### Profiles relevant to ITSG-33

| Profile | Type | Notes |
|---|---|---|
| `ocp4-moderate` | Platform | NIST SP 800-53 Moderate. **Main baseline for PBMM.** |
| `ocp4-moderate-node` | Node | Node-level OpenShift checks (kubelet and file permissions) for Moderate |
| `rhcos4-moderate` | Node | RHCOS operating system checks for Moderate |
| `ocp4-high`, `ocp4-high-node`, `rhcos4-high` | Platform / node | NIST SP 800-53 High. Useful where the departmental profile selects high-baseline enhancements. |
| `ocp4-cis`, `ocp4-cis-node` | Platform / node | CIS Benchmark. Good extra hardening evidence. |
| `ocp4-e8`, `rhcos4-e8` | Platform / node | ACSC Essential Eight. Optional. |

> List the profiles available in your cluster with
> `oc get profiles.compliance -n openshift-compliance`. Profile content changes between Compliance
> Operator releases.

### Install the Compliance Operator

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-compliance
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: compliance-operator
  namespace: openshift-compliance
spec:
  targetNamespaces:
    - openshift-compliance
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: compliance-operator
  namespace: openshift-compliance
spec:
  channel: stable
  name: compliance-operator
  source: redhat-operators            # or your mirrored catalog source in disconnected clusters
  sourceNamespace: openshift-marketplace
```

### Schedule the PBMM baseline scans

```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSetting
metadata:
  name: itsg33-pbmm
  namespace: openshift-compliance
schedule: "0 1 * * *"                  # Daily at 01:00 — supports CA-7 continuous monitoring
roles:
  - master
  - worker
rawResultStorage:
  rotation: 90                         # Keep 90 sets of raw ARF results (align with AU-11)
  size: 5Gi
autoApplyRemediations: false           # Review remediations through change control (CM-3)
autoUpdateRemediations: false
---
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: itsg33-pbmm
  namespace: openshift-compliance
profiles:
  - apiGroup: compliance.openshift.io/v1alpha1
    kind: Profile
    name: ocp4-moderate
  - apiGroup: compliance.openshift.io/v1alpha1
    kind: Profile
    name: ocp4-moderate-node
  - apiGroup: compliance.openshift.io/v1alpha1
    kind: Profile
    name: rhcos4-moderate
settingsRef:
  apiGroup: compliance.openshift.io/v1alpha1
  kind: ScanSetting
  name: itsg33-pbmm
```

> If you use custom node pools (for example, `infra`), add them to `roles`. Node scans run once
> per role.

### Tailor the profile to ITSG-33 PBMM

Use a `TailoredProfile` to:

- set variables to GC-specific values (for example, banner text and session timeouts),
- disable rules for controls your PBMM profile doesn't select, or that you meet another way
  (record the rationale), and
- give the profile a clear ITSG-33 name for reporting.

```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: TailoredProfile
metadata:
  name: ocp4-itsg33-pbmm
  namespace: openshift-compliance
spec:
  extends: ocp4-moderate
  title: "ITSG-33 PBMM tailored profile for OpenShift platform"
  description: >-
    Extends NIST SP 800-53 Moderate content with GC PBMM parameter values.
  setValues:
    - name: ocp4-var-oauth-inactivity-timeout
      rationale: "AC-11 / AC-12: departmental session inactivity limit of 15 minutes"
      value: "15m0s"
  disableRules:
    - name: ocp4-<rule-name>
      rationale: "Control met by <compensating control>; see SSP section <x>"
```

> Variable and rule names change between Compliance Operator content releases. List them with
> `oc get variables.compliance -n openshift-compliance` and
> `oc get rules.compliance -n openshift-compliance`. Then update the `ScanSettingBinding` to point
> to the `TailoredProfile` (`kind: TailoredProfile`) instead of `ocp4-moderate`.

### Map rules to ITSG-33 controls

Each Compliance Operator rule carries a NIST SP 800-53 annotation. Because ITSG-33 uses the same
identifiers, you can build an ITSG-33 view straight from the cluster:

```bash
# List every rule that supports a given control (example: AU-9)
oc get rules.compliance -n openshift-compliance -o json \
  | jq -r '.items[]
      | select(.metadata.annotations["control.compliance.openshift.io/NIST-800-53"] // ""
               | split(";") | index("AU-9"))
      | .metadata.name'

# Build a CSV of rule -> NIST/ITSG-33 controls for the whole cluster
oc get rules.compliance -n openshift-compliance -o json \
  | jq -r '.items[]
      | [.metadata.name,
         (.metadata.annotations["control.compliance.openshift.io/NIST-800-53"] // "")]
      | @csv' > rule-to-control-map.csv
```

### Evidence from scans

```bash
# Overall scan status
oc get compliancesuites,compliancescans -n openshift-compliance

# Failing checks (feeds your Plan of Action and Milestones, CA-5)
oc get compliancecheckresults -n openshift-compliance \
  -l compliance.openshift.io/check-status=FAIL

# Checks that need manual review
oc get compliancecheckresults -n openshift-compliance \
  -l compliance.openshift.io/check-status=MANUAL

# Export all results with severity, for the evidence bundle
oc get compliancecheckresults -n openshift-compliance -o json \
  | jq -r '.items[] | [.metadata.name, .status, .severity] | @csv' > check-results.csv

# Pending remediations (review before applying)
oc get complianceremediations -n openshift-compliance
```

Raw ARF (XCCDF) results are stored on PVCs. You can fetch them with the `oc-compliance` plugin
(`oc compliance fetch-raw scansettingbindings itsg33-pbmm -n openshift-compliance -o ./evidence`)
or by mounting the PVC in a pod. ARF output can be loaded into SCAP-aware GRC tools.

## Red Hat Advanced Cluster Management — governance

ACM policies enforce or audit configuration across a fleet. They also show compliance status and
history centrally. Policies carry `standards`, `categories`, and `controls` annotations. **Use
these to label policies with ITSG-33 identifiers** so the governance dashboard reports in ITSG-33
terms.

```yaml
apiVersion: policy.open-cluster-management.io/v1
kind: Policy
metadata:
  name: itsg33-ac-8-login-banner
  namespace: itsg33-policies
  annotations:
    policy.open-cluster-management.io/standards: ITSG-33
    policy.open-cluster-management.io/categories: AC Access Control
    policy.open-cluster-management.io/controls: AC-8 System Use Notification
spec:
  remediationAction: inform            # Switch to enforce once validated
  disabled: false
  policy-templates:
    - objectDefinition:
        apiVersion: policy.open-cluster-management.io/v1
        kind: ConfigurationPolicy
        metadata:
          name: itsg33-ac-8-console-banner
        spec:
          remediationAction: inform
          severity: medium
          object-templates:
            - complianceType: musthave
              objectDefinition:
                apiVersion: console.openshift.io/v1
                kind: ConsoleNotification
                metadata:
                  name: itsg33-classification-banner
```

ACM can also **check that the Compliance Operator is installed and that scans pass** across all
managed clusters, by using a `ConfigurationPolicy` that looks at `ComplianceCheckResult` objects.
This gives you a single view for CA-7.

> **Tip:** Generate policies with the **PolicyGenerator** Kustomize plugin from plain manifests kept
> in Git. Each manifest folder can map to one ITSG-33 control.

## Red Hat Advanced Cluster Security

RHACS provides:

- **Compliance reports** against NIST SP 800-53 and other standards, scheduled and exportable as
  CSV (CA-2, CA-7)
- **Vulnerability management** for images, nodes, and the platform, with fixability and risk
  ranking (RA-5, SI-2)
- **Policy enforcement** at build time (`roxctl` in CI), deploy time (admission controller), and
  runtime (SI-3, SI-4, CM-7)
- **Network graph** and generated `NetworkPolicy` suggestions (AC-4, SC-7)
- **Integration** with the SIEM, ticketing, and notification systems (IR-5, IR-6)

## Evidence bundle structure (proposed)

For each assessment cycle (for example, quarterly, or before an authorization decision), build
a versioned evidence bundle:

```text
evidence/
  <cluster-name>/<YYYY-MM-DD>/
    00-metadata/            cluster version, infrastructure, operator versions (oc get clusterversion, csv -A)
    01-compliance-operator/ ARF results, check-results.csv, remediations, tailored profile
    02-acm-governance/      policy compliance status and history export
    03-rhacs/               compliance report CSV, vulnerability report, policy list
    04-configuration/       exports of config.openshift.io resources, OAuth, APIServer, IngressControllers, Network
    05-rbac/                cluster role bindings, privileged SCC usage, group membership
    06-logging/             ClusterLogForwarder config, SIEM receipt confirmation sample
    07-integrity/           FileIntegrityNodeStatus, failed AIDE reports
    08-backup/              OADP schedules, last successful backup, restore test record
    README.md               index mapping each artifact to ITSG-33 controls
```

### Example collection script (starter)

```bash
#!/usr/bin/env bash
# collect-evidence.sh — starter script; extend per control family.
set -euo pipefail
CLUSTER=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
OUT="evidence/${CLUSTER}/$(date +%F)"
mkdir -p "${OUT}"/{00-metadata,01-compliance-operator,04-configuration,05-rbac,06-logging,07-integrity,08-backup}

# 00 — metadata
oc get clusterversion version -o yaml        > "${OUT}/00-metadata/clusterversion.yaml"
oc get csv -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase \
                                             > "${OUT}/00-metadata/operators.txt"
oc get nodes -o wide                         > "${OUT}/00-metadata/nodes.txt"

# 01 — Compliance Operator (CA-2, CA-7, CM-6, SI-6)
oc get compliancecheckresults -n openshift-compliance -o json \
  | jq -r '.items[] | [.metadata.name, .status, .severity] | @csv' \
                                             > "${OUT}/01-compliance-operator/check-results.csv"
oc get tailoredprofiles,scansettingbindings -n openshift-compliance -o yaml \
                                             > "${OUT}/01-compliance-operator/tailoring.yaml"

# 04 — configuration (CM-2, AC-8, AC-12, SC-8, SC-13, SC-28)
for r in apiservers oauths images proxies networks ingresses consoles; do
  oc get "${r}.config.openshift.io" cluster -o yaml \
                                             > "${OUT}/04-configuration/${r}.yaml"
done
oc get ingresscontrollers -n openshift-ingress-operator -o yaml \
                                             > "${OUT}/04-configuration/ingresscontrollers.yaml"
oc get consolenotifications -o yaml          > "${OUT}/04-configuration/consolenotifications.yaml"

# 04 — network isolation (AC-4, SC-4, SC-7)
oc get clusteruserdefinednetworks,userdefinednetworks -A -o yaml \
                                             > "${OUT}/04-configuration/user-defined-networks.yaml"
oc get ns -L itsg33/zone,k8s.ovn.org/primary-user-defined-network \
                                             > "${OUT}/04-configuration/namespace-zones.txt"
oc get adminnetworkpolicies,baselineadminnetworkpolicies -o yaml \
                                             > "${OUT}/04-configuration/admin-network-policies.yaml"
oc get routeadvertisements -o yaml           > "${OUT}/04-configuration/routeadvertisements.yaml" 2>/dev/null || true

# 05 — RBAC (AC-2, AC-5, AC-6)
oc get clusterrolebindings -o json \
  | jq -r '.items[] | select(.roleRef.name=="cluster-admin")
           | [.metadata.name, ([.subjects[]? | .kind + ":" + .name] | join(" "))] | @tsv' \
                                             > "${OUT}/05-rbac/cluster-admin-bindings.tsv"
oc get groups -o yaml                        > "${OUT}/05-rbac/groups.yaml"

# 06 — logging (AU-4, AU-9)
oc get clusterlogforwarders.observability.openshift.io -A -o yaml \
                                             > "${OUT}/06-logging/clusterlogforwarders.yaml"

# 07 — integrity (SI-7)
oc get fileintegritynodestatuses -n openshift-file-integrity -o wide \
                                             > "${OUT}/07-integrity/status.txt" || true

# 08 — backup (CP-9)
oc get schedules.velero.io,backups.velero.io -n openshift-adp \
                                             > "${OUT}/08-backup/backups.txt" || true

# Integrity of the bundle itself (AU-9, AU-10)
( cd "${OUT}" && find . -type f -exec sha256sum {} \; > SHA256SUMS )
echo "Evidence written to ${OUT}"
```

> Treat evidence bundles as **Protected B** if they include configuration details of a Protected B
> system. Store them in an approved repository with access control.
