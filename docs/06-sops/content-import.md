# Content Import

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

This page has three SOPs: the routine monthly import, the emergency CVE import, and the daily
RHACS vulnerability data import. They link to the Phase 1 and Phase 2 pages for the detailed
commands. The steps that only happen on a running cluster are written out here: applying the
regenerated cluster resources and checking that the catalogs updated.

Conventions: transfer `T-20261106-01` follows `T-20261002-01`; registry
`registry.example.gc.ca:8443`, organization `mirror`; cluster `ocp1.example.gc.ca`; catalog source
`cs-redhat-operator-index-v4-22`.

## Monthly content import

### Purpose and scope

Bring a new OpenShift z-stream, operator updates, and refreshed additional images to the high
side, and make them available to the cluster. This SOP ends when the content is **available**. It
doesn't install anything. Cluster and operator updates follow in [Upgrades](upgrades.md).

### Roles

| Role | Who |
|---|---|
| Performs | Platform engineer: low side, then high side |
| Reviews | Second reviewer: the ISC pull request and the cluster-resource diff |
| Approves | Change manager (routine change); content-transfer officer (transfer record) |
| Informed | DSO; application teams (new operator versions available) |

### Prerequisites

- Approved routine change ticket that names the transfer ID.
- The previous content transfer was accepted and imported (check the
  [import log](../02-high-side/accept-transfer.md#the-import-log)).
- The low-side oc-mirror cache and `working-dir` are intact
  ([Incremental runs](../01-mirroring/mirror-to-disk.md#incremental-runs)), and so are the
  high-side ones ([Keep the workspace and cache](../02-high-side/populate-registry.md#keep-the-workspace-and-cache)).
- Cluster access as a member of `ocp-platform-admins` through the IdP, not the break-glass
  kubeconfig.

### Procedure

**Low side**

1. Review the release notes and errata for the candidate versions, and list them
   ([Choosing versions](../01-mirroring/imageset-configuration.md#choosing-versions)).
2. On a branch, edit `01-mirror/imageset-config.yaml` and `docs/reference/versions.md` as the
   [scheduled import procedure](../01-mirroring/ongoing-imports.md#scheduled-import-procedure)
   describes:
   - Platform: raise `maxVersion` to the new z-stream. Keep `minVersion` at the version that's
     installed now.
   - Operators: set `minVersion` to the installed version, so the update path stays complete.
   - If an operator channel changes, change the Subscription in
     `04-gitops/components/operators/<package>/operator.yaml` in the **same** pull request.
3. Run a [dry run](../01-mirroring/mirror-to-disk.md#dry-run). Attach the catalog report and the
   size of `mapping.txt` to the pull request. Merge after review
   ([review checklist](../01-mirroring/imageset-configuration.md#review-checklist-for-the-pull-request)).
4. From a clean checkout of the merged commit, run
   [mirror-to-disk](../01-mirroring/mirror-to-disk.md#run), then back up the cache.
5. Download the RHACS vulnerability data for the installed RHACS version
   ([RHACS vulnerability data](../01-mirroring/mirror-to-disk.md#rhacs-vulnerability-data)).
6. [Build](../01-mirroring/packaging-and-transfer.md#build-the-package),
   [verify on the media](../01-mirroring/packaging-and-transfer.md#verify-the-package), and hand
   over the package, with section 1 and 2 of the transfer record filled in.

**High side** (registry host, as `quay`, tools from the transfer on `PATH`)

7. [Accept the transfer](../02-high-side/accept-transfer.md#verify-on-the-media): signature,
   checksums, no unlisted files, [order](../02-high-side/accept-transfer.md#check-the-order). If a
   check fails, stop. Never skip a check to keep to the schedule.
8. Run [disk to mirror](../02-high-side/populate-registry.md#disk-to-mirror) with the transfer's
   own `config/imageset-config.yaml`. Keep `cluster-resources/<ID>`, back up the cache, and record
   `imported`.
9. [Publish the repository](../02-high-side/populate-registry.md#publish-the-repository) and
   record `published`.
10. Review what changed in the generated cluster resources since the last import, and what the
    cluster would change. oc-mirror v2 regenerates them for the **whole** image set on every
    import ([Cluster resources](../02-high-side/populate-registry.md#cluster-resources)):

    ```bash
    ID=T-20261106-01; PREV=T-20261002-01
    CR=/data/ocp/cluster-resources/"$ID"
    diff -ru /data/ocp/cluster-resources/"$PREV" "$CR" | tee /data/ocp/logs/cluster-resources-"$ID".diff
    oc diff -f "$CR"/idms-oc-mirror.yaml -f "$CR"/itms-oc-mirror.yaml
    ```

    A change to an `ImageDigestMirrorSet` or `ImageTagMirrorSet` is rolled out by the Machine
    Config Operator. Red Hat's 4.22 documentation says that changing these objects can drain and
    reboot nodes. If `oc diff` shows changes, apply them in a maintenance window.

11. Apply the cluster resources. CatalogSources, IDMS, ITMS, and the release signature ConfigMap
    are **applied from the oc-mirror output, not through GitOps**. Their content changes with
    every import, and Red Hat forbids editing the generated fields. Apply the same set that was
    applied on Day 1 ([Day-1 settings](../03-cluster-install/run-install.md#day-1-settings)):

    ```bash
    for f in "$CR"/*.yaml; do
      [ "$(basename "$f")" = updateService.yaml ] && continue
      oc apply -f "$f"
    done
    oc apply -f "$CR"/signature-configmap.json      # release signatures (same object as the .yaml)
    ```

    For OLM v1, the `ClusterCatalog` (`cc-*.yaml`) files are included in the loop. The 4.22
    documentation lists IDMS, ITMS, `CatalogSource`, `ClusterCatalog`, `UpdateService`, and the
    signature ConfigMap as the generated resources. It doesn't mention `ClusterImagePolicy`. If a
    later oc-mirror version writes other files, review them before applying them.

12. If OpenShift Update Service is installed, apply the new graph data
    ([OSUS setup](upgrades.md#one-time-setup-openshift-update-service)):

    ```bash
    oc apply -n openshift-update-service -f "$CR"/updateService.yaml
    ```

13. Make sure that OLM reads the new catalog. If `spec.image` didn't change (a tag reference), OLM
    might keep the old catalog pod. In that case, delete the pod so that it's re-created and pulls
    the new catalog image:

    ```bash
    oc get catalogsource cs-redhat-operator-index-v4-22 -n openshift-marketplace \
      -o jsonpath='{.spec.image}{"\n"}'
    oc delete pod -n openshift-marketplace -l olm.catalogSource=cs-redhat-operator-index-v4-22
    ```

### Verification

```bash
# Catalog is serving
oc get catalogsource cs-redhat-operator-index-v4-22 -n openshift-marketplace \
  -o jsonpath='{.status.connectionState.lastObservedState}{"\n"}'          # READY

# New versions are visible (repeat for each package in the PR)
oc get packagemanifest compliance-operator -n openshift-marketplace \
  -o jsonpath='{range .status.channels[*]}{.name}{"\t"}{.currentCSV}{"\n"}{end}'

# Mirror configuration and signatures are on the cluster
oc get imagedigestmirrorset,imagetagmirrorset
oc get configmap -n openshift-config-managed | grep -i signature
oc get mcp                                                                 # UPDATED=True everywhere

# Pending install plans now offered (approve only under the upgrade change)
oc get installplan -A | grep -w false
```

The new z-stream appears in `oc adm upgrade recommend` once OSUS serves the new graph data
([Upgrades](upgrades.md)).

### Rollback

- Content in the mirror registry is additive. Nothing that the cluster uses was removed.
- Because every Subscription uses manual approval, a new catalog doesn't change any installed
  operator. If the content is bad, don't approve the install plans, and delete the pending ones
  (`oc delete installplan <name> -n <namespace>`).
- Mirror configuration: re-apply the IDMS and ITMS from `/data/ocp/cluster-resources/<previous ID>`
  and point `current` back to it (`ln -sfn <previous ID> /data/ocp/cluster-resources/current`).
- A failed import: record `import-failed` and follow
  [Ordering and re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining).

### Records and evidence

| Record | Where | Controls |
|---|---|---|
| Pull request with catalog report and dry-run size | Git | CM-3, CM-4 |
| Transfer record; `MANIFEST.json`, `SHA256SUMS`, signature | Records system, transfer directory | MP-5, SA-12, SI-7 |
| Import log rows `accepted`, `imported`, `published` | `/data/ocp/import-log.md` | CM-3, SI-7 |
| `cluster-resources/<ID>` with checksums; the diff file | Registry host `/data/ocp` | CM-2, CM-8 |
| Verification output | Change ticket | CM-3, SI-2 |

### Related controls

CM-2, CM-3, CM-4, CM-8, CM-11, MP-5, SA-12, SI-2, SI-7.

## Emergency CVE import

### Purpose and scope

Bring a fixed release or operator version to the high side within the departmental timeline for
critical vulnerabilities (SI-2). The steps are the same as the monthly import. Only the approval
is faster, and the change to the content is as small as possible.

### Roles

As for the [monthly import](#monthly-content-import). The **DSO** confirms that the vulnerability
qualifies, and an emergency change approval (ECAB) replaces the routine change. A second reviewer
is still required.

### Prerequisites

- Emergency change ticket that references the CVE or advisory, and the affected component.
- The fixed version exists in a channel that is already mirrored (or the PR adds that channel).
- No other content transfer is in flight. Transfers are deltas and must be imported in order. If
  a monthly transfer is still in transit, import it first, or rebuild with `--since`
  ([Ordering and re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining)).

### Procedure

1. Make the **smallest possible** change to `01-mirror/imageset-config.yaml`, for example raise
   only the platform `maxVersion`, or only the affected operator's range. Keep using the same file.
   oc-mirror's history makes the archive a delta, and the high side needs the same configuration.
   Don't combine the change with other pending ISC changes.
2. Dry run. The `mapping.txt` must list only the fix and what it depends on. Get an expedited
   review and merge.
3. Continue with steps 4–13 of the [monthly import](#monthly-content-import). Skip the RHACS
   download if a feed transfer runs the same day.
4. **Never skip** the signature check, the checksums, the unlisted-file check, or the malware
   scan. If the transfer key or a check fails, the transfer is rejected, whatever the urgency.
5. Apply the fix with [Upgrades](upgrades.md) (cluster) or
   [Operator upgrades](upgrades.md#operator-upgrade-with-manual-install-plans).

### Verification

- Same checks as the monthly import. The fixed version is in `oc adm upgrade recommend` or in the
  package manifest.
- After the upgrade: the affected component reports the fixed version
  (`oc get clusterversion`, `oc get csv -n <namespace>`), and RHACS no longer reports the CVE as
  fixable for that component.

### Rollback

As for the [monthly import](#monthly-content-import). If the fix itself is faulty, use the
rollback in [Upgrades](upgrades.md).

### Records and evidence

Same as the monthly import, plus the emergency approval, the CVE or advisory reference, and the
time from advisory to fix (SI-2 timeline evidence). Review the emergency change at the next CAB.

### Related controls

SI-2, SI-5, RA-5, CM-3, CM-4, IR-4, SA-12, SI-7.

## Daily RHACS vulnerability data import

### Purpose and scope

Keep RHACS Central's offline vulnerability data current (RA-5(2)). Red Hat's offline-mode guidance
is to upload new data at least once a day. Phase 4 already documents the upload; this SOP only
connects the existing steps.

### Roles

Performed by the platform engineer (or an on-call operator). Transfer approval by the
content-transfer officer. The DSO is informed when a day is missed.

### Prerequisites

The RHACS version on the cluster (`oc get csv -n rhacs-operator`) matches the data version. An
RHACS API token file exists (mode `0600`).

### Procedure

1. Low side: download the data
   ([RHACS vulnerability data](../01-mirroring/mirror-to-disk.md#rhacs-vulnerability-data)) and
   build a package **without** `content/` or `tools/`
   ([Package layout](../01-mirroring/packaging-and-transfer.md#package-layout)). Feed transfers
   aren't part of the ordering chain.
2. High side: [accept](../02-high-side/accept-transfer.md#verify-on-the-media) it (signature and
   checksums, as for any transfer), and copy the `.zip` to `/data/ocp/rhacs/`.
3. Upload it with `roxctl scanner upload-db`, as shown in
   [RHACS](../04-itsg33-configuration/platform-configuration.md#rhacs). Record the file name and
   its SHA-256.
4. Add a row to the import log, for example event `rhacs-uploaded`.

### Verification

`roxctl` reports success. In the RHACS portal, the vulnerability definitions date is today's
date.

### Rollback

None needed. Data that is older or missing only means scans miss recent CVEs. If a day is missed,
record the gap as a residual risk, as [Ongoing imports](../01-mirroring/ongoing-imports.md#recommended-cadence)
requires.

### Records and evidence

Transfer record, the import log row, and the SHA-256 of the uploaded file (RA-5(2), SI-5).

### Related controls

RA-5, RA-5(2), SI-5, SI-7, MP-5.
