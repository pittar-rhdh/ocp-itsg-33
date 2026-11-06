# Accept a Transfer

[← Phase 2](index.md)

> **Examples only — not validated.** The commands on this page are examples. Test and adapt
> them before use. See [Validation status](../reference/validation-status.md).

Nothing from a transfer is used on the high side until it has been **accepted**: verified on the
media, checked for ordering, copied, verified again, and recorded (SI-7, SA-12, MP-5, CM-3).

The examples use transfer `T-20261106-01` on media mounted at `/run/media/transfer`, and the
transfer public key at `/etc/pki/ocp-transfer/ocp-transfer-key.pub.asc` (delivered out of band,
never inside a transfer). For what a package contains, see
[Package layout](../01-mirroring/packaging-and-transfer.md#package-layout).

## Verify on the media

```bash
T=/run/media/transfer/T-20261106-01
cd "$T"

# 1. Signature: SHA256SUMS must be signed by the transfer key, and only that key is trusted.
export GNUPGHOME="$(mktemp -d)"
gpg --import /etc/pki/ocp-transfer/ocp-transfer-key.pub.asc
gpg --verify SHA256SUMS.asc SHA256SUMS            # must say "Good signature"; check the fingerprint
rm -rf "$GNUPGHOME"; unset GNUPGHOME

# 2. Every listed file is present and matches.
sha256sum --check --strict --quiet SHA256SUMS && echo "checksums OK"

# 3. No unlisted files (nothing was added in transit). Expected output: nothing.
comm -13 <(awk '{print $2}' SHA256SUMS | sed 's|^\*||; s|^\./||' | sort) \
         <(find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.asc ! -name transfer-record.md -printf '%P\n' | sort)

# 4. The repository bundle is readable.
git bundle verify repo/ocp-itsg-33.bundle

# Digest of SHA256SUMS: ties this package to its transfer record and the import log.
sha256sum SHA256SUMS
```

`gpg` warns that the key is not certified with a trusted signature; that is expected with a
temporary keyring. What matters is `Good signature` and that the primary key fingerprint matches
the one confirmed out of band. `transfer-record.md` is deliberately not covered by `SHA256SUMS`,
because people fill it in as the package moves.

If any check fails, **stop**: do not copy the package, record the rejection in the import log and
on the transfer record, and follow the departmental incident process.

## Check the order

Content transfers are **deltas**: each assumes the previous one is already in the mirror. The
transfer record (and the package manifest) names the content transfer built before it. Compare
it with the last content transfer you accepted in the [import log](#the-import-log):

```bash
jq -r .previousContentTransferId "$T/MANIFEST.json"   # for example T-20261002-01
```

If they don't match, don't import it; see [Ordering and re-baselining](#ordering-and-re-baselining).
Transfers without mirror content (RHACS feeds, repository updates) are not part of the chain and
can be accepted at any time.

## Copy, re-verify, and unpack

```bash
ID=T-20261106-01
cp -a "$T" /data/ocp/transfers/"$ID"
cd /data/ocp/transfers/"$ID"
sha256sum --check --strict --quiet SHA256SUMS && echo "copy OK"
chmod -R go-w .

# Tools for this OpenShift version (names as downloaded in Phase 1)
V=4.22.18
mkdir -p /data/ocp/tools/"$V"/bin
cp -a tools/. /data/ocp/tools/"$V"/
cd /data/ocp/tools/"$V"
tar -xzf openshift-client-linux-amd64-rhel9-"$V".tar.gz -C bin oc kubectl
tar -xzf oc-mirror.rhel9.tar.gz -C bin oc-mirror
install -m 0755 butane-amd64 bin/butane
chmod 0755 bin/*
export PATH=/data/ocp/tools/"$V"/bin:$PATH
oc version --client && oc-mirror --v2 --version

# RHACS offline vulnerability data, if the transfer has any (imported in Phase 4)
ls /data/ocp/transfers/"$ID"/rhacs/
mkdir -p /data/ocp/rhacs && cp /data/ocp/transfers/"$ID"/rhacs/*.zip /data/ocp/rhacs/
```

The mirror registry installer (`mirror-registry-amd64.tar.gz`) stays in
`/data/ocp/tools/<version>/` until you install or upgrade the registry.

Then complete section 4 of the package's `transfer-record.md` (receipt, malware scan, the
verification result, and the `SHA256SUMS` digest), and add an `accepted` row to the import log.

## The import log

Keep a simple, append-only record of every transfer on the registry host, for example a Markdown
table in `/data/ocp/import-log.md`. One row per event:

| Date (UTC) | Transfer | Event | Previous content transfer | SHA-256 of `SHA256SUMS` | By | Notes |
|---|---|---|---|---|---|---|
| 2026-11-06 19:14 | `T-20261106-01` | accepted | `T-20261002-01` | `3f1c…` | j.smith | Malware scan clean |
| 2026-11-06 21:02 | `T-20261106-01` | imported | | | j.smith | `cluster-resources/T-20261106-01` |
| 2026-11-06 21:20 | `T-20261106-01` | published | | | j.smith | Tag `transfer/T-20261106-01` |

Events: `received`, `rejected`, `accepted`, `imported`, `import-failed`, `published`, and the
RHACS events in Phase 4. Record a change or ticket number where you have one.

The log is CM-3 and SI-7 evidence. Never edit past rows; correct with a new row. It is watched by
auditd (see [Registry host](registry-host.md#audit-and-logging)) and backed up with `/data/ocp`.
A departmental ticketing or records system can replace the file if it captures the same fields.

On the very first transfer, start the log, and confirm on the transfer record that the transfer
public key's fingerprint was checked by a second channel before it was used.

## Ordering and re-baselining

If a delta is missing, the import fails part-way (oc-mirror can't find images that were in the
missing archive), so content transfers are imported strictly in build order.

If a transfer is lost, damaged, or rejected:

1. **Low side:** rebuild the delta from the last transfer the high side **accepted**, using
   `oc-mirror --v2 --since <yyyy-mm-dd>` with that transfer's date (see
   [Mirror to disk](../01-mirroring/mirror-to-disk.md)), and package it with a new ID that names
   the accepted transfer as its predecessor.
2. **High side:** accept it normally.

If the chain can't be repaired that way (for example, the high-side oc-mirror cache was lost),
accept the replacement only with an explicit, approved reason, and record it in the import log
(for example, `CHG0012345: re-baseline after loss of T-20261113-01`).

## After import

Once the content of a transfer is imported and the record is complete, delete the transfer's
`content/` archives from `/data/ocp/transfers/<ID>/` to recover space. Keep the manifest,
`SHA256SUMS`, `SHA256SUMS.asc`, `config/`, and `logs/` for the records retention period (AU-11).
