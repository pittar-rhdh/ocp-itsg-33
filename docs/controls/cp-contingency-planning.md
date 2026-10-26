# CP — Contingency Planning

[← Back to control families](index.md) · [← Back to main](../index.md)

For a medium-availability system, the platform needs **resilience inside a site** (highly available
control plane, ingress, and workloads) and **recovery across sites** (backups, a rebuild from
GitOps, and an optional second cluster).

---

### CP-2 Contingency Plan

| Attribute | Value |
|---|---|
| **Responsibility** | Org, Platform, Tenant |
| **Inheritable by tenants** | Partial |

**Implementation guidance:** The platform contingency plan should cover:

| Scenario | Recovery approach | Target (example) |
|---|---|---|
| Loss of a single node | Automatic rescheduling; `MachineHealthCheck` replaces failed machines | Minutes |
| Loss of a control plane node | etcd quorum is kept with 2 of 3 nodes; replace the member following the documented etcd procedure | Hours |
| Loss of etcd quorum | Restore from etcd snapshot (`cluster-restore.sh`) | Hours |
| Corrupted or deleted namespace | OADP restore | RTO by application |
| Cluster loss | Rebuild from GitOps plus OADP restore, or fail over to a second cluster | RTO/RPO set by the departmental BIA |
| Site loss | Fail over to a cluster in the alternate site (DNS / GSLB) | RTO/RPO set by the departmental BIA |

Align RTO and RPO values with the departmental **Business Impact Analysis (BIA)**.

---

### CP-6 Alternate Storage Site / CP-9 Information System Backup

| Attribute | Value |
|---|---|
| **Responsibility** | Platform (platform state), Tenant (application data), Infrastructure (storage) |
| **OpenShift capabilities** | etcd backup, OADP (Velero + CSI snapshots / Kopia data mover), GitOps repository, ODF Regional-DR |
| **Automated check** | ACM policy (backup schedule present), OADP backup status |

**Implementation guidance:**

- **etcd backups:** take a snapshot at least daily, and before every upgrade. Store it off-cluster
  in encrypted storage. The snapshot holds encrypted secret data (see SC-28), but treat it as
  Protected B anyway.
- **Application backups:** use OADP schedules for namespaces and persistent volumes. Send them to
  object storage at an **alternate site** (CP-6). Encrypt backups in transit (TLS) and at rest
  (object storage encryption).
- **Configuration:** the GitOps repository is itself a backup of the cluster configuration. Mirror
  it to the alternate site.
- **CP-9(1) Testing for reliability and integrity:** test restores at least quarterly (see CP-4).

**Configuration example — etcd backup (manual or scheduled job):**

```bash
# Run on a control plane node through oc debug
oc debug node/<control-plane-node> -- chroot /host \
  /usr/local/bin/cluster-backup.sh /home/core/assets/backup
# Copy the snapshot and static pod resources to off-cluster encrypted storage
```

**Configuration example — OADP schedule:**

```yaml
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: itsg33-dpa
  namespace: openshift-adp
spec:
  configuration:
    velero:
      defaultPlugins: [openshift, aws, csi]
    nodeAgent:
      enable: true
      uploaderType: kopia
  backupLocations:
    - velero:
        provider: aws                    # S3-compatible object storage at the alternate site
        default: true
        credential:
          name: cloud-credentials
          key: cloud
        objectStorage:
          bucket: ocp-prod-backups
          prefix: velero
        config:
          region: ca-central-1
          s3Url: https://s3.alt-site.example.gc.ca
          s3ForcePathStyle: "true"
---
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: tenant-daily
  namespace: openshift-adp
spec:
  schedule: "0 2 * * *"
  template:
    labelSelector:
      matchLabels:
        itsg33/backup: "daily"
    snapshotMoveData: true                # Copy snapshot data off-cluster
    ttl: 720h0m0s                         # 30 days; align with the departmental retention policy
```

**Evidence:**

```bash
oc get schedules.velero.io -n openshift-adp
oc get backups.velero.io -n openshift-adp \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,COMPLETED:.status.completionTimestamp
```

Also collect the etcd backup job logs and the off-site storage listing.

---

### CP-4 Contingency Plan Testing

**Implementation guidance:**

- Hold a restore exercise at least once a year (quarterly for critical applications).
- Rebuild a non-production cluster from GitOps plus OADP.
- Test an etcd restore in a lab cluster.
- Record the measured RTO and RPO against the targets.

**Evidence:** test plan, test results, lessons learned.

---

### CP-7 Alternate Processing Site / CP-10 Information System Recovery and Reconstitution

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Infrastructure |
| **OpenShift capabilities** | ACM multi-cluster management, GitOps (`ApplicationSet`), ODF Regional-DR / Metro-DR, global load balancing |

**Implementation guidance:**

- Keep a **second cluster** at the alternate site. Its configuration is managed from the same Git
  repository through ACM or GitOps `ApplicationSets`.
- For stateful applications, use OpenShift Data Foundation **Regional-DR** (asynchronous) or
  **Metro-DR** (synchronous). Or use replication at the database layer.
- **CP-10(2) Transaction recovery:** handled at the database or application layer (Tenant).
- After recovery, re-run Compliance Operator scans to confirm the security configuration was
  restored before the cluster goes back into service.

---

### CP-8 Telecommunications Services

**Implementation guidance:** This is an Infrastructure and Org control. Make sure the alternate site
has its own network paths to the IdP, SIEM, and registry. Otherwise a single network failure can
block authentication, logging, or image pulls.
