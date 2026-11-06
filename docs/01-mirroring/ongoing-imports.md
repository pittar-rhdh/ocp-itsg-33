# Ongoing Imports

[← Phase 1](index.md)

An air-gapped cluster is only as current as its last import. The import cadence is a security
control: it bounds how long known vulnerabilities stay unpatched (SI-2) and how stale
vulnerability data is (RA-5(2)). Agree the cadence with the departmental security officer and
record it in the SSP.

## Recommended cadence

| Import | Frequency | Content | Command |
|---|---|---|---|
| **Scheduled** | Monthly | New OpenShift z-stream, operator updates, refreshed additional images | Full workflow (`04` → `05` → `07`) |
| **Vulnerability feed** | Daily if the transfer process allows it (Red Hat's RHACS offline-mode guidance is to upload new definitions at least once per day); otherwise as often as possible, with the gap recorded as a residual risk | RHACS offline vulnerability data | `06-download-rhacs-db.sh`, then `07-package-transfer.sh --no-content --no-tools` |
| **Emergency** | Within the departmental timeline for critical vulnerabilities | The fixed release or operator version only | Full workflow, expedited approval |
| **Repository only** | As needed | Changes to this repository (configuration, SOPs) | `07-package-transfer.sh --no-content --no-tools` |

## Scheduled import procedure

1. Run `03-list-operator-channels.sh` and review the release notes and errata for new versions.
2. Edit `versions.env`:
   - Raise `OCP_MAX_VERSION` to the new z-stream. Keep `OCP_MIN_VERSION` at the version
     **currently installed** on the high side, so the update graph includes the path from it.
   - Set `minVersion` for installed operators to their installed versions.
3. Render, review, and merge (`04-render-imageset-config.sh`, pull request).
4. Run `05-mirror-to-disk.sh`. It's incremental: only new content is archived.
5. If `RHACS_VERSION` changed, run `01-download-tools.sh` and `06-download-rhacs-db.sh`.
6. Package, verify, and transfer.
7. On the high side, import (Phase 2) and upgrade (Phase 6 SOPs).
8. After the upgrade, raise `OCP_MIN_VERSION` to the new installed version in the next import.

Old content isn't deleted from the mirror registry by an import. Pruning uses the delete
configuration (`disc_pinned_*.yaml`) and is covered in the Phase 6 SOPs.

## Y-stream upgrades

Moving to the next minor release (for example, 4.22 to 4.24 through an EUS-to-EUS path) needs
more than one channel in the ISC. The render script supports one platform channel today; y-stream
imports are covered with the upgrade SOPs in Phase 6.

## Keeping the low side healthy

- Back up `${MIRROR_CACHE_DIR}` after every successful run.
- Keep `${MIRROR_ARCHIVE_DIR}/working-dir`; it is the incremental history.
- Patch the workstation monthly, and download new tools when `OCP_MAX_VERSION` changes.
- Rotate the transfer signing key before it expires, and give the high side the new public key
  out of band **before** the first transfer signed with it.

## Records for each import

| Record | Location | Controls |
|---|---|---|
| Pull request changing `versions.env` and `imageset-config.yaml`, with the catalog report | Git | CM-3, CM-4 |
| `MANIFEST.json`, `SHA256SUMS`, `SHA256SUMS.asc`, pinned ISC, `oc-mirror` log | Low-side transfer directory | SA-12, SI-7, CM-8 |
| Completed transfer record | Departmental records system | MP-2, MP-4, MP-5 |
| High-side import confirmation | Phase 2 records | CM-3, SI-2 |
