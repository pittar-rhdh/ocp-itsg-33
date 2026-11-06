# Versions and Pinned Content

[← Back to main](../index.md)

This page records the versions the reference design is written for. Two example files carry the
pins that matter at run time:

- `01-mirror/imageset-config.yaml` says **what** is mirrored: the OpenShift release range, the
  operator catalog and packages, and additional images. It is the source of truth for mirrored
  content ([ImageSetConfiguration](../01-mirroring/imageset-configuration.md)).
- `04-gitops/components/operators/*/operator.yaml` says which channel each operator is
  **installed** from ([Operators](../04-itsg33-configuration/operators.md)).

## Rules

1. Change versions only through a reviewed pull request. The Git history is CM-3 (change
   control) evidence.
2. Keep the ImageSetConfiguration and the operator Subscriptions consistent: a Subscription
   channel must be one of the mirrored channels. Change both in the same pull request.
3. Record in each transfer which commit of this repository it was built from
   ([Packaging and transfer](../01-mirroring/packaging-and-transfer.md)).
4. Pin operator channels and minimum versions deliberately, from the catalog listing. See
   [ImageSetConfiguration](../01-mirroring/imageset-configuration.md#operator-entries).

## Versions

| Item | Version | Where it is used |
|---|---|---|
| OpenShift Container Platform | 4.22.18, channel `stable-4.22` (or `eus-4.22`) | Mirrored range and install target (Phases 1–3) |
| `oc`, `oc-mirror` (v2) | 4.22.18 | Low-side mirroring; high-side import and administration |
| `openshift-install-fips` | From the mirrored 4.22.18 release | Installation (Phase 3) |
| `ImageSetConfiguration` API | `mirror.openshift.io/v2alpha1` | `01-mirror/imageset-config.yaml` |
| mirror registry for Red Hat OpenShift | 2.0.9 | High-side registry (Phase 2) |
| Butane | 0.29.0-1 (`variant: openshift`, `version: 4.22.0`) | Install-time MachineConfigs (Phase 3) |
| RHACS (`roxctl`, offline vulnerability data) | Must match the installed RHACS operator; 4.11.7 was current when this was written | Phases 1 and 4 |
| Advanced Cluster Management | 2.16 (`release-2.16`) | Phase 4 |
| OpenShift Logging and Loki | 6.7 (`stable-6.7`, same channel for both) | Phase 4 |
| RHEL on the mirror workstation, registry host, and provisioner | 9, FIPS mode | Phases 1–3 |

## Operators and why they are mirrored

The package names are **examples**. Confirm every one against the live catalog before the first
import: `oc-mirror list operators` on the low side, or `oc get packagemanifest` on the cluster.
The **Source** column shows where each name was checked against Red Hat documentation (OpenShift 4.22 and layered-product
documentation on docs.redhat.com, November 2026).

| Package | Purpose | Phase | Source |
|---|---|---|---|
| `cincinnati-operator` | OpenShift Update Service (offline update graph) | 6 (upgrades) | Not confirmed in Red Hat documentation; check the catalog |
| `kubernetes-nmstate-operator` | Day 2 host networking | 4 | Not confirmed; check the catalog |
| `metallb-operator` | `LoadBalancer` services on bare metal | 4 | 4.22 Hosted control planes, "Deploying hosted control planes in a disconnected environment" (`ImageSetConfiguration` example) |
| `openshift-gitops-operator` | GitOps (Argo CD) | 4 | Not confirmed; check the catalog |
| `advanced-cluster-management`, `multicluster-engine` | Governance policies and compliance reporting. ACM depends on MCE, and oc-mirror doesn't add dependencies, so both are listed. | 4, 5 | 4.22 Edge computing, "Pre-caching images" (`ImageSetConfiguration` example) |
| `rhacs-operator` | Vulnerability management, admission control, runtime detection | 4, 5 | RHACS 4.11 Installing, chapter 4 (Subscription example) |
| `compliance-operator` | OpenSCAP scans (NIST 800-53 Moderate → ITSG-33 PBMM) | 4, 5 | 4.22 Disconnected environments, "How filtering works in the operator catalog" |
| `file-integrity-operator` | AIDE file integrity monitoring | 4, 5 | Not confirmed; check the catalog |
| `security-profiles-operator` | seccomp and SELinux profiles | 4 | Not confirmed; check the catalog |
| `openshift-cert-manager-operator` | Certificates from the departmental PKI | 4 | 4.22 Security and compliance, chapter 11 (`Subscription` example, channel `stable-v1`) |
| `openshift-external-secrets-operator` | Secrets from the departmental vault. Red Hat requires cert-manager to be installed and working **before** it. | 4 | 4.22 Security and compliance, chapter 13 (`Subscription` example, channel `stable-v1`) |
| `cluster-logging`, `loki-operator` | Log collection, forwarding, short-term storage. Red Hat requires both to be on the **same** channel and updated together. | 4 | OpenShift Logging 6.x upgrade documentation (subscription examples) |
| `cluster-observability-operator` | Logging UI plugin and observability extras | 4 | Not confirmed; check the catalog |
| `redhat-oadp-operator` | Backup and restore | 4, 6 | Not confirmed; check the catalog |
