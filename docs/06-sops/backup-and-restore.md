# Backup and Restore

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

What must survive loss of the cluster or the registry host: etcd, tenant namespaces (OADP), the mirror registry and
oc-mirror state, and Git plus the secrets kept outside it. Recovery targets are in the
[CP guidance](../04-itsg33-configuration/controls/cp-contingency-planning.md).

## etcd backup

| | |
|---|---|
| **Purpose** | Consistent etcd snapshot for restore after quorum loss or a destructive change (OADP does not cover etcd or platform operators) |
| **When** | Daily, off-peak (high I/O); before every upgrade or control plane change |
| **Roles** | Performs: platform operator (`ocp-platform-admins`). Approves: none daily; change ticket for pre-upgrade. Informed: backup custodian |
| **Prerequisites** | IdP login with cluster-admin. Cluster older than 24 hours (earlier backups hold certificates that expire at first rotation). Backup encryption public key on the admin host, private key in the vault |
| **Controls** | CP-9, CP-9(1), CP-6, SC-28, SC-12 |

### Procedure

1. On **one** control plane node only (no proxy variables; the cluster has no proxy), run the backup, copy both
   files off with checksums, and clean the node:

   ```bash
   CP=$(oc get nodes -l node-role.kubernetes.io/master -o name | head -1)
   oc get clusterversion version -o jsonpath='{.status.desired.version}{"\n"}'   # record it
   oc debug --as-root "${CP}" -- chroot /host /usr/local/bin/cluster-backup.sh /home/core/assets/backup
   # Expect: "snapshot db and kube resources are successfully saved to /home/core/assets/backup"
   STAMP=$(date -u +%Y%m%dT%H%M%SZ); umask 077; mkdir -p ~/etcd-backup/"${STAMP}"; cd ~/etcd-backup/"${STAMP}"
   oc debug --quiet "${CP}" -- chroot /host sha256sum /home/core/assets/backup/* > node.sha256
   oc debug --quiet "${CP}" -- chroot /host tar -C /home/core/assets/backup -cf - . > backup.tar
   tar -xf backup.tar && rm backup.tar
   sed 's#/home/core/assets/backup/##' node.sha256 | sha256sum -c -     # both files: OK
   oc debug --quiet "${CP}" -- chroot /host rm -rf /home/core/assets/backup
   ```

2. Encrypt and store the two files **in different locations**: `static_kuberesources_*.tar.gz` holds the etcd
   encryption keys, and Red Hat says to keep it apart from the snapshot (a restore needs both).

   ```bash
   for f in snapshot_*.db static_kuberesources_*.tar.gz; do
     gpg --encrypt --recipient '<backup-key-fingerprint>' --output "${f}.gpg" "${f}"
   done
   sha256sum *.gpg > SHA256SUMS; shred -u snapshot_*.db static_kuberesources_*.tar.gz
   ```

   **Handling:** etcd encryption covers only resource *values*, not names or namespaces. Treat both files as Protected B.

### Verification

Script output and `sha256sum -c` are `OK`; both encrypted files are stored with the recorded checksums;
`oc debug --quiet "${CP}" -- chroot /host ls /home/core/assets` shows no backup.

### Rollback

Nothing to roll back. On failure, check `oc get etcd cluster -o yaml` and `oc get pods -n openshift-etcd`, then retry on another node.

### Records

Backup log: date, cluster version (a restore needs the **same z-stream**), node, file names, SHA-256 of encrypted
files, both locations, operator. Keep the pre-upgrade backup while that version could still be rolled back to.

## etcd restore

| | |
|---|---|
| **Purpose** | Restore etcd after quorum loss or a destructive change. **Last resort**: it takes the whole cluster back in time. If the API server answers, don't restore |
| **When** | Declared incident only |
| **Roles** | Performs: two platform operators. Approves: system owner (emergency change). Informed: SOC, application owners |
| **Prerequisites** | Restore decision recorded. Break-glass kubeconfig ([Break-glass](access-management.md#break-glass-use-and-review)) and `core` SSH key from the vault. A backup **from the current z-stream**, decrypted, both files in one directory |
| **Controls** | CP-10, CP-4, IR-4 |

### Procedure

Follow Red Hat's procedure exactly: OpenShift 4.22 *Backup and restore* → "Disaster recovery". Overview:

1. **Quorum lost, one member healthy:** `quorum-restore.sh` on a recovery node (no backup needed), then
   [replace the failed control plane nodes](node-management.md#replace-a-failed-control-plane-node).
2. **Restore to an earlier state:** SSH to every control plane node first, `disable-etcd.sh` on each, copy the
   backup to `/home/core/` on the recovery node, run `cluster-restore.sh`, then the remaining Red Hat steps.
3. Fix persistent-volume state that no longer matches the snapshot (Red Hat lists the cases).

### Verification

Cluster operators available, nodes Ready, etcd pods running, Argo CD applications `Synced`, and a fresh Compliance
Operator scan before returning to service.

### Rollback

None. Take an etcd backup of the restored state as soon as it is stable.

### Records

Incident record, decision, backup used (names, checksums), timeline, measured RTO and RPO.

## OADP backup check and quarterly restore test

| | |
|---|---|
| **Purpose** | Confirm `tenant-daily` completed; prove a restore works. Backups go to departmental S3 (AD-14), kept 30 days. DPA and `Schedule` are in `04-gitops/components/oadp/oadp.yaml` |
| **When** | Daily check; quarterly restore test |
| **Roles** | Performs: platform operator. Witness (quarterly): test application owner. Informed: system owner |
| **Prerequisites** | Test application labelled `itsg33/backup=daily`, with a persistent volume and no external side effects when started |
| **Controls** | CP-9, CP-9(1), CP-4, CP-10 |

### Procedure

1. Daily: `PartiallyFailed` or `Failed` opens an incident (`oc describe backups.velero.io <name> -n openshift-adp`).

   ```bash
   oc get backupstoragelocations.velero.io -n openshift-adp          # PHASE Available
   oc get backups.velero.io -n openshift-adp -l velero.io/schedule-name=tenant-daily --sort-by=.metadata.creationTimestamp \
     -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,ERRORS:.status.errors,WARNINGS:.status.warnings | tail -3
   ```

2. Quarterly: restore the latest backup into a new namespace (routes excluded; their hosts are taken), have the
   owner check a known record, then delete the `restore-test-<date>` namespace and Restore.

   ```bash
   B=$(oc get backups.velero.io -n openshift-adp -l velero.io/schedule-name=tenant-daily \
     --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d/ -f2)
   oc create -f - <<EOF
   apiVersion: velero.io/v1
   kind: Restore
   metadata: {name: restore-test-$(date -u +%Y%m%d), namespace: openshift-adp}
   spec:
     backupName: ${B}
     restorePVs: true
     includedNamespaces: [<test-app-namespace>]
     namespaceMapping: {<test-app-namespace>: restore-test-$(date -u +%Y%m%d)}
     excludedResources: [routes.route.openshift.io]
   EOF
   oc get restores.velero.io -n openshift-adp -w      # wait for PHASE Completed
   ```

### Verification

Restore `Completed` with no errors, PVCs `Bound`, pods `Running`, owner confirms the data.

### Rollback

Delete the test namespace (`namespaceMapping` never writes to the source namespace).

### Records

Daily: backup name and phase (or ticket). Quarterly: backup/restore names, item counts, owner confirmation, restore time, lessons learned.

## Registry host and oc-mirror state

| | |
|---|---|
| **Purpose** | Back up what is needed to keep serving images and importing deltas: registry config, database, storage, and oc-mirror cache (both sides) |
| **When** | Weekly, and after every import or mirror run |
| **Roles** | Performs: registry administrator (`quay` account owner). Informed: backup custodian |
| **Prerequisites** | Departmental backup target; 15-minute window without imports or scaling (pulls fail while `quay-app` is stopped) |
| **Controls** | CP-9, CP-10, CM-11, SI-7 |

### Procedure

1. High side: follow [Mirror registry → Backup and restore](../02-high-side/mirror-registry.md#backup-and-restore)
   (full list in [Storage layout](../02-high-side/registry-host.md#storage-layout)).
2. High side, after every import: back up `/data/ocp/oc-mirror-cache`, `/data/ocp/cluster-resources`,
   `/data/ocp/installer`, and `/data/ocp/import-log.md` ([Keep the workspace and cache](../02-high-side/populate-registry.md#keep-the-workspace-and-cache)).
3. Low side, after every mirror run: see [What to keep on the low side](../01-mirroring/packaging-and-transfer.md#what-to-keep-on-the-low-side).
4. Record checksums: `sha256sum <archive> >> /data/ocp/backup-SHA256SUMS`.

### Verification

`oc image info -a ~/.config/ocp-registry/cluster-pull-secret.json registry.example.gc.ca:8443/mirror/openshift/release-images@sha256:<release-digest>`
succeeds. Annually, restore onto a scratch host and pull one image.

### Rollback

Restart `quay-app` if interrupted. If the registry is lost and unrecoverable, rebuild and re-import ([mirror registry](../02-high-side/mirror-registry.md)).

### Records

Backup job output, checksums, annual restore test.

## Git and Argo CD

| | |
|---|---|
| **Purpose** | Git is the configuration (AD-12) and Argo CD is rebuilt from it; back up what Git does not hold |
| **When** | On every change to an out-of-Git secret |
| **Roles** | Performs: platform operator. Git server backup: departmental Git team |
| **Prerequisites** | Git server backup in the shared-responsibility agreement; low side keeps the reviewed origin; each transfer carries a bundle |
| **Controls** | CP-9, CM-2, CM-3, IA-5 |

### Procedure

1. Confirm the Git server backup includes the repository and its `transfer/<ID>` tags.
2. Keep the [secrets kept outside Git](../04-itsg33-configuration/platform-configuration.md#secrets-kept-outside-git),
   the Argo CD repository token and Git CA, and the RHACS API token in the vault; update on change.
3. To rebuild: restore the repository (or [publish the latest transfer bundle](../02-high-side/populate-registry.md#publish-the-repository)),
   repeat [GitOps bootstrap](../04-itsg33-configuration/gitops-bootstrap.md), and recreate secrets from the vault.

### Verification

Every application `Synced` and `Healthy` in `oc get applications.argoproj.io -n openshift-gitops`;
[ACM policies](../04-itsg33-configuration/acm-governance.md) compliant.

### Rollback

Not applicable.

### Records

Git server backup report reference; vault entry list (names and dates, never values).
