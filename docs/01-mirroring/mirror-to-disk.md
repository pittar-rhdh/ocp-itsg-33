# Mirror to Disk

[← Phase 1](index.md)

`05-mirror-to-disk.sh` runs the `oc-mirror` v2 **mirror-to-disk** workflow: it pulls everything in
`imageset-config.yaml` from Red Hat and writes it to archive files that can be carried to the
high side.

```bash
01-mirror/05-mirror-to-disk.sh --dry-run    # optional: list what would be mirrored
01-mirror/05-mirror-to-disk.sh
```

The script runs:

```bash
oc-mirror --v2 \
  --config 01-mirror/imageset-config.yaml \
  --cache-dir "${MIRROR_CACHE_DIR}" \
  --authfile "${REGISTRY_AUTH_FILE}" \
  file://"${MIRROR_ARCHIVE_DIR}"
```

Before it starts, it checks that:

- the committed `imageset-config.yaml` matches `versions.env` (`04-render-imageset-config.sh --check`),
- there are no `mirror_*.tar` archives left from a previous run that haven't been packaged yet.
  `oc-mirror` reuses the same file names on every run, so mixing runs would lose content.

## Output

```text
${MIRROR_ARCHIVE_DIR}/
  mirror_000001.tar ...          archives for this run (moved into the transfer package)
  working-dir/                   oc-mirror metadata and history (keep)
    isc_pinned_<time>.yaml       ISC with catalogs pinned by digest (observed file name)
    disc_pinned_<time>.yaml      matching delete configuration
    dry-run/mapping.txt          image list (dry runs)
  logs/mirror-to-disk-<time>.log full log of each run (goes into the transfer package)
  last-run.env                   run ID, git commit, and ISC checksum (used by packaging)
${MIRROR_CACHE_DIR}/             blob cache (keep, and back up)
```

## Incremental runs

`oc-mirror` keeps a history in `working-dir/`. Each run only archives content that is **new since
the last successful run**: a run with no changes produces an archive of a few hundred KiB. To
rebuild a delta from a specific date (for example, after a lost transfer), use:

```bash
01-mirror/05-mirror-to-disk.sh --since 2026-10-01
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

If `MIRROR_ARCHIVE_SIZE_GB` is set, it is rendered as `archiveSize` and the script adds
`--strict-archive`, so no archive file exceeds the limit (the run fails instead). Use it when the
media or cross-domain solution has a per-file limit.

## Optional: verify image signatures while mirroring

By default, `oc-mirror` copies image signatures but doesn't enforce them on the low side.
OpenShift verifies the **release** payload signature on the cluster, but operator and additional
images are not checked at that point. To check Red Hat signatures for images from
`registry.redhat.io` and `registry.access.redhat.com` **before** they enter a transfer (SA-12,
SI-7):

```bash
# 01-mirror/settings.local.env
MIRROR_VERIFY_SIGNATURES=true
# MIRROR_SIGNATURE_POLICY=/path/to/policy.json   # default: 01-mirror/signature-policy.json
```

This adds `--secure-policy=true --policy 01-mirror/signature-policy.json --registries.d
/etc/containers/registries.d`. The policy requires a signature by the Red Hat release key for the
two Red Hat registries and accepts everything else (the release payload on `quay.io` is verified
on the cluster).

> **Test before relying on it.** Run a dry run with signature verification on, against the
> exact content set, before using it for a real import. It depends on the
> `/etc/containers/registries.d/` sigstore configuration that ships with RHEL 9. If an image
> fails verification, **don't** turn verification off to get past it: record the image and raise
> it with Red Hat support.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `unauthorized` / `invalid username/password` for `registry.redhat.io` | Pull secret missing, expired, or not at `REGISTRY_AUTH_FILE` |
| `imageset-config.yaml is out of date` | `versions.env` changed; run `04-render-imageset-config.sh` and commit |
| `archive(s) from a previous run are still in ...` | Package the previous run (`07-package-transfer.sh`) or, if it was abandoned, move the archives away deliberately |
| Default channel error for a package | You listed channels without the package's default channel; see [ImageSetConfiguration](imageset-configuration.md#operator-entries) |
| Run is much larger than expected | Check the OpenShift version range and any `minVersion`; review `dry-run/mapping.txt` |
| Disk full | Cache and archives both need space on the first run; see [sizing](workstation.md#storage-sizing) |
