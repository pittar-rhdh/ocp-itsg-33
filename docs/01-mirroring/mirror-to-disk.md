# Mirror to Disk

[← Phase 1](index.md)

> **Examples only — not validated.** Test and adapt the commands before use. See
> [Validation status](../reference/validation-status.md).

The `oc-mirror` v2 **mirror-to-disk** workflow pulls everything in
`01-mirror/imageset-config.yaml` from Red Hat and writes it to archive files that can be carried
to the high side. Run it from a clean checkout of the reviewed, committed configuration.

## Before you start

```bash
cd ~/ocp-itsg-33
git status --porcelain            # must be empty: the run must match a known commit
ls /data/mirror/archive/mirror_*.tar 2>/dev/null   # must be empty
```

`oc-mirror` reuses the same archive file names on every run, so archives left from a previous
run must be packaged (or deliberately moved away) first; mixing runs would lose content.

## Dry run

A dry run lists what would be mirrored without downloading it. Use it to estimate size and to
review the image list before a real run:

```bash
umask 0022
oc-mirror --v2 \
  --config 01-mirror/imageset-config.yaml \
  --cache-dir /data/mirror/cache \
  --authfile ~/.secrets/pull-secret.json \
  --dry-run \
  file:///data/mirror/archive
less /data/mirror/archive/working-dir/dry-run/mapping.txt
```

## Run

```bash
umask 0022                        # Red Hat prerequisite for hosts that run oc-mirror
mkdir -p /data/mirror/archive/logs
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
oc-mirror --v2 --version
oc-mirror --v2 \
  --config 01-mirror/imageset-config.yaml \
  --cache-dir /data/mirror/cache \
  --authfile ~/.secrets/pull-secret.json \
  file:///data/mirror/archive 2>&1 | tee /data/mirror/archive/logs/mirror-to-disk-${RUN_ID}.log

# Record what the run was built from (goes on the transfer record and in MANIFEST.json).
git rev-parse HEAD
sha256sum 01-mirror/imageset-config.yaml
ls -lh /data/mirror/archive/mirror_*.tar
```

Check that `oc-mirror` exited without errors and that no error file was written under
`working-dir/logs/`. Then back up the cache (see [Incremental runs](#incremental-runs)).

## Output

```text
/data/mirror/archive/
  mirror_000001.tar ...          archives for this run (moved into the transfer package)
  working-dir/                   oc-mirror metadata and history (keep)
    isc_pinned_<time>.yaml       ISC with catalogs pinned by digest (observed file name)
    disc_pinned_<time>.yaml      matching delete configuration
    dry-run/mapping.txt          image list (dry runs)
  logs/mirror-to-disk-<time>.log full log of each run (goes into the transfer package)
/data/mirror/cache/              blob cache (keep, and back up)
```

## Incremental runs

`oc-mirror` keeps a history in `working-dir/`. Each run only archives content that is **new since
the last successful run**: a run with no changes produces an archive of a few hundred KiB. To
rebuild a delta from a specific date (for example, after a lost transfer), add `--since`:

```bash
oc-mirror --v2 --config 01-mirror/imageset-config.yaml \
  --cache-dir /data/mirror/cache --authfile ~/.secrets/pull-secret.json \
  --since 2026-10-01 \
  file:///data/mirror/archive
```

Consequences:

- **Transfers must be imported in order** on the high side. A delta assumes the earlier ones are
  already in the mirror registry.
- **Don't delete or modify `working-dir/` or the cache.** Red Hat warns that this can cause
  failed or incomplete mirroring, loss of incremental data, and a full re-mirror. Red Hat requires
  backing up the **cache** after each successful run (CP-9); the workspace is regenerated on each
  run and doesn't need a backup, but must be left in place.
- If a transfer is lost or rejected, re-create it with `--since` set to the date of the last
  transfer the high side **accepted**, after resetting the ordering chain (see
  [Ordering and re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining)).

## Archive size

If `archiveSize` is set in `imageset-config.yaml`, add `--strict-archive` to the `oc-mirror`
command so that no archive file exceeds the limit (the run fails instead). Use it when the media
or cross-domain solution has a per-file limit.

## Optional: verify image signatures while mirroring

By default, `oc-mirror` copies image signatures but doesn't enforce them on the low side.
OpenShift verifies the **release** payload signature on the cluster, but operator and additional
images are not checked at that point. To check Red Hat signatures for images from
`registry.redhat.io` and `registry.access.redhat.com` **before** they enter a transfer (SA-12,
SI-7), add these flags to the `oc-mirror` command:

```bash
  --secure-policy=true \
  --policy 01-mirror/signature-policy.json \
  --registries.d /etc/containers/registries.d \
```

The example policy, `01-mirror/signature-policy.json`, requires a signature by the Red Hat
release key (`/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release`) for the two Red Hat registries and
accepts everything else (the release payload on `quay.io` is verified on the cluster).

> **Test before relying on it.** Run a dry run with signature verification on, against the
> exact content set, before using it for a real import. It depends on the
> `/etc/containers/registries.d/` sigstore configuration that ships with RHEL 9. If an image
> fails verification, **don't** turn verification off to get past it: record the image and raise
> it with Red Hat support.

## RHACS vulnerability data

RHACS Central on the high side needs offline vulnerability data that matches its version
(RA-5(2), SI-5). Download it with `roxctl` (see [Tools](workstation.md#tools)) on the
vulnerability-feed cadence (Red Hat's RHACS offline-mode guidance is at least once per day), not
only with platform imports:

```bash
RHACS_VERSION=<rhacs-version>     # same version as the mirrored rhacs-operator
OUT=/data/mirror/rhacs/scanner-vuln-updates-${RHACS_VERSION}-$(date -u +%Y%m%d).zip
/data/mirror/tools/4.22.18/roxctl scanner download-db \
  --version "${RHACS_VERSION}" \
  --skip-central \
  --force \
  --scanner-db-file "${OUT}"
sha256sum "${OUT}"
```

The file goes into the next transfer package (`rhacs/`).

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `unauthorized` / `invalid username/password` for `registry.redhat.io` | Pull secret missing, expired, or not the file passed with `--authfile` |
| Default channel error for a package | You listed channels without the package's default channel; see [ImageSetConfiguration](imageset-configuration.md#operator-entries) |
| "Multiple channel heads" error | A `minVersion` cut the operator's update graph; widen the range |
| Run is much larger than expected | Check the OpenShift version range and any `minVersion`; review `dry-run/mapping.txt` |
| Disk full | Cache and archives both need space on the first run; see [sizing](workstation.md#storage-sizing) |
