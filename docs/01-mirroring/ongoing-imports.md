# Ongoing Imports

[← Phase 1](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

An air-gapped cluster is only as current as its last import. The import cadence is a security
control: it bounds how long known vulnerabilities stay unpatched (SI-2) and how stale
vulnerability data is (RA-5(2)). Agree the cadence with the departmental security officer and
record it in the SSP.

## Recommended cadence

| Import | Frequency | Content | Steps |
|---|---|---|---|
| **Scheduled** | Monthly | New OpenShift z-stream, operator updates, refreshed additional images | Full workflow: edit ISC → [mirror](mirror-to-disk.md) → [package](packaging-and-transfer.md) |
| **Vulnerability feed** | Daily if the transfer process allows it (Red Hat's RHACS offline-mode guidance is to upload new definitions at least once per day); otherwise as often as possible, with the gap recorded as a residual risk | RHACS offline vulnerability data | [`roxctl scanner download-db`](mirror-to-disk.md#rhacs-vulnerability-data), then a package without `content/` or `tools/` |
| **Emergency** | Within the departmental timeline for critical vulnerabilities | The fixed release or operator version only | Full workflow, expedited approval |
| **Repository only** | As needed | Changes to this repository (configuration, SOPs) | A package with only `repo/` and `config/` |

## Scheduled import procedure

1. Review the release notes and errata for new versions, and list the available releases and
   operator versions (see [Choosing versions](imageset-configuration.md#choosing-versions)).
2. Edit `01-mirror/imageset-config.yaml` and update
   [Versions and pinned content](../reference/versions.md) to match:
   - Raise `maxVersion` to the new z-stream. Keep `minVersion` at the version **currently
     installed** on the high side, so the update graph includes the path from it.
   - Set `minVersion` for installed operators to their installed versions.
3. Review and merge the pull request, with the catalog report attached.
4. Run `oc-mirror --v2` mirror-to-disk. It's incremental: only new content is archived.
5. If the RHACS version changed, download the matching `roxctl` and vulnerability data.
6. Package, sign, verify, and transfer.
7. On the high side, import ([Content import](../06-sops/content-import.md)) and upgrade
   ([Upgrades](../06-sops/upgrades.md)).
8. After the upgrade, raise the platform `minVersion` to the new installed version in the next
   import.

Old content isn't deleted from the mirror registry by an import. Pruning uses the delete
configuration (`disc_pinned_*.yaml`) and the oc-mirror v2 delete workflow; it is not yet covered
by an SOP (see the [backlog](../reference/backlog.md)).

## Y-stream upgrades

Moving to the next minor release (for example, 4.22 to 4.24 through an EUS-to-EUS path) needs
more than one platform channel in the ISC and different tool versions. Y-stream imports are
covered in the [Control Plane Only (EUS-to-EUS) upgrade](../06-sops/upgrades.md#control-plane-only-eus-to-eus-upgrade) SOP.

## Keeping the low side healthy

- Back up `/data/mirror/cache` after every successful run.
- Keep `/data/mirror/archive/working-dir`; it is the incremental history.
- Patch the workstation monthly, and download new tools when the target OpenShift version
  changes.
- Rotate the transfer signing key before it expires, and give the high side the new public key
  out of band **before** the first transfer signed with it.

## Records for each import

| Record | Location | Controls |
|---|---|---|
| Pull request changing `imageset-config.yaml`, with the catalog report | Git | CM-3, CM-4 |
| `MANIFEST.json`, `SHA256SUMS`, `SHA256SUMS.asc`, pinned ISC, `oc-mirror` log | Low-side transfer directory | SA-12, SI-7, CM-8 |
| Completed transfer record | Departmental records system | MP-2, MP-4, MP-5 |
| High-side import confirmation | Phase 2 records | CM-3, SI-2 |
