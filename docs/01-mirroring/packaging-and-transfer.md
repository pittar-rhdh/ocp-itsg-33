# Packaging and Transfer

[← Phase 1](index.md)

Everything that crosses to the high side travels as **one transfer package**: a directory with
a signed SHA-256 manifest and a chain-of-custody record. The high side imports nothing that
didn't arrive this way.

## Build the package

```bash
01-mirror/07-package-transfer.sh --id T-20261106-01
```

| Option | Use |
|---|---|
| `--id <ID>` | Transfer ID (default `T-<date>-<time>`). Use the departmental ticket or change number if you have one. |
| `--no-tools` | Leave out the tools directory, when the high side already has them for this version |
| `--no-content` | Package without mirror archives, for example an RHACS vulnerability feed or a repository-only update |

The script refuses to run if:

- the repository has **uncommitted changes** (the package must match a known commit),
- `TRANSFER_SIGNING_KEY` isn't set and `REQUIRE_TRANSFER_SIGNATURE=true` (the default),
- there are no archives and `--no-content` wasn't given, or
- `imageset-config.yaml` has changed since the mirror run.

## Package layout

```text
${MIRROR_TRANSFERS_DIR}/T-20261106-01/
  content/mirror_000001.tar ...       mirror archives (moved from the archive directory)
  config/imageset-config.yaml         ISC used for the run; needed for disk-to-mirror
  config/isc_pinned_<time>.yaml       ISC with catalogs pinned by digest (if oc-mirror wrote one)
  config/disc_pinned_<time>.yaml      delete configuration for later pruning
  tools/                              verified oc, oc-mirror, mirror registry, roxctl + checksums
  rhacs/scanner-vuln-updates-*.zip    RHACS offline vulnerability data (moved)
  repo/ocp-itsg-33.bundle             git bundle of the current branch of this repository
  logs/mirror-to-disk-<time>.log      oc-mirror log for the run
  MANIFEST.json                       ID, time, user@host, commit, versions, ISC checksum,
                                      previousContentTransferId (ordering chain)
  SHA256SUMS                          SHA-256 of every file above
  SHA256SUMS.asc                      detached GPG signature of SHA256SUMS
  transfer-record.md                  chain-of-custody record (completed by hand)
```

Content transfers are deltas, so each `MANIFEST.json` records the ID of the content transfer
built before it (`previousContentTransferId`, from `${MIRROR_TRANSFERS_DIR}/.last-content-transfer`).
The high side refuses to accept or import content transfers out of that order; see
[Ordering and re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining).

`transfer-record.md` is deliberately **not** covered by `SHA256SUMS`, because people fill it in
as the package moves. Its first section is filled in automatically and includes the SHA-256 of
`SHA256SUMS`, which ties the paper trail to the signed content.

The script also refuses file names that aren't valid on exFAT or NTFS media (for example, the
`:` in `oc-mirror`'s pinned file names is removed).

## Integrity model

```text
 Red Hat key ──verifies──> tools and checksum lists          (01-download-tools.sh)
 Transfer key ──signs────> SHA256SUMS ──covers──> every file in the package
 Transfer public key (out of band) ──verifies──> SHA256SUMS.asc   (08-verify-transfer.sh)
 transfer-record.md ──records──> SHA-256 of SHA256SUMS, people, media, dates
```

`08-verify-transfer.sh` checks that:

1. `SHA256SUMS.asc` is a valid signature of `SHA256SUMS` by the transfer key,
2. every listed file is present and matches its checksum,
3. **no unlisted file** is present (nothing was added in transit), and
4. the git bundle is readable.

```bash
01-mirror/08-verify-transfer.sh /run/media/transfer/T-20261106-01 --key ocp-transfer-key.pub.asc
```

Run it **twice**: on the low side against the copy on the media (before the media leaves), and on
the high side when it arrives (Phase 2). Record both results on the transfer record.

## Media and transfer

| Step | Guidance |
|---|---|
| Approve | The change or ticket is approved, and the content matches the reviewed `versions.env` (section 2 of the record) |
| Media | Departmentally approved, encrypted removable media, labelled with its classification (MP-3). exFAT or XFS file systems; for FAT32, set `MIRROR_ARCHIVE_SIZE_GB=3`. |
| Copy | `cp -r` (or `rsync -a`) the whole package directory to the media, then run `08-verify-transfer.sh` **against the media copy** |
| Malware scan | As departmental policy requires, on both sides. Record the tool and result. Image archives are large, so plan the time. |
| Custody | Record every hand-off (section 3). The media is never unattended outside an approved storage container (MP-4, MP-5). |
| Cross-domain solution | If a CDS or data diode is used instead of removable media, the same package and verification apply; the CDS logs replace the custody table. Check the CDS's file size and type limits. |
| Receipt | High side verifies, scans, and records receipt (section 4) before anything is imported |
| Disposition | Wipe, return, or destroy the media as ITSP.40.006 requires (section 5) |

## What to keep on the low side

After the high side confirms the import:

- delete the `content/` archives from `${MIRROR_TRANSFERS_DIR}/<ID>/` (they are re-creatable
  with `--since`),
- **keep** `MANIFEST.json`, `SHA256SUMS`, `SHA256SUMS.asc`, `config/`, `logs/`, and the
  completed `transfer-record.md` for the retention period your records schedule sets (AU-11),
- keep the cache and `working-dir/`.
