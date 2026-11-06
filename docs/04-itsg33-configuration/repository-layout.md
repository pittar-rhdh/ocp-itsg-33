# Repository Layout

[← Phase 4 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

```text
04-gitops/
  bootstrap/                    applied once by 01-bootstrap-gitops.sh
  components/
    operators/<package>/        Namespace + OperatorGroup + Subscription
    gitops/  gitops-rbac/       Argo CD settings, AppProject, controller binding
    identity/ rbac/ ...         one Kustomize component per capability
  overlays/
    ocp1/
      root-app.yaml
      apps/                     child Applications
      gitops/ operators/ config/ policies/
  acm-policies/                 ITSG-33 governance policies
```

## Components

Each directory under `components/` is a Kustomize `Component` for one capability, not one
control: a capability usually meets several controls, and one OpenShift resource can hold
settings for several families. For example, `components/api-server/apiserver.yaml` holds the
audit policy (AU), the TLS profile (SC-8, SC-13), and etcd encryption (SC-28), because
`APIServer/cluster` is a single object and must have one owner.

Every object carries an `itsg33/controls` annotation listing the controls it implements. On the
cluster you can list them:

```bash
oc get oauth,apiserver,image -o custom-columns='KIND:.kind,NAME:.metadata.name,CONTROLS:.metadata.annotations.itsg33/controls'
```

The [control family guides](controls/index.md) point at the component files. The YAML lives only
in `04-gitops/`, so there is one source of truth.

## Overlays

`overlays/<cluster>/` selects components and patches the values that differ per cluster:

| Value | Where |
|---|---|
| Git URL and branch | `root-app.yaml`, `apps/kustomization.yaml`, `gitops/kustomization.yaml` |
| Catalog source name | `operators/kustomization.yaml` (all Subscriptions), `config/kustomization.yaml` (MultiClusterHub annotation), `bootstrap/kustomization.yaml` |
| Storage class of the CSI driver (AD-13) | `config/kustomization.yaml` (LokiStack, ScanSetting, Central) |
| Cluster name | `config/kustomization.yaml` (SecuredCluster, OADP bucket) |

Other values (IdP issuer and client ID, SIEM address, S3 endpoint, allowed registries, banner
text) are example values in the components. Change them in the component when every cluster uses
the same value, or add a patch in the overlay when they differ. To add a cluster, copy
`overlays/ocp1` and change the values above.

Components not enabled in the example overlay: `cert-manager-pki` (needs the departmental ACME
service). Not in Git yet: infra node placement (AD-17), the OpenShift Update Service instance
(`UpdateService` from oc-mirror's `updateService.yaml`), and `ExternalSecret` resources.

## Validation and CI

`04-gitops/07-validate.sh` runs without a cluster and should run in CI on the low side for every
pull request, and on the high side before every merge (CM-3, CM-4, SA-11):

1. Renders `bootstrap/` and every overlay layer with `kustomize build` (or `oc kustomize`).
2. Repository rules: every object has `itsg33/controls`; no `Secret` objects; every Subscription
   uses `installPlanApproval: Manual` and the same catalog source; one Git URL; no CHACHA20
   ciphers; no `insecureSkipVerify: true`.
3. `yamllint`, `kubeconform -strict`, and `shellcheck`, when installed.
4. With `--server`: a server-side dry run against the cluster.

kubeconform needs JSON schemas. The defaults (Kubernetes schemas and the datreeio CRD catalog)
need internet access. On the high side, generate schemas from the cluster's own CRDs and set
`KUBECONFORM_LOCAL_SCHEMAS`:

```bash
oc get crd -o yaml > crds.yaml
FILENAME_FORMAT='{kind}_{version}' python3 openapi2jsonschema.py crds.yaml   # from the kubeconform project
KUBECONFORM_LOCAL_SCHEMAS=$PWD KUBECONFORM_K8S_SCHEMAS=<mirrored-k8s-schemas> 04-gitops/07-validate.sh
```

## Making a change

1. Branch, edit the component or overlay, run `04-gitops/07-validate.sh`.
2. Open a pull request that names the change ticket and the controls affected; get a review from
   someone other than the author (CM-3, AC-5).
3. On the low side, the change reaches the high side with the next transfer; on the high side,
   `02-high-side/08-publish-repo.sh` fast-forwards departmental Git.
4. Argo CD syncs. For operator updates, approve the install plan
   ([Operators](operators.md#approving-install-plans)).
5. Check the ACM policies and the next Compliance Operator scan (Phase 5).

Changes that reboot nodes (`KubeletConfig`, MachineConfigs) or re-encrypt etcd need a
maintenance window.
