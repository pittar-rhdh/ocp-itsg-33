# GitOps Bootstrap

[← Phase 4 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

`04-gitops/01-bootstrap-gitops.sh` is the only step that applies configuration directly. After
it, every change goes through Git.

## Before you start

- The mirrored catalog source exists: `oc get catalogsource -n openshift-marketplace`. oc-mirror v2
  names it after the catalog image, so `redhat-operator-index:v4.22` becomes
  `cs-redhat-operator-index-v4-22` (`CATALOG_SOURCE`). The same name is in
  `04-gitops/bootstrap/kustomization.yaml` and `overlays/<cluster>/operators/kustomization.yaml`.
- This repository is on the departmental Git server (`GIT_REMOTE_URL`, published by
  `02-high-side/08-publish-repo.sh`), and `overlays/<cluster>/root-app.yaml`,
  `apps/kustomization.yaml`, and `gitops/kustomization.yaml` use that URL. `07-validate.sh` fails
  if they differ.
- A **read-only** deploy token for that repository in `GIT_TOKEN_FILE` (mode 0600), and the CA
  that signed the Git server certificate in `GIT_CA_FILE`. HTTPS only (SC-8).
- A change ticket in `CHANGE_ID`.

## What the script does

| Step | Action | Controls |
|---|---|---|
| Checks | cluster-admin; catalog source and `openshift-gitops-operator` package present; Git URL, CA, and token mode | CM-3 |
| Operator | Server-side apply of `bootstrap/`: namespace `openshift-gitops-operator`, OperatorGroup (all namespaces), Subscription (channel `latest`, **Manual**) | CM-3, CM-11 |
| Approval | Approves the first install plan and records it in `EVIDENCE_DIR/changes.tsv` | CM-3 |
| Argo CD RBAC | ClusterRoleBinding `itsg33-gitops-cluster-admin` for the application controller (see below) | AC-6 |
| Git trust | Adds the Git server CA to `argocd-tls-certs-cm` under the Git host name | SC-8, SC-23 |
| Credential | Secret `itsg33-gitops-repo` (label `argocd.argoproj.io/secret-type: repository`) with the URL, user, and token | IA-5 |
| Root app | Applies `overlays/<cluster>/root-app.yaml` | CM-2 |

The GitOps operator creates the default Argo CD instance `openshift-gitops`. The operator reads
`spec.tls.initialCerts` only when it creates an instance (argocd-operator source), so the Git CA
is written straight into `argocd-tls-certs-cm` instead.

## Applications

The root application syncs `overlays/<cluster>/apps`, which holds four child applications in the
AppProject `itsg33-platform`:

| Application | Path | Contents |
|---|---|---|
| `itsg33-gitops` | `overlays/<cluster>/gitops` | Argo CD settings, the controller binding, the AppProject |
| `itsg33-operators` | `overlays/<cluster>/operators` | Every operator Subscription |
| `itsg33-config` | `overlays/<cluster>/config` | Platform configuration (identity, audit, TLS, logging, scans, RHACS, ACM hub, backups) |
| `itsg33-policies` | `overlays/<cluster>/policies` | ACM governance policies |

Sync behaviour (AD-22):

- **Server-side apply.** Cluster singletons (`OAuth`, `APIServer`, `Image`, `OperatorHub`,
  `IngressController/default`) are created by OpenShift. Git owns only the fields it sets.
- **`selfHeal: true`.** Manual changes are reverted (CM-6). Make emergency changes in Git, or
  disable auto-sync on the application and record why.
- **`prune: false`** for the gitops, operators, and config applications. Objects removed from Git
  show as OutOfSync and a person deletes them. An automatic prune of a singleton or of a stateful
  resource (LokiStack, Central) is not a risk worth taking.
- **Retries.** Custom resources wait for their operators, which wait for install plan approval.
  `SkipDryRunOnMissingResource=true` and unlimited retries with back-off let the config
  application converge once the operators are installed.

## Argo CD access and privileges

`components/gitops/argocd.yaml` sets, on the default instance:

- `rbac.defaultPolicy: ""`: users who are not in a listed group get no access (AC-3, AC-6).
- `ocp-platform-admins` → `role:admin`; `ocp-security-auditors` → `role:readonly`
  (`scopes: [groups]`, groups from the cluster IdP).
- `resourceTrackingMethod: annotation`, so objects that other controllers copy, such as the
  ACM policies replicated into the `local-cluster` namespace, aren't treated as Argo CD objects.

The default instance can manage only a small set of cluster-scoped resources. Platform
configuration needs `cluster-admin`, granted to `openshift-gitops-argocd-application-controller`
by `components/gitops-rbac/controller-rbac.yaml`. This is a deliberate, high privilege. The
compensating controls are that only the reviewed repository is a permitted source (AppProject),
merges need review, and only `ocp-platform-admins` can sync or change Argo CD. Record this in the
SSP (AC-6).

## Verify

```bash
oc get subscription,csv -n openshift-gitops-operator
oc get applications.argoproj.io -n openshift-gitops
oc get appproject itsg33-platform -n openshift-gitops -o yaml
column -t -s $'\t' "${EVIDENCE_DIR}/changes.tsv"
```

The `itsg33-config` application stays OutOfSync or Progressing until the operator install plans
are approved ([Operators](operators.md)) and the secrets exist
([Platform configuration](platform-configuration.md#secrets-kept-outside-git)).
