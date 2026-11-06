# Upgrades

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

These SOPs update the cluster, the operators, and the registry host. Every upgrade uses content
that a [content import](content-import.md) has already made available. Commands follow the
OpenShift 4.22 *Updating clusters* guide and *Disconnected environments*, chapter 12.

For every SOP on this page:

- Use `oc` **for the target version**, from the transfer (`export PATH=/data/ocp/tools/<target>/bin:$PATH`).
  Red Hat strongly discourages updating with an older `oc`.
- Log in through the IdP as a member of `ocp-platform-admins`. `oc adm upgrade recommend` checks
  firing alerts only with a token-based login. With the break-glass kubeconfig (a client
  certificate), it skips those checks.

## One-time setup: OpenShift Update Service

### Purpose and scope

Run OpenShift Update Service (OSUS) from mirrored graph data, so that the cluster offers
recommended update paths (AD-19). Do it once, before the first upgrade.

### Roles

The platform engineer performs it. A second reviewer reviews the pull request. The change manager
approves.

### Prerequisites

The `cincinnati-operator` install plan is approved
([Operators](../04-itsg33-configuration/operators.md#approving-install-plans)), and
`/data/ocp/cluster-resources/current/updateService.yaml` exists (ISC `graph: true`).

### Procedure

1. OSUS must trust the mirror registry. Red Hat requires the CA under the key
   `updateservice-registry` in the ConfigMap referenced by `Image/cluster`
   `spec.additionalTrustedCA`. Git owns `Image/cluster`, so add both through a pull request to
   `04-gitops/components/image-policy/`:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: mirror-registry-ca
     namespace: openshift-config
     annotations:
       itsg33/controls: "SC-8,SI-2"
   data:
     updateservice-registry: |
       -----BEGIN CERTIFICATE-----
       <departmental root CA>
       -----END CERTIFICATE-----
   # and in image.yaml:  spec.additionalTrustedCA.name: mirror-registry-ca
   ```

2. Apply the generated `UpdateService`. It isn't in Git, because its graph data image changes with
   every import ([Cluster resources](../02-high-side/populate-registry.md#cluster-resources)):

   ```bash
   oc apply -n openshift-update-service -f /data/ocp/cluster-resources/current/updateService.yaml
   NAME=$(oc get updateservice -n openshift-update-service -o jsonpath='{.items[0].metadata.name}')
   URI="$(oc get updateservice "$NAME" -n openshift-update-service \
     -o jsonpath='{.status.policyEngineURI}')/api/upgrades_info/v1/graph"   # repeat until https://...
   ```

3. Point the Cluster Version Operator at it. The CVO must trust the route's certificate (the
   default ingress certificate), so its issuing CA must be in the
   [cluster trust bundle](certificate-rotation.md#update-the-cluster-trust-bundle):

   ```bash
   oc patch clusterversion version --type merge -p "{\"spec\":{\"upstream\":\"${URI}\"}}"
   ```

### Verification

```bash
curl -fsS --cacert /etc/pki/ocp-registry/ca-bundle.crt -H 'Accept: application/json' \
  "${URI}?channel=stable-4.22" | jq -r '.nodes[].version' | sort -V | tail -3
oc adm upgrade recommend          # shows the local upstream and the mirrored versions
```

### Rollback

Remove `spec.upstream` from `clusterversion/version` and use the explicit-digest method in the
[z-stream SOP](#z-stream-upgrade).

### Records and evidence

The pull request, the `upstream` value, and the verification output, in the change ticket.

### Related controls

SI-2, CM-3, SC-8.

## Z-stream upgrade

### Purpose and scope

Update within 4.22 (for example 4.22.18 → 4.22.z) for security and bug fixes (SI-2), with OSUS
or, without OSUS, to an explicit release digest.

### Roles

The platform engineer performs it. The platform lead approves the target version. The change
manager approves the window. The DSO and the application teams are informed.

### Prerequisites

- The target release and its signature were imported ([Content import](content-import.md)).
- A maintenance window. Nodes drain and reboot one at a time.
- An etcd backup from **this** z-stream, taken in the window and copied off the node
  ([Backup and restore](backup-and-restore.md)). Red Hat 4.22: `oc debug --as-root node/<control-plane-node>`,
  `chroot /host`, `/usr/local/bin/cluster-backup.sh /home/core/assets/backup`.

### Procedure

1. Run the pre-checks and record the output:

   ```bash
   oc get clusterversion
   oc get clusteroperators            # Available=True, Progressing=False, Degraded=False
   oc get mcp                         # UPDATED=True, DEGRADED=False, none paused
   oc get nodes                       # all Ready
   oc adm upgrade recommend           # no firing critical alerts; target listed
   oc get clusterversion version \
     -o jsonpath='{.status.conditions[?(@.type=="Upgradeable")].message}{"\n"}'
   oc get pdb -A                      # no ALLOWED DISRUPTIONS 0 that would block a drain
   oc get applications.argoproj.io -n openshift-gitops   # Synced/Healthy baseline
   oc get machinehealthcheck -n openshift-machine-api
   ```

   Pause each `MachineHealthCheck`, if there are any:
   `oc -n openshift-machine-api annotate mhc <name> cluster.x-k8s.io/paused=""`.

2. **With OSUS:** `oc adm upgrade --to=4.22.<z>`.

   **Without OSUS:** read the digest from the mirror, confirm that its signature is on the cluster,
   and update to the canonical reference (the IDMS resolves it to the mirror):

   ```bash
   V=4.22.<z>; PS=~/.config/ocp-registry/cluster-pull-secret.json; CA=/etc/pki/ocp-registry/ca-bundle.crt
   DIGEST=$(oc adm release info -a "$PS" --certificate-authority "$CA" -o json \
     registry.example.gc.ca:8443/mirror/openshift/release-images:"$V"-x86_64 | jq -r .digest)
   oc get configmap -n openshift-config-managed -o json \
     | jq -r '.items[].binaryData // {} | keys[]' | grep "sha256-${DIGEST#sha256:}"   # must print a key
   oc adm upgrade --allow-explicit-upgrade --to-image quay.io/openshift-release-dev/ocp-release@"$DIGEST"
   ```

   Never use `--force`: it bypasses release verification.

3. Monitor with `watch oc adm upgrade status`, and start no other change meanwhile. If an operator
   stays degraded, see [Troubleshooting](troubleshooting.md).
4. Remove the pause from each `MachineHealthCheck` (`cluster.x-k8s.io/paused-`).

### Verification

```bash
oc adm upgrade                                         # Cluster version is 4.22.<z>
oc get clusterversion version -o jsonpath='{.status.desired.image}{"\n"}'   # the target digest
oc get clusteroperators; oc get mcp; oc get nodes
oc get applications.argoproj.io -n openshift-gitops    # Synced/Healthy
oc get policies -n local-cluster                       # Compliant
```

Then repeat the node checks (FIPS, LUKS, chrony) from
[Verify](../03-cluster-install/run-install.md#verify). In the next import, raise `minVersion` to
the new version ([Scheduled import procedure](../01-mirroring/ongoing-imports.md#scheduled-import-procedure)).

### Rollback

Red Hat doesn't support rolling a cluster back to an earlier version. If the update doesn't
complete, open a support case with `must-gather` ([Troubleshooting](troubleshooting.md)).
Restoring etcd from the pre-update backup is a last resort, and only with Red Hat's guidance.

### Records and evidence

The pre-check and verification output, the target version and digest, the etcd backup reference,
and the start and end times, in the change ticket. A pull request updates
`docs/reference/versions.md`.

### Related controls

SI-2, CM-3, CM-4, CP-9, SI-7.

## Control Plane Only (EUS-to-EUS) upgrade

### Purpose and scope

Move from 4.22 to the next even-numbered (EUS) release, through the odd-numbered release between
them, with one worker reboot. Red Hat now calls this a **Control Plane Only** update (formerly
EUS-to-EUS). Below, `<y+1>` is the intermediate release and `<y+2>` the target. Red Hat
documentation for OpenShift 5.0 already exists: confirm in the update graph and the release notes
which release follows 4.22, and that this path is offered.

### Roles

As for the z-stream. The DSO also approves, because the platform baseline changes (CM-2).

### Prerequisites

- The path is in the `eus-<y+2>` channel. Red Hat says this takes 45–90 days after GA.
- Release notes for `<y+1>` and `<y+2>` reviewed (API removals, admin acknowledgements).
- Every installed operator has a version that supports both `<y+1>` and `<y+2>` (Red Hat's
  *Operator Update Information Checker*, reviewed on the low side).
- **Both** releases with their signatures, `oc` for both, and the target operator catalog were
  imported. In the ISC this is, for example, a channel `eus-<y+2>` with `minVersion` at the
  installed version, `maxVersion` at the target, and `shortestPath: true`, plus
  `redhat-operator-index:v<y+2>`. Check the dry run's `mapping.txt` for the intermediate release.

### Procedure

1. Update operators to versions that are compatible with both releases
   ([Operator upgrade](#operator-upgrade-with-manual-install-plans)).
2. Check for use of APIs removed in the target, and give the admin acknowledgements that the
   `Upgradeable` message names:

   ```bash
   oc get apirequestcounts -o jsonpath='{range .items[?(@.status.removedInRelease!="")]}{.status.removedInRelease}{"\t"}{.metadata.name}{"\n"}{end}'
   oc -n openshift-config patch cm admin-acks --type=merge --patch '{"data":{"<ack-key>":"true"}}'
   ```

3. Run the [z-stream](#z-stream-upgrade) pre-checks, and take the etcd backup.
4. Set the channel, and pause every pool except `master` (the control plane pool can't be paused):

   ```bash
   oc adm upgrade channel eus-<y+2>
   oc patch mcp/worker --type merge --patch '{"spec":{"paused":true}}'
   ```

5. First hop, with `oc` for `<y+1>`: `oc adm upgrade --to=<y+1.z>` (or `--to-image` with the
   digest, as in the z-stream SOP). Wait until every cluster operator is healthy at `<y+1.z>`.
6. Update any operators that must move before the second hop. Take a new etcd backup (a restore
   needs a backup from the same z-stream).
7. Second hop, with `oc` for `<y+2>`: `oc adm upgrade --to=<y+2.z>`. Wait until it completes.
8. Unpause the workers. Red Hat warns that paused pools block later minor updates and some
   maintenance tasks:

   ```bash
   oc patch mcp/worker --type merge --patch '{"spec":{"paused":false}}'
   watch oc get mcp
   ```

9. Through a pull request, move the Subscriptions to the new CatalogSource name (for example
   `cs-redhat-operator-index-v<y+2>`) in `04-gitops/overlays/ocp1/operators/kustomization.yaml`,
   the MultiClusterHub annotation in `overlays/ocp1/config/kustomization.yaml`, and
   `04-gitops/bootstrap/kustomization.yaml`. Test the switch in a lab first. Remove the old
   catalog from the ISC once nothing uses it.

### Verification

As for the z-stream, plus: every node reports the new kubelet version (`oc get nodes`), no pool is
paused (`oc get mcp`), and every Subscription uses the new source
(`oc get sub -A -o custom-columns=NS:.metadata.namespace,SRC:.spec.source`).

### Rollback

Not supported (see the z-stream SOP). Red Hat notes that if problems appear at `<y+1>`, you might
have to unpause the workers and finish `<y+1>` before you move on.

### Records and evidence

The z-stream records for each hop, the admin acknowledgements, the API check, the operator
compatibility review, and the catalog-switch pull request.

### Related controls

CM-2, CM-3, CM-4, SI-2, CP-9, SA-22.

## Operator upgrade with manual install plans

### Purpose and scope

Update a layered operator within its channel, or move it to a new channel. Every Subscription uses
`installPlanApproval: Manual` (AD-22), so nothing changes until a person approves.

### Roles

The platform engineer performs it. A second reviewer reviews channel changes. The platform lead
approves the install plan under the change ticket.

### Prerequisites

The new version is in the mirrored catalog ([Content import](content-import.md)). Its release
notes and supported OpenShift versions have been reviewed.

### Procedure

1. **Channel change only:** in one pull request, change `spec.channel` in
   `04-gitops/components/operators/<package>/operator.yaml` and, if it isn't mirrored yet, the
   channel in `01-mirror/imageset-config.yaml`. Merge it, and let `itsg33-operators` sync
   ([Making a change](../04-itsg33-configuration/repository-layout.md#making-a-change)).
2. Compare the pending install plans' CSV names with the change ticket, and approve them as
   [Approving install plans](../04-itsg33-configuration/operators.md#approving-install-plans)
   describes.
3. Follow the [ordering constraints](../04-itsg33-configuration/operators.md#ordering-constraints):
   **Loki before Logging** (the same `stable-6.x` channel, changed in the same pull request;
   approve `loki-operator`, wait for `Succeeded`, then approve `cluster-logging`); cert-manager
   before External Secrets. ACM updates `multicluster-engine` itself.
4. If the operator is several versions behind, OLM steps along the update graph, and a new install
   plan can appear after each step. Review each one before you approve it.

### Verification

`oc get csv -n <namespace>` shows the new version with `PHASE Succeeded`. `oc get installplan -n <namespace>`
shows nothing unexpected pending. The operator's own resources are healthy (for example
`oc get lokistack -n openshift-logging`), `itsg33-config` is `Healthy`, and the related ACM policy
is `Compliant`.

### Rollback

OLM doesn't downgrade operators. Before approval, just delete the install plan. After a failed
update, see [Troubleshooting](troubleshooting.md) and open a support case. Restore data with
[Backup and restore](backup-and-restore.md).

### Records and evidence

The pull request, the install plan names, the CSV versions, and who approved them and when.

### Related controls

CM-3, CM-5, CM-11, SI-2.

## Mirror registry upgrade and registry host patching

### Purpose and scope

Install a new mirror registry version, or apply RHEL errata to the registry host. While the
registry is down, nodes can't pull images they don't already have. Don't overlap this work with a
cluster upgrade, node maintenance, or an import.

### Roles

The platform engineer performs it (as `quay` for the registry, with a named sudo account for the
OS). The change manager approves.

### Prerequisites

- For a registry upgrade: the new `mirror-registry-amd64.tar.gz` came in an accepted transfer.
- `/data/quay` was backed up with `quay-app` stopped
  ([Backup and restore](../02-high-side/mirror-registry.md#backup-and-restore)), and so was
  `/data/ocp`.
- For patching: RHEL errata are available from the departmental high-side content source.

### Procedure

1. **Registry:** run the new installer's `upgrade` command with the same hostname, paths, and
   certificate, as [Upgrades](../02-high-side/mirror-registry.md#upgrades) shows. Red Hat 4.22:
   from 2.0.11 on, `upgrade` keeps the existing hostname and paths. It can rotate the certificate
   with `--sslCert` and `--sslKey`, passed together.
2. **Host:** `sudo dnf upgrade --refresh`, then `sudo dnf needs-restarting -r || sudo systemctl reboot`.
3. After either one, as `quay`:

   ```bash
   systemctl --user status quay-pod quay-redis quay-app
   podman ps --format '{{.Image}}'                        # the expected Quay image
   curl -s -o /dev/null -w '%{http_code}\n' --cacert /etc/pki/ocp-registry/ca-bundle.crt \
     https://registry.example.gc.ca:8443/health/instance  # 200
   ```

4. Repeat the [hardening](../02-high-side/mirror-registry.md#hardening) checks (an upgrade can
   rewrite `config.yaml`) and the [readiness checks](../02-high-side/registry-host.md#readiness-checks).

### Verification

`oc adm release info` with the cluster pull secret, as in
[Extract the installer](../02-high-side/populate-registry.md#extract-the-installer), returns the
current release, and the cluster shows no new image pull errors.

### Rollback

Registry: stop the services, restore `/data/quay/install`, `/data/quay/sqlite`, and the storage
snapshot, then start the services. Host: `sudo dnf history undo <id>`, or boot the previous
kernel.

### Records and evidence

The registry version before and after (update `docs/reference/versions.md` through a pull
request), `dnf history info`, the hardening log entry, and the readiness output.

### Related controls

SI-2, CM-3, CM-6, MA-2, CP-9.
