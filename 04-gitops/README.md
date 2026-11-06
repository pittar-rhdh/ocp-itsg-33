# 04-gitops — Phase 4: ITSG-33 Configuration as Code

> **Examples only — not validated.** These are example manifests for a reference guide. They
> render with kustomize and passed `kubeconform -strict` against the upstream Kubernetes and CRD
> schemas, but they have never been applied to a cluster. Read them, adapt them, and test them
> before use. See [validation status](../docs/reference/validation-status.md).

OpenShift GitOps (Argo CD) applies everything in this directory from the departmental Git server.
ACM policies independently report whether the configuration is in place. Full guidance,
including the commands for each manual step:
[docs/04-itsg33-configuration](../docs/04-itsg33-configuration/index.md).

```text
04-gitops/
  bootstrap/                  applied once with oc (GitOps operator + Argo CD controller binding)
  components/
    operators/<package>/      Namespace, OperatorGroup, Subscription (manual approval)
    <capability>/             one Kustomize component per capability, annotated itsg33/controls
  overlays/<cluster>/
    root-app.yaml             the root ("app of apps") Application, applied once with oc
    apps/                     child Applications: itsg33-gitops, -operators, -config, -policies
    gitops/ operators/ config/ policies/   the layers, with cluster-specific patches
  acm-policies/               inform-only ITSG-33 governance policies for local-cluster
```

## How it is applied

1. **Once, with `oc`:** `oc apply --server-side -k 04-gitops/bootstrap`, approve the GitOps
   operator install plan, add the Git server CA and a read-only repository credential to Argo CD,
   then `oc apply -f 04-gitops/overlays/<cluster>/root-app.yaml`.
2. **From then on, Argo CD** syncs the root application and its four child applications from
   Git. Every change is a reviewed pull request.
3. **By hand, under a change ticket:** operator install plan approvals, the Secrets that the
   configuration refers to but Git must never hold, RHACS cluster registration and daily
   vulnerability data upload, and removal of `kubeadmin` and project self-provisioning.

Render a layer locally with `oc kustomize 04-gitops/overlays/ocp1/config` (or `kustomize build`).
