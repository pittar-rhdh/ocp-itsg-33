# Populate the Registry

[← Phase 2](index.md)

> **Examples only — not validated.** The commands on this page are examples. Test and adapt
> them before use. See [Validation status](../reference/validation-status.md).

Run everything on this page as `quay` on the registry host, with the tools from the accepted
transfer first on `PATH` (see [Accept a transfer](accept-transfer.md#copy-re-verify-and-unpack)).

## Disk to mirror

Import only transfers that were accepted, have mirror content, weren't imported before, and follow
the last import in the import log ([ordering](accept-transfer.md#ordering-and-re-baselining)).
Use the **transfer's own** `config/imageset-config.yaml`: oc-mirror needs the same configuration on
both sides.

```bash
ID=T-20261106-01
T=/data/ocp/transfers/"$ID"
export PATH=/data/ocp/tools/4.22.18/bin:$PATH
umask 0022                                  # Red Hat prerequisite for oc-mirror hosts

# Stage the archives in the workspace (hard links: no extra space; use cp across filesystems)
mkdir -p /data/ocp/oc-mirror /data/ocp/oc-mirror-cache /data/ocp/logs
rm -f /data/ocp/oc-mirror/mirror_*.tar
ln "$T"/content/mirror_*.tar /data/ocp/oc-mirror/

oc-mirror --v2 \
  --config "$T"/config/imageset-config.yaml \
  --from file:///data/ocp/oc-mirror \
  --cache-dir /data/ocp/oc-mirror-cache \
  --authfile ~/.config/ocp-registry/importer-auth.json \
  docker://registry.example.gc.ca:8443/mirror \
  2>&1 | tee /data/ocp/logs/disk-to-mirror-"$ID".log
```

Add `--dry-run` first to see what would be pushed. If `oc-mirror` exits non-zero, record
`import-failed` in the import log and read the log and `/data/ocp/oc-mirror/working-dir/logs/`.

All content lands under the `mirror` organization, for example
`registry.example.gc.ca:8443/mirror/openshift/release-images`. After a successful import, keep
this import's cluster resources and record `imported` in the import log:

```bash
mkdir -p /data/ocp/cluster-resources/"$ID"
cp -a /data/ocp/oc-mirror/working-dir/cluster-resources/. /data/ocp/cluster-resources/"$ID"/
( cd /data/ocp/cluster-resources/"$ID" && sha256sum -- * > SHA256SUMS )
ln -sfn "$ID" /data/ocp/cluster-resources/current
rm -f /data/ocp/oc-mirror/mirror_*.tar
```

### Keep the workspace and cache

Red Hat warns that deleting or modifying the oc-mirror cache (`/data/ocp/oc-mirror-cache`) or
workspace (`/data/ocp/oc-mirror/working-dir`) can cause failed or incomplete mirroring and loss of
incremental data. Back up the cache after each import (Red Hat requires this); the workspace is
regenerated on each run and doesn't need a backup, but leave it in place.

Separately, each delta only contains images that are new since the previous transfer, so the
mirror registry must already hold the earlier content. In earlier testing, importing only the
second of two transfers into an empty registry failed (oc-mirror exited with code 8 and reported
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

Two Red Hat 4.22 procedures apply here:

- *Installation overview → Support for FIPS cryptography*: extract the FIPS-capable installer
  with `oc adm release extract --command=openshift-install-fips` (requires `oc` 4.16 or later),
  and use it in place of `openshift-install`.
- *Installing on bare metal → Installer-provisioned infrastructure*: extract the installer with
  `--command=openshift-baremetal-install`.

In the `oc` 4.22 source code (`pkg/cli/admin/release/extract_tools.go`), both commands map to the
same file in the release's `baremetal-installer` image. This guide uses `openshift-install-fips`,
the name the FIPS procedure uses. This is an observation from the source code, not a documented
statement; confirm with Red Hat support if your assessor needs it in writing.

Pin the installer to the **canonical** release digest
(`quay.io/openshift-release-dev/ocp-release@sha256:…`) and resolve it through the mirror with the
generated IDMS, so the installer, the IDMS, and `install-config.yaml` all refer to the same
immutable release (SI-7):

```bash
V=4.22.18
PS=~/.config/ocp-registry/cluster-pull-secret.json
CA=/etc/pki/ocp-registry/ca-bundle.crt
CR=/data/ocp/cluster-resources/current

# 1. Read the release digest from the mirror (pull-only credentials)
DIGEST=$(oc adm release info -a "$PS" --certificate-authority "$CA" -o json \
  registry.example.gc.ca:8443/mirror/openshift/release-images:"$V"-x86_64 | jq -r .digest)
echo "$DIGEST"                                  # sha256:<64 hex characters>

# 2. A release signature for that digest was mirrored (prints the matching key)
jq -r --arg d "sha256-${DIGEST#sha256:}-" '.binaryData | keys[] | select(startswith($d))' \
  "$CR"/signature-configmap.json

# 3. Extract, resolving the canonical reference through the mirror
mkdir -p /data/ocp/installer/"$V"
oc adm release extract -a "$PS" --certificate-authority "$CA" \
  --idms-file "$CR"/idms-oc-mirror.yaml \
  --command=openshift-install-fips --to /data/ocp/installer/"$V" \
  quay.io/openshift-release-dev/ocp-release@"$DIGEST"

# 4. The installer reports exactly that release image
/data/ocp/installer/"$V"/openshift-install-fips version
```

Record the result for Phase 3 in `/data/ocp/installer/<version>/release.env`:

```bash
# /data/ocp/installer/4.22.18/release.env
OCP_RELEASE_VERSION=4.22.18
OCP_RELEASE_DIGEST=sha256:<digest>
OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release@sha256:<digest>
OCP_RELEASE_MIRROR=registry.example.gc.ca:8443/mirror/openshift/release-images
OCP_INSTALLER=/data/ocp/installer/4.22.18/openshift-install-fips
OCP_INSTALLER_SHA256=<output of: sha256sum openshift-install-fips>
OCP_IDMS_FILE=/data/ocp/cluster-resources/T-20261106-01/idms-oc-mirror.yaml
```

The installer must **run** on a RHEL 9 host in FIPS mode (the provisioner host, Phase 3); copy it
there with `release.env`.

## Publish the repository

Each transfer carries this repository as a Git bundle (`repo/ocp-itsg-33.bundle`). Publish it to
departmental Git (AD-12) only by **fast-forward**: the reviewed low-side history is the source of
truth (CM-3, CM-5), and high-side-only changes (for example, cluster overlays that reference
high-side names) go on a separate branch or repository.

```bash
ID=T-20261106-01
B=/data/ocp/transfers/"$ID"/repo/ocp-itsg-33.bundle
git bundle verify "$B"
git bundle list-heads "$B"         # the main head must be the commit on the transfer record

# First time only: clone departmental Git (or, if it is still empty, clone the bundle
# and point origin at departmental Git)
git clone https://git.example.gc.ca/platform/ocp-itsg-33.git /data/ocp/repo/ocp-itsg-33

cd /data/ocp/repo/ocp-itsg-33
git fetch "$B" refs/heads/main:refs/remotes/transfer/main
git checkout main
git merge --ff-only transfer/main  # refuses if the high-side branch has diverged: investigate
git tag "transfer/$ID" transfer/main
git push origin main "refs/tags/transfer/$ID"
```

Refuse to publish a transfer built from uncommitted changes, or whose bundle head doesn't match
the commit recorded for the transfer. Record `published` in the import log.

## Hand-off to Phase 3

| Item | Location |
|---|---|
| Release details and installer | `/data/ocp/installer/<version>/release.env`, `openshift-install-fips` |
| Mirror configuration for `install-config.yaml` | `/data/ocp/cluster-resources/current/idms-oc-mirror.yaml` |
| Pull secret for `install-config.yaml` | `~quay/.config/ocp-registry/cluster-pull-secret.json` (pull-only robot, mode `0600`) |
| Trust bundle for `install-config.yaml` | `/etc/pki/ocp-registry/ca-bundle.crt` |
| Cluster resources for Day 1 (catalogs, ITMS, signatures) | `/data/ocp/cluster-resources/current/` |
| `oc` and `butane` | `/data/ocp/tools/<version>/bin/` |
| Configuration repository | Departmental Git, tag `transfer/<ID>` |
