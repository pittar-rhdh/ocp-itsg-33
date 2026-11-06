# Operators

[← Phase 4 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Each operator has a component in `04-gitops/components/operators/<package>/` with its
Namespace, OperatorGroup, and Subscription. The `itsg33-operators` application applies them. All
of them come from the mirrored catalog (`cs-redhat-operator-index-v4-22`) and use
`installPlanApproval: Manual`.

| Package | Namespace | Install mode | Channel | Purpose |
|---|---|---|---|---|
| `openshift-gitops-operator` | `openshift-gitops-operator` | All namespaces | `latest` | Argo CD (also applied by the bootstrap) |
| `advanced-cluster-management` | `open-cluster-management` | Own namespace | `release-2.16` | Governance; installs `multicluster-engine` itself |
| `rhacs-operator` | `rhacs-operator` | All namespaces | `stable` | Central and SecuredCluster (in `stackrox`) |
| `compliance-operator` | `openshift-compliance` | Own namespace | `stable` | OpenSCAP scans |
| `file-integrity-operator` | `openshift-file-integrity` | Own namespace | `stable` | AIDE on every node |
| `openshift-cert-manager-operator` | `cert-manager-operator` | All namespaces | `stable-v1` | Certificates (before External Secrets) |
| `openshift-external-secrets-operator` | `external-secrets-operator` | All namespaces | `stable-v1` | Secrets from the departmental store |
| `loki-operator` | `openshift-operators-redhat` | All namespaces | `stable-6.7` | Log store (same channel as Logging) |
| `cluster-logging` | `openshift-logging` | All namespaces | `stable-6.7` | Collection and forwarding |
| `cluster-observability-operator` | `openshift-cluster-observability-operator` | All namespaces | `stable` | Console log view |
| `redhat-oadp-operator` | `openshift-adp` | Own namespace | `stable` | Backups |
| `cincinnati-operator` | `openshift-update-service` | Own namespace | `v1` | OpenShift Update Service (AD-19) |

**Confirm every channel against the mirrored catalog** before the first sync:
`01-mirror/03-list-operator-channels.sh <package>` on the low side, or
`oc get packagemanifest <package> -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'`
on the cluster. `versions.env` mirrors the head of every channel of these packages, so the
channel must exist in the catalog but the Subscription decides which one is used. The table
reflects Red Hat documentation and catalog conventions at the time of writing, not a live
catalog.

Mirrored but not subscribed here: `kubernetes-nmstate-operator`, `metallb-operator`,
`security-profiles-operator` (add a component when they are needed), and `multicluster-engine`
(ACM subscribes to it).

## Ordering constraints

| Constraint | Source | How it is handled |
|---|---|---|
| cert-manager must be installed and working before External Secrets | OpenShift 4.22 Security and compliance, External Secrets Operator | Approve the cert-manager install plan first; the ESO operand needs its own configuration before use |
| Logging and Loki on the same major.minor channel, updated together (Loki first) | Logging 6 upgrade documentation | Both components use `stable-6.7`; approve Loki, then Logging |
| RHACS offline mode can only be set when Central is first created | RHACS "Enabling offline mode" | `egress.connectivityPolicy: Offline` is in Git from the first sync |
| ACM in a disconnected cluster must be told which catalog to use for multicluster-engine | ACM 2.16 install documentation | `installer.open-cluster-management.io/mce-subscription-spec` annotation on the MultiClusterHub, patched by the overlay |
| Manual approval in a namespace applies to every operator in it | OpenShift 4.22 Operators | One operator per namespace |

## Approving install plans

```bash
04-gitops/02-approve-installplans.sh                      # pending plans and their CSVs
CHANGE_ID=CHG0012345 04-gitops/02-approve-installplans.sh openshift-compliance/install-abcde
CHANGE_ID=CHG0012345 04-gitops/02-approve-installplans.sh --all-in-repo   # initial install only
```

Every approval is appended to `EVIDENCE_DIR/changes.tsv` with the time, change ticket, cluster
user, host user, and the CSV names (CM-3, SI-2). Before approving an update, check the operator
release notes and its supported OpenShift versions. For a new operator version, the flow is:
low-side mirror (Phase 1) → transfer and import (Phase 2) → new catalog source contents →
install plan appears → review and approve.
