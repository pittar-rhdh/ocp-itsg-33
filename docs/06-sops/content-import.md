# Content Import

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

The routine monthly import and the emergency CVE import. Detailed commands are in Phases 1 and 2;
only the steps on a running cluster are written out here. Conventions: transfer `T-20261106-01`
follows `T-20261002-01`; registry `registry.example.gc.ca:8443`, organization `mirror`; catalog
source `cs-redhat-operator-index-v4-22`.

## Monthly content import

| | |
|---|---|
| **Purpose** | Bring a new z-stream, operator updates, and refreshed images to the high side and make them **available** to the cluster. Installs nothing; updates follow in [Upgrades](upgrades.md) |
| **When** | Monthly ([Recommended cadence](../01-mirroring/ongoing-imports.md#recommended-cadence)) |
| **Roles** | Platform engineer performs (low then high side); second reviewer reviews the ISC PR and the cluster-resource diff; change manager approves; content-transfer officer approves the transfer record; DSO and app teams informed |
| **Prerequisites** | Approved change ticket naming the transfer ID; previous transfer accepted and imported ([import log](../02-high-side/accept-transfer.md#the-import-log)); oc-mirror cache and `working-dir` intact on both sides ([Incremental runs](../01-mirroring/mirror-to-disk.md#incremental-runs), [Keep the workspace and cache](../02-high-side/populate-registry.md#keep-the-workspace-and-cache)); IdP login as `ocp-platform-admins` |
| **Controls** | CM-2, CM-3, CM-4, CM-8, CM-11, MP-5, SA-12, SI-2, SI-7 |

### Procedure

**Low side**

1. Review release notes and errata; list the candidate versions
   ([Choosing versions](../01-mirroring/imageset-configuration.md#choosing-versions)).
2. On a branch, edit `01-mirror/imageset-config.yaml` and `docs/reference/versions.md` per the
   [scheduled import procedure](../01-mirroring/ongoing-imports.md#scheduled-import-procedure):
   raise platform `maxVersion`, keep `minVersion` (platform and operators) at the installed
   version. A channel change also changes the Subscription in
   `04-gitops/components/operators/<package>/operator.yaml` in the **same** PR.
3. [Dry run](../01-mirroring/mirror-to-disk.md#dry-run); attach the catalog report and `mapping.txt`
   size to the PR; merge after [review](../01-mirroring/imageset-configuration.md#review-checklist-for-the-pull-request).
4. From a clean checkout of the merged commit, [mirror-to-disk](../01-mirroring/mirror-to-disk.md#run),
   then back up the cache.
5. Download [RHACS vulnerability data](../01-mirroring/mirror-to-disk.md#rhacs-vulnerability-data)
   for the installed RHACS version.
6. [Build](../01-mirroring/packaging-and-transfer.md#build-the-package) and
   [verify on the media](../01-mirroring/packaging-and-transfer.md#verify-the-package); hand over
   with transfer record sections 1–2 filled in.

**High side** (registry host, as `quay`, tools from the transfer on `PATH`)

7. [Accept the transfer](../02-high-side/accept-transfer.md#verify-on-the-media) and
   [check the order](../02-high-side/accept-transfer.md#check-the-order). If a check fails, stop.
8. [Disk to mirror](../02-high-side/populate-registry.md#disk-to-mirror) with the transfer's own
   `config/imageset-config.yaml`; keep `cluster-resources/<ID>`, back up the cache, record `imported`.
9. [Publish the repository](../02-high-side/populate-registry.md#publish-the-repository); record `published`.
10. Review what changed. oc-mirror v2 regenerates the
    [cluster resources](../02-high-side/populate-registry.md#cluster-resources) for the whole image set:

    ```bash
    ID=T-20261106-01; PREV=T-20261002-01
    CR=/data/ocp/cluster-resources/"$ID"
    diff -ru /data/ocp/cluster-resources/"$PREV" "$CR" | tee /data/ocp/logs/cluster-resources-"$ID".diff
    oc diff -f "$CR"/idms-oc-mirror.yaml -f "$CR"/itms-oc-mirror.yaml
    ```

    IDMS/ITMS changes can drain and reboot nodes (Red Hat 4.22): if `oc diff` shows changes, apply
    in a maintenance window.

11. Apply the cluster resources from the oc-mirror output (not GitOps; same set as
    [Day-1 settings](../03-cluster-install/run-install.md#day-1-settings)):

    ```bash
    for f in "$CR"/*.yaml; do
      [ "$(basename "$f")" = updateService.yaml ] && continue
      oc apply -f "$f"
    done
    oc apply -f "$CR"/signature-configmap.json      # release signatures (same object as the .yaml)
    ```

    Source-derived: the 4.22 docs list IDMS, ITMS, `CatalogSource`, `ClusterCatalog`, `UpdateService`
    and the signature ConfigMap (no `ClusterImagePolicy`). Review any other file before applying it.

12. If OSUS is installed ([OSUS setup](upgrades.md#one-time-setup-openshift-update-service)):
    `oc apply -n openshift-update-service -f "$CR"/updateService.yaml`
13. If the catalog `spec.image` didn't change (tag reference), delete the catalog pod so it pulls
    the new image:

    ```bash
    oc get catalogsource cs-redhat-operator-index-v4-22 -n openshift-marketplace \
      -o jsonpath='{.spec.image}{"\n"}'
    oc delete pod -n openshift-marketplace -l olm.catalogSource=cs-redhat-operator-index-v4-22
    ```

### Verification

```bash
oc get catalogsource cs-redhat-operator-index-v4-22 -n openshift-marketplace \
  -o jsonpath='{.status.connectionState.lastObservedState}{"\n"}'          # READY
oc get packagemanifest compliance-operator -n openshift-marketplace \
  -o jsonpath='{range .status.channels[*]}{.name}{"\t"}{.currentCSV}{"\n"}{end}'   # each package in the PR
oc get imagedigestmirrorset,imagetagmirrorset
oc get configmap -n openshift-config-managed | grep -i signature
oc get mcp                                                                 # UPDATED=True everywhere
oc get installplan -A | grep -w false     # pending; approve only under the upgrade change
```

The new z-stream appears in `oc adm upgrade recommend` once OSUS serves the new graph data.

### Rollback

Registry content is additive and manual approval means no operator changes; delete bad pending
install plans. Mirror config: re-apply IDMS/ITMS from the previous ID and
`ln -sfn <previous ID> /data/ocp/cluster-resources/current`. Failed import: record `import-failed`
and see [Ordering and re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining).

### Records

PR with catalog report and dry-run size (Git); transfer record, `MANIFEST.json`, `SHA256SUMS`,
signature; import log rows `accepted`/`imported`/`published`; `cluster-resources/<ID>` and the diff
file (`/data/ocp`); verification output in the change ticket.

## Emergency CVE import

| | |
|---|---|
| **Purpose** | Bring a fixed release or operator version to the high side within the departmental timeline for critical vulnerabilities; same steps as monthly, faster approval, smallest possible change |
| **When** | On demand, for a qualifying CVE or advisory |
| **Roles** | As for the [monthly import](#monthly-content-import); DSO confirms the vulnerability qualifies; emergency change approval (ECAB) replaces the routine change; second reviewer still required |
| **Prerequisites** | Emergency change ticket referencing the CVE/advisory and component; fix in an already-mirrored channel (or the PR adds it); no other transfer in flight — import it first or rebuild with `--since` ([Ordering and re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining)) |
| **Controls** | SI-2, SI-5, RA-5, CM-3, CM-4, IR-4, SA-12, SI-7 |

### Procedure

1. Make the **smallest** change to the same `01-mirror/imageset-config.yaml` (e.g. only platform
   `maxVersion` or one operator's range), not combined with other pending ISC changes.
2. Dry run: `mapping.txt` lists only the fix and its dependencies. Expedited review and merge.
3. Continue with steps 4–13 of the [monthly import](#monthly-content-import). Skip the RHACS
   download if a feed transfer runs the same day.
4. **Never skip** the signature, checksum, unlisted-file, or malware checks, whatever the urgency.
5. Apply the fix with [Upgrades](upgrades.md) or
   [Operator upgrades](upgrades.md#operator-upgrade-with-manual-install-plans).

### Verification

The fixed version is in `oc adm upgrade recommend` or the package manifest. After the upgrade, the
component reports it (`oc get clusterversion`, `oc get csv -n <namespace>`) and RHACS no longer
reports the CVE as fixable.

### Rollback

As for the monthly import; a faulty fix follows the rollback in [Upgrades](upgrades.md).

### Records

As monthly, plus the emergency approval, CVE/advisory reference, and advisory-to-fix time (SI-2).
Review at the next CAB.

## Daily RHACS vulnerability data import

Moved to [Security operations → RHACS vulnerability data import](security-operations.md#rhacs-vulnerability-data-import).
Feed transfers carry no `content/` or `tools/`
([Package layout](../01-mirroring/packaging-and-transfer.md#package-layout)) and are outside the
ordering chain.
