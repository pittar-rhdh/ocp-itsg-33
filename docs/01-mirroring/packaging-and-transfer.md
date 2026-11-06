# Packaging and Transfer

[← Phase 1](index.md)

> **Examples only — not validated.** Test and adapt the commands before use. See
> [Validation status](../reference/validation-status.md).

Everything that crosses to the high side travels as **one transfer package**: a directory with
a signed SHA-256 manifest and a chain-of-custody record. The high side imports nothing that
didn't arrive this way.

## Package layout

```text
/data/mirror/transfers/T-20261106-01/
  content/mirror_000001.tar ...       mirror archives (moved from the archive directory)
  config/imageset-config.yaml         ISC used for the run; needed for disk-to-mirror
  config/isc_pinned_<time>.yaml       ISC with catalogs pinned by digest (if oc-mirror wrote one)
  config/disc_pinned_<time>.yaml      delete configuration for later pruning
  tools/                              verified oc, oc-mirror, mirror registry, butane, roxctl + checksum lists
  rhacs/scanner-vuln-updates-*.zip    RHACS offline vulnerability data (moved)
  repo/ocp-itsg-33.bundle             git bundle of the main branch of this repository
  logs/mirror-to-disk-<time>.log      oc-mirror log for the run
  MANIFEST.json                       ID, time, user@host, commit, versions, ISC checksum,
                                      previousContentTransferId (ordering chain)
  SHA256SUMS                          SHA-256 of every file above
  SHA256SUMS.asc                      detached GPG signature of SHA256SUMS
  transfer-record.md                  chain-of-custody record (completed by hand)
```

Leave out `content/` for a vulnerability-feed or repository-only transfer, and `tools/` when the
high side already has them for this version.

Content transfers are deltas, so each `MANIFEST.json` records the ID of the content transfer
built before it (`previousContentTransferId`). The high side refuses to accept or import content
transfers out of that order; see
[Ordering and re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining).

`transfer-record.md` is deliberately **not** covered by `SHA256SUMS`, because people fill it in
as the package moves. Its first section records the SHA-256 of `SHA256SUMS`, which ties the paper
trail to the signed content.

## Build the package

Use the departmental ticket or change number as the transfer ID if you have one. The repository
must have no uncommitted changes, so the package matches a known commit.

```bash
REPO=~/ocp-itsg-33
ID=T-20261106-01
OUT=/data/mirror/transfers/${ID}
PREV=$(cat /data/mirror/transfers/.last-content-transfer 2>/dev/null || echo none)
test -z "$(git -C ${REPO} status --porcelain)" || echo "STOP: uncommitted changes"
mkdir -p ${OUT}/{content,config,tools,rhacs,repo,logs}

# Content, configuration, and the log of the run
mv /data/mirror/archive/mirror_*.tar ${OUT}/content/
cp ${REPO}/01-mirror/imageset-config.yaml ${OUT}/config/
cd /data/mirror/archive/working-dir
for kind in isc disc; do
  f=$(ls -1 ${kind}_pinned_*.yaml 2>/dev/null | LC_ALL=C sort | tail -1)
  [ -n "$f" ] && cp "$f" "${OUT}/config/${f//:/}"     # ':' is not valid on exFAT/NTFS media
done
cp /data/mirror/archive/logs/mirror-to-disk-<run-id>.log ${OUT}/logs/

# Tools and RHACS data
cp -a /data/mirror/tools/4.22.18/. ${OUT}/tools/
mv /data/mirror/rhacs/*.zip ${OUT}/rhacs/

# Repository
git -C ${REPO} bundle create ${OUT}/repo/ocp-itsg-33.bundle main
git bundle list-heads ${OUT}/repo/ocp-itsg-33.bundle

# Manifest
cat > ${OUT}/MANIFEST.json <<EOF
{
  "transferId": "${ID}",
  "previousContentTransferId": "${PREV}",
  "created": "$(date -u +%FT%TZ)",
  "createdBy": "$(id -un)@$(uname -n)",
  "repository": {"commit": "$(git -C ${REPO} rev-parse HEAD)", "branch": "main"},
  "versions": {"ocpChannel": "stable-4.22", "ocpMin": "4.22.18", "ocpMax": "4.22.18"},
  "imagesetConfigSha256": "$(sha256sum ${OUT}/config/imageset-config.yaml | cut -d' ' -f1)"
}
EOF
```

Then check file names, write the checksums, and sign:

```bash
cd ${OUT}
find . -name '*[:\\*?"<>|]*'      # must print nothing: names must be valid on exFAT/NTFS media
find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.asc ! -name transfer-record.md -printf '%P\n' \
  | LC_ALL=C sort | xargs -d '\n' sha256sum > SHA256SUMS
gpg --local-user <fingerprint> --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS
sha256sum SHA256SUMS              # write this digest in section 1 of the transfer record
cp ${REPO}/01-mirror/transfer-record.md transfer-record.md

# Content transfers only: this one is now the head of the ordering chain.
echo ${ID} > /data/mirror/transfers/.last-content-transfer
```

Complete section 1 of `transfer-record.md` from `MANIFEST.json`, the `sha256sum SHA256SUMS`
output, and the signing key fingerprint.

## Integrity model

```text
 Red Hat key ──verifies──> tools and checksum lists          (Mirror workstation → Tools)
 Transfer key ──signs────> SHA256SUMS ──covers──> every file in the package
 Transfer public key (out of band) ──verifies──> SHA256SUMS.asc   (Verify the package)
 transfer-record.md ──records──> SHA-256 of SHA256SUMS, people, media, dates
```

## Verify the package

Check that:

1. `SHA256SUMS.asc` is a valid signature of `SHA256SUMS` by the transfer key,
2. every listed file is present and matches its checksum,
3. **no unlisted file** is present (nothing was added in transit), and
4. the git bundle is readable.

```bash
cd /run/media/transfer/T-20261106-01
gpg --dearmor < ocp-transfer-key.pub.asc > /tmp/transfer-key.gpg   # public key received out of band
gpgv --keyring /tmp/transfer-key.gpg SHA256SUMS.asc SHA256SUMS     # must say "Good signature"
sha256sum --check --strict --quiet SHA256SUMS && echo "checksums OK"
comm -13 <(sed -E 's/^[0-9a-f]{64}  //' SHA256SUMS | LC_ALL=C sort) \
         <(find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.asc ! -name transfer-record.md \
             -printf '%P\n' | LC_ALL=C sort)                          # must print nothing
git bundle list-heads repo/ocp-itsg-33.bundle
sha256sum SHA256SUMS                                                # must match the transfer record
```

Run it **twice**: on the low side against the copy on the media (before the media leaves), and on
the high side when it arrives (Phase 2). Record both results on the transfer record. Any failure
means the package is not imported.

## Media and transfer

| Step | Guidance |
|---|---|
| Approve | The change or ticket is approved, and the content matches the reviewed `imageset-config.yaml` (section 2 of the record) |
| Media | Departmentally approved, encrypted removable media, labelled with its classification (MP-3). exFAT or XFS file systems; for FAT32, set `archiveSize: 3` in the ISC. |
| Copy | `cp -r` (or `rsync -a`) the whole package directory to the media, then [verify](#verify-the-package) **the media copy** |
| Malware scan | As departmental policy requires, on both sides. Record the tool and result. Image archives are large, so plan the time. |
| Custody | Record every hand-off (section 3). The media is never unattended outside an approved storage container (MP-4, MP-5). |
| Cross-domain solution | If a CDS or data diode is used instead of removable media, the same package and verification apply; the CDS logs replace the custody table. Check the CDS's file size and type limits. |
| Receipt | High side verifies, scans, and records receipt (section 4) before anything is imported |
| Disposition | Wipe, return, or destroy the media as ITSP.40.006 requires (section 5) |

## What to keep on the low side

After the high side confirms the import:

- delete the `content/` archives from `/data/mirror/transfers/<transfer-id>/` (they are
  re-creatable with `oc-mirror --since`),
- **keep** `MANIFEST.json`, `SHA256SUMS`, `SHA256SUMS.asc`, `config/`, `logs/`, and the
  completed `transfer-record.md` for the retention period your records schedule sets (AU-11),
- keep the cache and `working-dir/`.
