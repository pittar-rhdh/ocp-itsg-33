# ACM Governance

[← Phase 4 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Argo CD applies the configuration. ACM governance policies, in `04-gitops/acm-policies/`, check
independently that it is in place and report the result in ITSG-33 terms (CA-7). They are
`inform` only: one writer (Git) and one checker (ACM), so a policy can never fight Argo CD.

## Policies

Each policy carries `policy.open-cluster-management.io/standards: ITSG-33`, a `categories`
value with the control family, and a `controls` value, so the ACM Governance dashboard groups
results by ITSG-33 family and control.

| Policy | Checks | Control |
|---|---|---|
| `itsg33-ac-6-no-self-provisioning` | `self-provisioners` doesn't include `system:authenticated:oauth` | AC-6 |
| `itsg33-ac-8-login-banner` | Console banner exists | AC-8 |
| `itsg33-ia-2-kubeadmin-removed` | No `kube-system/kubeadmin` secret | IA-2 |
| `itsg33-au-2-audit-profile` | Audit profile `WriteRequestBodies` | AU-2 |
| `itsg33-au-4-log-forwarding` | `ClusterLogForwarder itsg33-siem` exists | AU-4 |
| `itsg33-sc-28-etcd-encryption` | etcd encryption `aesgcm` | SC-28 |
| `itsg33-cm-7-mirrored-catalogs-only` | Default catalog sources disabled | CM-7 |
| `itsg33-si-7-file-integrity` | Worker `FileIntegrity` exists | SI-7 |
| `itsg33-ra-5-rhacs-offline` | Central in offline mode | RA-5 |
| `itsg33-ca-7-no-high-severity-failures` | No failing high-severity Compliance Operator check | CA-7 |

The first two policies stay non-compliant until `05-lock-down-access.sh` runs, and the RHACS,
logging, and file integrity policies until their operators are installed. That is expected.

## Placement

The policies live in namespace `itsg33-policies`. A `ManagedClusterSetBinding` makes the built-in
`global` cluster set available there, a `Placement` selects the cluster labelled
`local-cluster=true` (the hub itself, AD-04), and a `PlacementBinding` binds every policy to it.
To add managed clusters later, widen the Placement.

```bash
oc get policies -n itsg33-policies
oc get policies -n local-cluster          # the replicated copies with per-cluster status
```

## Why not PolicyGenerator (AD-23)

ACM's `PolicyGenerator` Kustomize plugin can build these policies from plain manifests. The
documented way to use it from OpenShift GitOps (ACM 2.16 GitOps, "Accessing the Policy Generator
from OpenShift GitOps") adds an init container that copies `/policy-generator/PolicyGenerator-not-fips-compliant`
from the ACM subscription image into the Argo CD repo server and enables Kustomize alpha plugins.
In the upstream image build (stolostron/multicloud-operators-subscription), that file is a link
to a RHEL 8 build of the plugin that isn't built for strict FIPS. Running it in the repo server
of a FIPS cluster would bring non-FIPS cryptography into the GitOps path (SC-13).

These policies are therefore written as plain `Policy`, `Placement`, and `PlacementBinding`
resources, which Kustomize applies with no plugin. If you prefer PolicyGenerator, run it in CI
on the low side and commit its output, so the cluster still sees only plain resources.
