# Backup and Restore

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Five SOPs cover what must survive the loss of the cluster or the registry host: etcd, tenant
namespaces (OADP), the mirror registry and oc-mirror state, and the configuration in Git. The
recovery targets come from the [CP guidance](../04-itsg33-configuration/controls/cp-contingency-planning.md).

| What | Mechanism | Frequency | Stored |
|---|---|---|---|
| etcd and static pod resources | `cluster-backup.sh` | Daily, and before every upgrade or control plane change | Off-cluster, encrypted, two separate locations |
| Tenant namespaces and volumes | OADP `Schedule` `tenant-daily` | Nightly (02:00), kept 30 days | Departmental S3 (AD-14) |
| Mirror registry and oc-mirror cache | File and storage snapshots on the registry host | Weekly, and after every import | Departmental backup service |
| Cluster configuration | Git (AD-12) | Every merge | Departmental Git, plus the low-side origin |
| Secrets kept outside Git | Input files | On every change | Departmental vault |

## etcd backup

### Purpose and scope

Take a consistent etcd snapshot so the control plane can be restored after quorum loss or a
destructive change. OADP does not back up etcd or the platform operators.

### Roles

| Role | Who |
|---|---|
| Performs | Platform operator (`ocp-platform-admins`) |
| Approves | None for the daily run; the change ticket covers pre-upgrade backups |
| Informed | Backup custodian |

### Prerequisites

- An IdP login with cluster-admin. The cluster is more than 24 hours old: Red Hat warns that a
  backup taken before the first certificate rotation contains expired certificates.
- A departmental backup encryption key (public part on the admin host, private part in the vault).
- Off-peak window: the snapshot has a high I/O cost.

### Procedure

1. Pick **one** control plane node. Red Hat: run the script once, on one node, not on each.

   ```bash
   CP=$(oc get nodes -l node-role.kubernetes.io/master -o name | head -1)
   oc get clusterversion version -o jsonpath='{.status.desired.version}{"\n"}'   # record it
   ```

2. Run the backup script (Red Hat's procedure; the cluster has no proxy, so no proxy variables):

   ```bash
   oc debug --as-root "${CP}" -- chroot /host /usr/local/bin/cluster-backup.sh /home/core/assets/backup
   # Expect: "snapshot db and kube resources are successfully saved to /home/core/assets/backup"
   ```

3. Copy both files off the node, check them, and remove them from the node. The copy streams a
   tar archive through the debug pod; the checksums catch a corrupted stream.

   ```bash
   STAMP=$(date -u +%Y%m%dT%H%M%SZ); umask 077; mkdir -p ~/etcd-backup/"${STAMP}"; cd ~/etcd-backup/"${STAMP}"
   oc debug --quiet "${CP}" -- chroot /host sha256sum /home/core/assets/backup/* > node.sha256
   oc debug --quiet "${CP}" -- chroot /host tar -C /home/core/assets/backup -cf - . > backup.tar
   tar -xf backup.tar && rm backup.tar
   sed 's#/home/core/assets/backup/##' node.sha256 | sha256sum -c -     # both files: OK
   oc debug --quiet "${CP}" -- chroot /host rm -rf /home/core/assets/backup
   ```

4. Encrypt each file for the backup key and store them **in two different locations**. With etcd
   encryption on, `static_kuberesources_*.tar.gz` contains the etcd encryption keys; Red Hat says
   to store it separately from the snapshot (both are needed for a restore).

   ```bash
   for f in snapshot_*.db static_kuberesources_*.tar.gz; do
     gpg --encrypt --recipient '<backup-key-fingerprint>' --output "${f}.gpg" "${f}"
   done
   sha256sum *.gpg > SHA256SUMS
   shred -u snapshot_*.db static_kuberesources_*.tar.gz
   # Copy snapshot_*.gpg and static_kuberesources_*.gpg to their two approved locations.
   ```

### Verification

- The script output and both `sha256sum -c` results are `OK`.
- The off-cluster copies list both encrypted files with the recorded checksums.
- No backup is left on the node: `oc debug --quiet "${CP}" -- chroot /host ls /home/core/assets`.

### Rollback

Nothing to roll back. If the script fails, check `oc get etcd cluster -o yaml` conditions and
`oc get pods -n openshift-etcd` before retrying on another control plane node.

### Records and evidence

Backup log entry: date, cluster version (a restore needs a backup **from the same z-stream**), node,
file names, SHA-256 of the encrypted files, both storage locations, operator. Keep one backup taken
immediately before each upgrade for as long as that version could be rolled back to.

### Related controls

CP-9, CP-9(1), CP-6, SC-28, SC-12.

> **Handling.** etcd encryption (`aesgcm`) encrypts the *values* of the encrypted resource types
> only. Resource types, namespaces, and object names stay in clear text, and other resource types
> are not encrypted. Treat both files as Protected B and the key file as a secret key.

## etcd restore

### Purpose and scope

Restore etcd after loss of quorum or a destructive change. This is a **last resort**: Red Hat warns
that restoring takes the whole cluster back in time and can disrupt operators, persistent volumes,
and nodes. If the API server still answers, etcd is available: don't restore.

### Roles

Performs: two platform operators. Approves: system owner (emergency change). Informed: SOC,
application owners.

### Prerequisites

- The incident is declared and the decision to restore is recorded.
- The break-glass installer kubeconfig (certificate-based; see
  [Break-glass](access-management.md#break-glass-use-and-review)) and the `core` SSH key from the vault.
- A backup **from the current z-stream**, decrypted on the admin host, with both files in one
  directory named `snapshot_<timestamp>.db` and `static_kuberesources_<timestamp>.tar.gz`.

### Procedure

Follow Red Hat's procedure exactly: OpenShift 4.22 *Backup and restore*, "Disaster recovery". In
outline:

1. **Quorum lost but one member's data is good:** on a recovery control plane node,
   `sudo -E /usr/local/bin/quorum-restore.sh` (no backup needed). For bare-metal IPI, failed
   control plane nodes are then replaced as in
   [Replace a failed control plane node](node-management.md#replace-a-failed-control-plane-node).
2. **Restore to an earlier state:** open an SSH session to every control plane node first (the API
   goes away), run `sudo -E /usr/local/bin/disable-etcd.sh` on each, copy the backup directory to
   `/home/core/` on the recovery node, run `sudo -E /usr/local/bin/cluster-restore.sh
   /home/core/<backup-dir>`, then follow the quorum-guard and `oc adm wait-for-stable-cluster`
   steps in the Red Hat procedure.
3. Fix persistent-volume state that the old snapshot no longer matches (Red Hat lists the cases).

### Verification

`oc get clusteroperators` all available, `oc get nodes` Ready, `oc get pods -n openshift-etcd`,
Argo CD applications `Synced`, and a fresh Compliance Operator scan before the cluster returns to
service (CP-10).

### Rollback

None: a restore cannot be undone. Take an etcd backup of the restored state as soon as it is
stable.

### Records and evidence

Incident record, decision, backup used (file names, checksums), timeline, measured RTO and RPO.

### Related controls

CP-10, CP-4, IR-4.

## OADP backup check and quarterly restore test

### Purpose and scope

Confirm every night that `tenant-daily` produced a complete backup, and prove once a quarter that a
backup can be restored (CP-9(1), CP-4). The DPA `itsg33-dpa` and the `Schedule` are in Git
(`04-gitops/components/oadp/oadp.yaml`).

### Roles

Performs: platform operator. Witness for the quarterly test: application owner of the test
namespace. Informed: system owner.

### Prerequisites

A test application whose namespace is labelled `itsg33/backup=daily` and that has a persistent
volume and no side effects on external systems when started (no live database connections or
outbound jobs).

### Procedure

1. Daily check:

   ```bash
   oc get backupstoragelocations.velero.io -n openshift-adp          # PHASE Available
   oc get backups.velero.io -n openshift-adp -l velero.io/schedule-name=tenant-daily \
     --sort-by=.metadata.creationTimestamp \
     -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,ERRORS:.status.errors,WARNINGS:.status.warnings | tail -3
   ```

   `PartiallyFailed` or `Failed` is an incident ticket: `oc describe backups.velero.io <name> -n openshift-adp`.

2. Quarterly test: restore the latest backup into a new namespace. Routes are excluded because
   their host names are already claimed by the source namespace.

   ```bash
   B=$(oc get backups.velero.io -n openshift-adp -l velero.io/schedule-name=tenant-daily \
     --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d/ -f2)
   oc create -f - <<EOF
   apiVersion: velero.io/v1
   kind: Restore
   metadata:
     name: restore-test-$(date -u +%Y%m%d)
     namespace: openshift-adp
   spec:
     backupName: ${B}
     restorePVs: true
     includedNamespaces: [<test-app-namespace>]
     namespaceMapping:
       <test-app-namespace>: restore-test-$(date -u +%Y%m%d)
     excludedResources: [routes.route.openshift.io]
   EOF
   oc get restores.velero.io -n openshift-adp -w      # wait for PHASE Completed
   ```

3. Check the restored data with the application owner (for example, a known record), then
   clean up: `oc delete namespace restore-test-<date>` and
   `oc delete restores.velero.io restore-test-<date> -n openshift-adp`.

### Verification

Restore phase `Completed` (`oc describe restores.velero.io <name> -n openshift-adp` shows no
errors), PVCs `Bound`, pods `Running`, and the application owner confirms the data.

### Rollback

Delete the test namespace. A restore never writes into the source namespace when
`namespaceMapping` is set.

### Records and evidence

Daily: backup name and phase (or the ticket). Quarterly: backup and restore names, timestamps,
item counts, the owner's confirmation, measured restore time, lessons learned.

### Related controls

CP-9, CP-9(1), CP-4, CP-10.

## Registry host and oc-mirror state

### Purpose and scope

Back up what is needed to keep serving images and to keep importing deltas: the registry
configuration, database and storage, and the oc-mirror cache, on the high side and the low side.

### Roles

Performs: registry administrator (the `quay` service account owner). Informed: backup custodian.

### Prerequisites

A departmental backup target and a 15-minute window without imports or cluster scaling (pulls fail
while `quay-app` is stopped).

### Procedure

1. High side, as the service account: follow
   [Mirror registry → Backup and restore](../02-high-side/mirror-registry.md#backup-and-restore)
   (stop `quay-app`, copy `/data/quay/install` and `/data/quay/sqlite`, snapshot
   `/data/quay/storage` at the same time, start `quay-app`). The full list is in
   [Registry host → Storage layout](../02-high-side/registry-host.md#storage-layout).
2. High side, after every import: back up `/data/ocp/oc-mirror-cache` (Red Hat requirement),
   `/data/ocp/cluster-resources`, `/data/ocp/installer`, and `/data/ocp/import-log.md`. Leave the
   workspace in place ([Keep the workspace and cache](../02-high-side/populate-registry.md#keep-the-workspace-and-cache)).
3. Low side, after every successful mirror run: back up the oc-mirror cache and keep
   `working-dir/` ([What to keep on the low side](../01-mirroring/packaging-and-transfer.md#what-to-keep-on-the-low-side)).
4. Record checksums of each archive: `sha256sum <archive> >> /data/ocp/backup-SHA256SUMS`.

### Verification

`quay-app` is running and serves the release with the pull-only credentials:

```bash
oc image info -a ~/.config/ocp-registry/cluster-pull-secret.json \
  registry.example.gc.ca:8443/mirror/openshift/release-images@sha256:<release-digest>
```

Once a year, restore the registry backup on a scratch host and pull one image.

### Rollback

Start `quay-app` again if the backup is interrupted. If the registry is lost and the backup
can't be restored, rebuild and re-import as described on the mirror registry page.

### Records and evidence

Backup job output, checksums, the annual restore test.

### Related controls

CP-9, CP-10, CM-11, SI-7.

## Git and Argo CD

### Purpose and scope

The cluster configuration is the Git repository (AD-12). Argo CD holds no state that must be backed
up; it is rebuilt from Git. What Git does **not** hold must be backed up separately.

### Roles

Performs: platform operator. The departmental Git team backs up the Git server.

### Prerequisites

The Git server backup is confirmed in the shared-responsibility agreement; the low side keeps the
reviewed origin of the repository, and each transfer carries a bundle.

### Procedure

1. Confirm the departmental Git server backup includes the repository and its tags
   (`transfer/<ID>`).
2. Keep the inputs of [Secrets kept outside Git](../04-itsg33-configuration/platform-configuration.md#secrets-kept-outside-git),
   the Argo CD repository token and Git CA, and the RHACS API token in the departmental vault.
   Update the vault copy whenever one of them changes.
3. To rebuild: restore or recreate the Git repository (from backup, or by publishing the latest
   transfer bundle as in [Publish the repository](../02-high-side/populate-registry.md#publish-the-repository)),
   then repeat [GitOps bootstrap](../04-itsg33-configuration/gitops-bootstrap.md) and recreate the
   secrets from the vault.

### Verification

`oc get applications.argoproj.io -n openshift-gitops`: every application `Synced` and `Healthy`;
ACM policies compliant ([ACM governance](../04-itsg33-configuration/acm-governance.md)).

### Rollback

Not applicable.

### Records and evidence

Git server backup report reference; vault entry list (names and dates, never values).

### Related controls

CP-9, CM-2, CM-3, IA-5.
