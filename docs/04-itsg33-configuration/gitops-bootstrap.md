# GitOps Bootstrap

[← Phase 4 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

The bootstrap is the only time configuration is applied directly with `oc`. After it, every
change goes through Git. Run it from the registry host (or another high-side admin host) in a
clone of the departmental repository, logged in with the installer kubeconfig (the IdP is not
configured yet), under an approved change ticket.

## Before you start

- The mirrored catalog source exists. oc-mirror v2 names it after the catalog image, so
  `redhat-operator-index:v4.22` becomes `cs-redhat-operator-index-v4-22`. The same name is in
  `04-gitops/bootstrap/kustomization.yaml` and `overlays/<cluster>/operators/kustomization.yaml`.
- This repository is on the departmental Git server
  ([Phase 2](../02-high-side/populate-registry.md)), and `overlays/<cluster>/root-app.yaml`,
  `apps/kustomization.yaml`, and `gitops/kustomization.yaml` all use that HTTPS URL (SC-8).
- A **read-only** deploy token for that repository in a file outside Git (mode 0600), and the CA
  that signed the Git server certificate.

```bash
oc whoami && oc auth can-i '*' '*' --all-namespaces          # cluster-admin
oc get catalogsource -n openshift-marketplace
oc get packagemanifest openshift-gitops-operator -n openshift-marketplace
grep -n 'repoURL\|value: https' 04-gitops/overlays/ocp1/root-app.yaml \
  04-gitops/overlays/ocp1/apps/kustomization.yaml 04-gitops/overlays/ocp1/gitops/kustomization.yaml
```

## Steps

| Step | Action | Controls |
|---|---|---|
| Operator | Server-side apply of `bootstrap/`: namespace `openshift-gitops-operator`, OperatorGroup (all namespaces), Subscription (channel `latest`, **Manual**) | CM-3, CM-11 |
| Approval | Approve the first install plan; record it in the change ticket | CM-3 |
| Argo CD RBAC | ClusterRoleBinding `itsg33-gitops-cluster-admin` for the application controller (see below), also in `bootstrap/` | AC-6 |
| Git trust | Add the Git server CA to `argocd-tls-certs-cm` under the Git host name | SC-8, SC-23 |
| Credential | Secret `itsg33-gitops-repo` (label `argocd.argoproj.io/secret-type: repository`) with the URL, user, and token | IA-5 |
| Root app | Apply `overlays/<cluster>/root-app.yaml` | CM-2 |

**1. Install the operator and approve its install plan:**

```bash
oc apply --server-side -k 04-gitops/bootstrap
# or: oc kustomize 04-gitops/bootstrap | oc apply --server-side -f -

oc get installplan -n openshift-gitops-operator      # wait until a plan appears
oc get installplan <install-xxxxx> -n openshift-gitops-operator \
  -o jsonpath='{.spec.clusterServiceVersionNames}{"\n"}'
oc patch installplan <install-xxxxx> -n openshift-gitops-operator \
  --type merge -p '{"spec":{"approved":true}}'

oc get csv -n openshift-gitops-operator               # wait for PHASE Succeeded
oc wait argocd.argoproj.io/openshift-gitops -n openshift-gitops \
  --for=jsonpath='{.status.phase}'=Available --timeout=15m
```

**2. Trust the Git server CA.** The key is the Git host name:

```bash
oc create configmap argocd-tls-certs-cm -n openshift-gitops \
  --from-file=git.example.gc.ca=dept-root-ca.crt --dry-run=client -o json \
  | jq '{data: .data}' \
  | oc patch configmap argocd-tls-certs-cm -n openshift-gitops --type merge --patch-file /dev/stdin
```

**3. Add the read-only repository credential.** Read the token from a file so it is not on the
command line or in the shell history, and strip the trailing newline, which would otherwise
become part of the password:

```bash
umask 077
tr -d '\r\n' < ~/.config/ocp-gitops/git-token > /tmp/git-password
oc create secret generic itsg33-gitops-repo -n openshift-gitops \
  --from-literal=type=git \
  --from-literal=url=https://git.example.gc.ca/platform/ocp-itsg-33.git \
  --from-literal=username=ocp1-argocd \
  --from-file=password=/tmp/git-password \
  --dry-run=client -o yaml \
  | oc label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
  | oc apply -f -
rm -f /tmp/git-password
```

**4. Hand over to Git:**

```bash
oc apply -f 04-gitops/overlays/ocp1/root-app.yaml
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}{"\n"}'
```

Record in the change ticket: the Git commit applied (`git rev-parse HEAD`), the install plan and
CSV approved, and the repository credential name (never its value).

The GitOps operator creates the default Argo CD instance `openshift-gitops`. The operator reads
`spec.tls.initialCerts` only when it creates an instance (argocd-operator source), so step 2
writes the Git CA straight into `argocd-tls-certs-cm` instead.

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
```

The `itsg33-config` application stays OutOfSync or Progressing until the operator install plans
are approved ([Operators](operators.md)) and the secrets exist
([Platform configuration](platform-configuration.md#secrets-kept-outside-git)).
