# Repository Layout

[← Phase 4 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

```text
04-gitops/
  bootstrap/                    applied once with oc (GitOps bootstrap)
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

Check every change before it is merged (CM-3, CM-4, SA-11): in CI on the low side for every pull
request, and on the high side before every merge. None of these checks needs a cluster, except
the optional server-side dry run.

**1. Render every layer.** `oc kustomize` and `kustomize build` give the same output:

```bash
mkdir -p rendered
for d in bootstrap overlays/ocp1/{apps,gitops,operators,config,policies}; do
  oc kustomize "04-gitops/${d}" > "rendered/${d//\//_}.yaml" || echo "FAIL ${d}"
done
```

**2. Validate against schemas** with kubeconform. `-ignore-missing-schemas` skips kinds with no
schema (the project `Template`, for example) instead of failing:

```bash
kubeconform -strict -summary -ignore-missing-schemas \
  -schema-location default \
  -schema-location '<crd-catalog>/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  rendered/*.yaml
```

`default` is the Kubernetes schema set on GitHub and `<crd-catalog>` a copy of the datreeio
CRDs-catalog; both need internet access or a mirrored copy. On the high side, generate schemas
from the cluster's own CRDs with `openapi2jsonschema.py` from the kubeconform project:

```bash
oc get crd -o yaml > crds.yaml
mkdir -p schemas && cd schemas
FILENAME_FORMAT='{kind}_{version}' python3 ../openapi2jsonschema.py ../crds.yaml
cd ..
kubeconform -strict -summary -ignore-missing-schemas \
  -schema-location <mirrored-k8s-schemas> \
  -schema-location 'schemas/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' rendered/*.yaml
```

**3. Lint the YAML:**

```bash
yamllint -s -d '{extends: default, rules: {line-length: disable, document-start: disable,
  comments: {min-spaces-from-content: 1}, comments-indentation: disable,
  braces: {max-spaces-inside: 1}, truthy: {check-keys: false}}}' 04-gitops
```

**4. Review rules.** Reviewers check these, and CI can grep for them:

- Every object has an `itsg33/controls` annotation.
- No `Secret` objects in Git (IA-5, SC-28).
- Every Subscription uses `installPlanApproval: Manual` and the same catalog source.
- One Git URL in `root-app.yaml`, the child applications, and the AppProject.
- No CHACHA20 ciphers (not FIPS-approved) and no `insecureSkipVerify: true`.

```bash
grep -h '^kind:' rendered/*.yaml | wc -l                       # objects
grep -h 'itsg33/controls:' rendered/*.yaml | wc -l             # must be the same number
grep -l '^kind: Secret$' rendered/*.yaml                       # must print nothing
grep -h 'installPlanApproval:\|^  source: ' rendered/*.yaml | sort | uniq -c   # Manual, one source
grep -rhoE 'https://git[^ "]*' 04-gitops/overlays | sort -u     # one URL
grep -iE 'chacha20|insecureSkipVerify: *true' rendered/*.yaml   # must print nothing
```

**5. Optional, with cluster access:** a server-side dry run. Before the operators are installed,
custom resources whose CRDs do not exist yet are reported as errors; that is expected.

```bash
for f in rendered/*.yaml; do oc apply --server-side --dry-run=server -f "${f}"; done
```

## Making a change

1. Branch, edit the component or overlay, and run the [validation](#validation-and-ci).
2. Open a pull request that names the change ticket and the controls affected; get a review from
   someone other than the author (CM-3, AC-5).
3. On the low side, the change reaches the high side with the next transfer and is published to
   departmental Git ([Phase 2](../02-high-side/populate-registry.md)); on the high side, merge
   in departmental Git.
4. Argo CD syncs. For operator updates, approve the install plan
   ([Operators](operators.md#approving-install-plans)).
5. Check the ACM policies and the next Compliance Operator scan (Phase 5).

Changes that reboot nodes (`KubeletConfig`, MachineConfigs) or re-encrypt etcd need a
maintenance window.
