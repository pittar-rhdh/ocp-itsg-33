# Accept a Transfer

[← Phase 2](index.md)

Nothing from a transfer is used on the high side until it has been **accepted**: verified on the
media, checked for ordering, copied, verified again, and recorded.

```bash
02-high-side/01-accept-transfer.sh /run/media/transfer/T-20261106-01
```

## What the script does

1. Runs `01-mirror/08-verify-transfer.sh` on the media: the signature on `SHA256SUMS` must be
   valid for the transfer key at `TRANSFER_VERIFY_KEY`, every file must match, and there must be
   no extra files.
2. Refuses a transfer ID that was already accepted.
3. For content transfers, checks **ordering**: the transfer's `previousContentTransferId` must be
   the last content transfer accepted.
4. Copies the package to `${HS_TRANSFERS_DIR}/<ID>/` and verifies the copy.
5. Unpacks `oc`, `kubectl`, and `oc-mirror` into `${HS_TOOLS_DIR}/<version>/bin/`, and stages any
   RHACS vulnerability data in `${HS_RHACS_DIR}` for Phase 4.
6. Appends an `accepted` line to the import ledger.

Then complete section 4 of the package's `transfer-record.md` (receipt, malware scan, the
verification result, and the `SHA256SUMS` digest the script printed).

## The first transfer

On the very first transfer the high side doesn't have this repository yet, so the scripts aren't
available to verify the package that contains them. Verify by hand, then use the scripts:

```bash
T=/run/media/transfer/T-20261106-01
gpg --dearmor </etc/pki/ocp-transfer/ocp-transfer-key.pub.asc >/tmp/transfer-key.gpg
gpgv --keyring /tmp/transfer-key.gpg "$T/SHA256SUMS.asc" "$T/SHA256SUMS"   # must say "Good signature"
( cd "$T" && sha256sum --check --strict --quiet SHA256SUMS ) && echo "checksums OK"

# Only after both checks pass:
git clone --branch main "$T/repo/ocp-itsg-33.bundle" ~/ocp-itsg-33
cd ~/ocp-itsg-33
02-high-side/01-accept-transfer.sh "$T"     # accept it properly; this creates the ledger
02-high-side/08-publish-repo.sh T-20261106-01
```

Record on the transfer record that the first transfer was verified manually, and by whom.

## The import ledger

`${HS_LEDGER}` (default `/data/ocp/imports.tsv`) is an append-only, tab-separated record:

| Column | Example |
|---|---|
| time (UTC) | `2026-11-06T19:14:41Z` |
| transfer | `T-20261106-01` |
| event | `accepted`, `imported`, `import-failed`, `rhacs-staged` |
| sums_sha256 | SHA-256 of the transfer's `SHA256SUMS` (ties to the transfer record) |
| user | Account that ran the step |
| detail | `content;prev=T-20261002-01`, `nocontent`, log path, or out-of-order reason |

It is CM-3 and SI-7 evidence. It is watched by auditd (see [Registry host](registry-host.md#audit-and-logging))
and backed up with `/data/ocp`.

## Ordering and re-baselining

Content transfers are **deltas**: each assumes the previous one is already in the mirror. If one
is missing, the import fails part-way (oc-mirror can't find images that were in the missing
archive). The scripts therefore refuse to accept or import a content transfer out of order.

If a transfer is lost, damaged, or rejected:

1. **Low side:** set `${MIRROR_TRANSFERS_DIR}/.last-content-transfer` to the ID of the last
   transfer the high side **accepted**, then rebuild the delta from that transfer's date:
   `05-mirror-to-disk.sh --since <yyyy-mm-dd>`, and package it with a new ID.
2. **High side:** accept it normally. Its `previousContentTransferId` now matches.

If the chain can't be repaired that way (for example, the high-side cache was lost), accept the
replacement with an explicit, recorded reason:

```bash
02-high-side/01-accept-transfer.sh /run/media/transfer/T-20261120-02 \
  --allow-out-of-order "CHG0012345: re-baseline after loss of T-20261113-01"
```

The reason is written to the ledger, and `06-disk-to-mirror.sh` honours it.

## Non-content transfers

Transfers built with `--no-content` (RHACS feeds, repository updates) are not part of the
content chain and can be accepted at any time. Publish repository updates with
`08-publish-repo.sh <ID>`.

## After import

Once the content of a transfer is imported and the record is complete, delete the transfer's
`content/` archives from `${HS_TRANSFERS_DIR}/<ID>/` to recover space. Keep `MANIFEST.json`,
`SHA256SUMS`, `SHA256SUMS.asc`, `config/`, and `logs/` for the records retention period (AU-11).
