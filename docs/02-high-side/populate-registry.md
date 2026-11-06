# Populate the Registry

[← Phase 2](index.md)

## Disk to mirror

```bash
02-high-side/06-disk-to-mirror.sh T-20261106-01             # import
02-high-side/06-disk-to-mirror.sh T-20261106-01 --dry-run   # see what would happen
```

The script:

1. Checks the transfer was accepted, has content, wasn't imported already, and follows the last
   import ([ordering](accept-transfer.md#ordering-and-re-baselining)).
2. Uses `oc-mirror` from the transfer's tools and the **transfer's own**
   `config/imageset-config.yaml` (oc-mirror needs the same configuration on both sides).
3. Hard-links the archives into the workspace (no extra disk space when on the same filesystem)
   and runs:

   ```bash
   oc-mirror --v2 --config <transfer>/config/imageset-config.yaml \
     --from file:///data/ocp/oc-mirror --cache-dir /data/ocp/oc-mirror-cache \
     --authfile <IMPORTER_AUTH_FILE> \
     docker://<REGISTRY_FQDN>:8443/mirror
   ```

4. Copies the generated cluster resources to `/data/ocp/cluster-resources/<ID>/`, writes a
   `SHA256SUMS` for them, points `current` at them, and records `imported` in the ledger.

All content lands under the `mirror` organization, for example
`<REGISTRY_FQDN>:8443/mirror/openshift/release-images`.

### Keep the workspace and cache

Red Hat warns that deleting or modifying the oc-mirror cache (`/data/ocp/oc-mirror-cache`) or
workspace (`/data/ocp/oc-mirror/working-dir`) can cause failed or incomplete mirroring and loss of
incremental data. Back up the cache after each import (Red Hat requires this); the workspace is
regenerated on each run and doesn't need a backup, but leave it in place.

Separately, each delta only contains images that are new since the previous transfer, so the
mirror registry must already hold the earlier content. In testing, importing only the second of
two transfers into an empty registry failed (oc-mirror exited with code 8 and reported
`manifest unknown` for an image that was only in the first archive). This is why imports must be
in order, and why the registry's own storage must be backed up.

## Cluster resources

oc-mirror v2 regenerates these files on every import. They always describe the **whole** mirrored
image set, not only the delta:

| File | Kind | Used in |
|---|---|---|
| `idms-oc-mirror.yaml` | `ImageDigestMirrorSet` | Install (`imageDigestSources` in Phase 3) and Day 2 |
| `itms-oc-mirror.yaml` | `ImageTagMirrorSet` | Day 2 (additional images pulled by tag) |
| `cs-redhat-operator-index-*.yaml` | `CatalogSource` (OLM classic) | Phase 4 (replaces the default sources) |
| `cc-redhat-operator-index-*.yaml` | `ClusterCatalog` (OLM v1) | Phase 4, if OLM v1 is used |
| `signature-configmap.json` / `.yaml` | `ConfigMap` `mirrored-release-signatures` in `openshift-config-managed` | Day 2, so the cluster can verify release signatures for upgrades |
| `updateService.yaml` | `UpdateService` | Phase 6 (OpenShift Update Service) |

Red Hat documents fields in these resources that **must not be changed**: `spec.image` in a
`CatalogSource`, `spec.source.image.ref` in a `ClusterCatalog`, `spec.imageDigestMirrors` /
`spec.imageTagMirrors`, `binaryData` and the namespace of the signature `ConfigMap`, and
`spec.graphDataImage` / `spec.releases` in the `UpdateService`. Change names, labels, or
`updateStrategy` if you need to, but not those fields.

Keep every import's directory: it records what the cluster was told to trust at that point
(CM-2, CM-8).

## Extract the installer

```bash
02-high-side/07-extract-installer.sh          # for OCP_MAX_VERSION
```

Two Red Hat 4.22 procedures apply here:

- *Installation overview → Support for FIPS cryptography*: extract the FIPS-capable installer
  with `oc adm release extract --command=openshift-install-fips` (requires `oc` 4.16 or later),
  and use it in place of `openshift-install`.
- *Installing on bare metal → Installer-provisioned infrastructure*: extract the installer with
  `--command=openshift-baremetal-install`.

In the `oc` 4.22 source code (`pkg/cli/admin/release/extract_tools.go`), both commands map to the
same file in the release's `baremetal-installer` image. This repository uses
`openshift-install-fips`, the name the FIPS procedure uses. This is an observation from the source
code, not a documented statement; confirm with Red Hat support if your assessor needs it in
writing.

The script:

1. Looks up `<REGISTRY_FQDN>:8443/mirror/openshift/release-images:<version>-x86_64` with the pull-only
   credentials, and reads the release **digest** and version.
2. Checks that `signature-configmap.json` contains a signature for that digest.
3. Extracts the installer for the **canonical** reference
   `quay.io/openshift-release-dev/ocp-release@sha256:…`, resolving it through the mirror with
   `--idms-file` (the generated IDMS).
4. Checks that `openshift-install-fips version` reports that exact release image, and writes
   `/data/ocp/installer/<version>/release.env`:

```bash
OCP_RELEASE_VERSION=4.22.18
OCP_RELEASE_DIGEST=sha256:...
OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release@sha256:...
OCP_RELEASE_MIRROR=registry.example.gc.ca:8443/mirror/openshift/release-images
OCP_INSTALLER=/data/ocp/installer/4.22.18/openshift-install-fips
OCP_INSTALLER_SHA256=...
OCP_IDMS_FILE=/data/ocp/cluster-resources/T-20261106-01/idms-oc-mirror.yaml
```

Pinning to the canonical digest means the installer, the IDMS, and `install-config.yaml` all
refer to the same immutable release (SI-7). The installer must **run** on a RHEL 9 host in FIPS
mode (the provisioner host, Phase 3); copy it there with `release.env`.

## Publish the repository

```bash
02-high-side/08-publish-repo.sh T-20261106-01
```

The script checks that the bundle's branch head is the commit recorded in the transfer's
`MANIFEST.json` (and refuses a transfer built from uncommitted changes), fetches it into
`GIT_LOCAL_CLONE`, **fast-forwards** `GIT_BRANCH`, tags the commit `transfer/<ID>`, and pushes both
to `GIT_REMOTE_URL`.

It refuses to publish if the high-side branch has diverged from the low-side history. The
reviewed low-side history is the source of truth (CM-3, CM-5); high-side-only changes (for
example, cluster overlays that reference high-side names) go on a separate branch or repository.

## Hand-off to Phase 3

| Item | Location |
|---|---|
| Release details and installer | `/data/ocp/installer/<version>/release.env`, `openshift-install-fips` |
| Mirror configuration for `install-config.yaml` | `/data/ocp/cluster-resources/current/idms-oc-mirror.yaml` |
| Pull secret for `install-config.yaml` | `CLUSTER_PULL_SECRET_FILE` (pull-only robot) |
| Trust bundle for `install-config.yaml` | `TLS_CA_BUNDLE` |
| Configuration repository | Departmental Git, tag `transfer/<ID>` |
