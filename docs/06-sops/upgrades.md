# Upgrades

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Updates use content already made available by a [content import](content-import.md). Commands
follow OpenShift 4.22 *Updating clusters* and *Disconnected environments* ch. 12. Always use `oc`
**for the target version** (`export PATH=/data/ocp/tools/<target>/bin:$PATH`) and log in through the
IdP as `ocp-platform-admins` (with the break-glass kubeconfig, `recommend` skips alert checks).

## One-time setup: OpenShift Update Service

| | |
|---|---|
| **Purpose** | Serve recommended update paths from mirrored graph data (AD-19) |
| **When** | Once, before the first upgrade |
| **Roles** | Platform engineer performs; second reviewer reviews the PR; change manager approves |
| **Prerequisites** | `cincinnati-operator` install plan approved ([Operators](../04-itsg33-configuration/operators.md#approving-install-plans)); `/data/ocp/cluster-resources/current/updateService.yaml` exists (ISC `graph: true`) |
| **Controls** | SI-2, CM-3, SC-8 |

### Procedure

1. PR to `04-gitops/components/image-policy/`: ConfigMap `mirror-registry-ca` in `openshift-config`
   (annotation `itsg33/controls: "SC-8,SI-2"`), root CA under key **`updateservice-registry`** (Red
   Hat requirement); `spec.additionalTrustedCA.name: mirror-registry-ca` in `image.yaml`.
2. Apply the generated `UpdateService` ([not in Git](../02-high-side/populate-registry.md#cluster-resources)):

   ```bash
   oc apply -n openshift-update-service -f /data/ocp/cluster-resources/current/updateService.yaml
   NAME=$(oc get updateservice -n openshift-update-service -o jsonpath='{.items[0].metadata.name}')
   URI="$(oc get updateservice "$NAME" -n openshift-update-service \
     -o jsonpath='{.status.policyEngineURI}')/api/upgrades_info/v1/graph"   # repeat until https://...
   ```

3. Point the CVO at it (ingress CA must be in the [trust bundle](certificate-rotation.md#update-the-cluster-trust-bundle)):
   `oc patch clusterversion version --type merge -p "{\"spec\":{\"upstream\":\"${URI}\"}}"`

### Verification

```bash
curl -fsS --cacert /etc/pki/ocp-registry/ca-bundle.crt -H 'Accept: application/json' \
  "${URI}?channel=stable-4.22" | jq -r '.nodes[].version' | sort -V | tail -3
oc adm upgrade recommend          # shows the local upstream and the mirrored versions
```

### Rollback

Remove `spec.upstream` from `clusterversion/version`; upgrade by explicit digest ([z-stream](#z-stream-upgrade)).

### Records

The PR, the `upstream` value, and the verification output, in the change ticket.

## Z-stream upgrade

| | |
|---|---|
| **Purpose** | Update within 4.22 (e.g. 4.22.18 → 4.22.z) for security and bug fixes, with OSUS or to an explicit digest |
| **When** | Monthly after an import; on demand for an emergency CVE |
| **Roles** | Platform engineer performs; platform lead approves the version; change manager approves the window; DSO and app teams informed |
| **Prerequisites** | Target release and signature imported; maintenance window (nodes drain and reboot one at a time); etcd backup from **this** z-stream taken in the window and copied off the node ([Backup and restore](backup-and-restore.md)) |
| **Controls** | SI-2, CM-3, CM-4, CP-9, SI-7 |

### Procedure

1. Run the pre-checks and record the output, then pause any `MachineHealthCheck`
   (`oc -n openshift-machine-api annotate mhc <name> cluster.x-k8s.io/paused=""`):

   ```bash
   oc get clusterversion; oc get nodes   # all Ready
   oc get clusteroperators            # Available=True, Progressing=False, Degraded=False
   oc get mcp                         # UPDATED=True, DEGRADED=False, none paused
   oc adm upgrade recommend           # no firing critical alerts; target listed
   oc get clusterversion version \
     -o jsonpath='{.status.conditions[?(@.type=="Upgradeable")].message}{"\n"}'
   oc get pdb -A                      # no ALLOWED DISRUPTIONS 0 that would block a drain
   oc get applications.argoproj.io -n openshift-gitops; oc get mhc -n openshift-machine-api
   ```

2. **With OSUS:** `oc adm upgrade --to=4.22.<z>`.
   **Without OSUS:** confirm the signature is on the cluster, then update to the canonical
   reference (the IDMS resolves it to the mirror). Never use `--force`.

   ```bash
   V=4.22.<z>; PS=~/.config/ocp-registry/cluster-pull-secret.json; CA=/etc/pki/ocp-registry/ca-bundle.crt
   DIGEST=$(oc adm release info -a "$PS" --certificate-authority "$CA" -o json \
     registry.example.gc.ca:8443/mirror/openshift/release-images:"$V"-x86_64 | jq -r .digest)
   oc get configmap -n openshift-config-managed -o json \
     | jq -r '.items[].binaryData // {} | keys[]' | grep "sha256-${DIGEST#sha256:}"   # must print a key
   oc adm upgrade --allow-explicit-upgrade --to-image quay.io/openshift-release-dev/ocp-release@"$DIGEST"
   ```

3. Monitor with `watch oc adm upgrade status`; no other changes ([Troubleshooting](troubleshooting.md)).
4. Unpause each `MachineHealthCheck` (`cluster.x-k8s.io/paused-`).

### Verification

```bash
oc adm upgrade                                         # Cluster version is 4.22.<z>
oc get clusterversion version -o jsonpath='{.status.desired.image}{"\n"}'   # the target digest
oc get clusteroperators; oc get mcp; oc get nodes
oc get applications.argoproj.io -n openshift-gitops; oc get policies -n local-cluster  # Synced/Healthy; Compliant
```

Repeat the node checks (FIPS, LUKS, chrony) from [Verify](../03-cluster-install/run-install.md#verify).
In the next import, raise `minVersion` ([Scheduled import procedure](../01-mirroring/ongoing-imports.md#scheduled-import-procedure)).

### Rollback

Not supported. Support case with `must-gather`; etcd restore only as a last resort, with Red Hat.

### Records

Change ticket: pre-checks, verification, version/digest, etcd backup ref, times; PR to `versions.md`.

## Control Plane Only (EUS-to-EUS) upgrade

| | |
|---|---|
| **Purpose** | Move 4.22 to the next EUS release through the intermediate odd release, with one worker reboot (formerly EUS-to-EUS). `<y+1>` = intermediate, `<y+2>` = target |
| **When** | Per EUS release, once the path is in `eus-<y+2>` (Red Hat: 45–90 days after GA) |
| **Roles** | As for the z-stream; the DSO also approves (baseline change, CM-2) |
| **Prerequisites** | Release notes for `<y+1>` and `<y+2>` reviewed; every operator has a version supporting both (*Operator Update Information Checker*, low side); **both** releases + signatures, `oc` for both, and the `<y+2>` catalog imported (ISC channel `eus-<y+2>`, `minVersion` installed, `maxVersion` target, `shortestPath: true`; check `mapping.txt` for the intermediate) |
| **Controls** | CM-2, CM-3, CM-4, SI-2, CP-9, SA-22 |

> Unverified: Red Hat already documents OpenShift 5.0. Confirm in the update graph and release
> notes which release follows 4.22 and that this path is offered.

### Procedure

1. Update operators to versions compatible with both releases ([Operator upgrade](#operator-upgrade-with-manual-install-plans)).
2. Check for removed APIs and give the admin acknowledgements named in `Upgradeable`:

   ```bash
   oc get apirequestcounts -o jsonpath='{range .items[?(@.status.removedInRelease!="")]}{.status.removedInRelease}{"\t"}{.metadata.name}{"\n"}{end}'
   oc -n openshift-config patch cm admin-acks --type=merge --patch '{"data":{"<ack-key>":"true"}}'
   ```

3. Run the [z-stream](#z-stream-upgrade) pre-checks and take the etcd backup.
4. Set the channel and pause every pool except `master`: `oc adm upgrade channel eus-<y+2>`, then
   `oc patch mcp/worker --type merge --patch '{"spec":{"paused":true}}'`.
5. First hop, with `oc` for `<y+1>`: `oc adm upgrade --to=<y+1.z>` (or `--to-image` as in the
   z-stream). Wait until all cluster operators are healthy.
6. Update operators that must move before the second hop. Take a new etcd backup (same z-stream).
7. Second hop, with `oc` for `<y+2>`: `oc adm upgrade --to=<y+2.z>`. Wait until it completes.
8. Unpause the workers (paused pools block later updates):
   `oc patch mcp/worker --type merge --patch '{"spec":{"paused":false}}'`, then `watch oc get mcp`.
9. PR (lab-tested): switch to the new CatalogSource (e.g. `cs-redhat-operator-index-v<y+2>`) in
   `04-gitops/overlays/ocp1/{operators,config}/kustomization.yaml` (Subscriptions; MultiClusterHub
   annotation) and `04-gitops/bootstrap/kustomization.yaml`. Drop the old catalog from the ISC later.

### Verification

As z-stream, plus new kubelet on every node, no pool paused, and every Subscription on the new
source (`oc get sub -A -o custom-columns=NS:.metadata.namespace,SRC:.spec.source`).

### Rollback

Not supported. If problems appear at `<y+1>`, you may have to unpause the workers and finish `<y+1>` first.

### Records

Z-stream records per hop, admin acks, API check, operator compatibility review, catalog PR.

## Operator upgrade with manual install plans

| | |
|---|---|
| **Purpose** | Update a layered operator within its channel or to a new channel; `installPlanApproval: Manual` everywhere (AD-22) |
| **When** | After an import that brings new operator versions |
| **Roles** | Platform engineer performs; second reviewer reviews channel changes; platform lead approves the install plan |
| **Prerequisites** | New version in the mirrored catalog; release notes and supported OpenShift versions reviewed |
| **Controls** | CM-3, CM-5, CM-11, SI-2 |

### Procedure

1. **Channel change only:** one [PR](../04-itsg33-configuration/repository-layout.md#making-a-change)
   changing `spec.channel` in `04-gitops/components/operators/<package>/operator.yaml` (and in
   `01-mirror/imageset-config.yaml` if needed); let `itsg33-operators` sync.
2. Match pending install plan CSVs to the ticket and [approve them](../04-itsg33-configuration/operators.md#approving-install-plans),
   following the [ordering constraints](../04-itsg33-configuration/operators.md#ordering-constraints)
   (Loki before Logging, cert-manager before External Secrets).
3. Several versions behind: OLM may create a new install plan per step. Review each one.

### Verification

`oc get csv -n <namespace>` shows the new version `Succeeded`; `oc get installplan -n <namespace>`
has nothing unexpected pending; operator resources healthy (e.g. `oc get lokistack -n openshift-logging`);
`itsg33-config` `Healthy`; related ACM policy `Compliant`.

### Rollback

OLM doesn't downgrade: delete the install plan before approval; after, [Troubleshooting](troubleshooting.md).

### Records

The PR, install plan names, CSV versions, who approved and when.

## Mirror registry upgrade and registry host patching

| | |
|---|---|
| **Purpose** | Install a new mirror registry version or apply RHEL errata to the registry host |
| **When** | On demand; not overlapping a cluster upgrade, node maintenance, or import (nodes can't pull new images while the registry is down) |
| **Roles** | Platform engineer performs (as `quay` for the registry, named sudo account for the OS); change manager approves |
| **Prerequisites** | New `mirror-registry-amd64.tar.gz` from an accepted transfer, or RHEL errata from the departmental source; `/data/quay` backed up with `quay-app` stopped ([Backup and restore](../02-high-side/mirror-registry.md#backup-and-restore)), and `/data/ocp` |
| **Controls** | SI-2, CM-3, CM-6, MA-2, CP-9 |

### Procedure

1. **Registry:** run the new installer's `upgrade` as in [Upgrades](../02-high-side/mirror-registry.md#upgrades)
   (from 2.0.11 it keeps hostname and paths; `--sslCert`/`--sslKey` together rotate the certificate).
2. **Host:** `sudo dnf upgrade --refresh`, then `sudo dnf needs-restarting -r || sudo systemctl reboot`.
3. After either, as `quay`:

   ```bash
   systemctl --user status quay-pod quay-redis quay-app; podman ps --format '{{.Image}}'
   curl -s -o /dev/null -w '%{http_code}\n' --cacert /etc/pki/ocp-registry/ca-bundle.crt \
     https://registry.example.gc.ca:8443/health/instance  # 200
   ```

4. Repeat the [hardening](../02-high-side/mirror-registry.md#hardening) checks (an upgrade can
   rewrite `config.yaml`) and the [readiness checks](../02-high-side/registry-host.md#readiness-checks).

### Verification

`oc adm release info` [with the pull secret](../02-high-side/populate-registry.md#extract-the-installer) works; no new pull errors.

### Rollback

Restore `/data/quay/install`, `/data/quay/sqlite` and storage snapshot (services stopped); host: `dnf history undo <id>` or previous kernel.

### Records

Registry version before/after (PR to `versions.md`), `dnf history info`, hardening log, readiness output.
