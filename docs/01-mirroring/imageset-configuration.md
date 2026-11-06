# ImageSetConfiguration

[← Phase 1](index.md)

> **Examples only — not validated.** Confirm every package name, channel, and version against
> the live catalogs before use. See [Validation status](../reference/validation-status.md).

`oc-mirror` v2 mirrors what an `ImageSetConfiguration` (ISC) lists. In this design,
`01-mirror/imageset-config.yaml` is the **source of truth** for mirrored content, and it is
**committed**, so that:

- every change to mirrored content is a reviewable diff in a pull request (CM-3),
- the low side mirrors and the high side uploads with the same file (Phase 2 needs it for
  disk-to-mirror), and
- every transfer records the SHA-256 of the file it was built from.

The pinned versions it should agree with (OpenShift 4.22.18 in `stable-4.22`, and the RHACS
version) are listed in [Versions and pinned content](../reference/versions.md).

## What the file contains

| ISC field | Example value | Notes |
|---|---|---|
| `mirror.platform.channels` | `stable-4.22`, `minVersion`/`maxVersion` `4.22.18` | Every release between min and max in the channel. Keep the range small: each z-stream adds many GiB. |
| `mirror.platform.architectures` | `amd64` | This design is x86-64 only |
| `mirror.platform.graph` | `true` | Builds the graph-data image for OpenShift Update Service and generates an `UpdateService` manifest |
| `mirror.operators[0]` | `redhat-operator-index:v4.22` | Filtered catalog: only the listed packages |
| `mirror.operators[1]` | `certified-operator-index:v4.22` (commented out) | Vendor CSI driver (AD-13); add it when the vendor package is known |
| `mirror.additionalImages` | support tools, UBI | Must use a full registry hostname; prefer `@sha256` digests |
| `archiveSize` | commented out | Maximum size of each archive file, in GiB. Set it to fit your media (for example, `3` for FAT32 media, which has a 4 GiB file limit). |

## Operator entries

The examples below follow the filtering table in the Red Hat 4.22 documentation ("How filtering
works in the operator catalog"):

```yaml
packages:
  - name: compliance-operator            # head bundle of EVERY channel of the package
  - name: compliance-operator            # head of the stable channel
    channels:
      - name: stable
  - name: rhacs-operator                 # heads of two channels
    channels:
      - name: stable
      - name: rhacs-4.11
  - name: compliance-operator            # stable channel, from 1.7.0 up to the head
    channels:
      - name: stable
        minVersion: '1.7.0'
  - name: cluster-logging                # all channels, from 6.6.0 up to each head
    minVersion: '6.6.0'
  - name: rhacs-operator                 # a non-default channel: defaultChannel is required
    defaultChannel: stable
    channels:
      - name: rhacs-4.11
```

Rules from the Red Hat documentation:

- **Dependencies are not added for you.** oc-mirror v2 does not infer bundle or GVK
  dependencies; list every package an operator needs, with compatible versions (for example,
  `advanced-cluster-management` needs `multicluster-engine`).
- **Default channel.** If the listed channels don't include the package's default channel, set
  `defaultChannel`. Find the default channel with `oc-mirror list operators` (see
  [Choosing versions](#choosing-versions)).
- **`minVersion`** keeps every version from that version up to the channel head. Red Hat warns
  that version filters can produce a "multiple channel heads" error, because the filter can cut
  the operator's update graph; don't filter out the latest version, and widen the range if the
  error appears.
- Put `minVersion` under each channel when channels are listed, and at package level otherwise.
  Red Hat states that combining channel filters with a package-level `minVersion`/`maxVersion`
  is not allowed.
- Head-only mirroring is the smallest, but OLM on the high side can only upgrade along versions
  that are present. Once an operator is installed, set `minVersion` to the **installed version**
  so the next import contains a complete upgrade path.

## Choosing versions

List the latest OpenShift releases in the channel from the update graph, and the default
channel, channels, and versions of each package from the live catalog:

```bash
curl -fsSL -H 'Accept: application/json' \
  "https://api.openshift.com/api/upgrades_info/v1/graph?channel=stable-4.22&arch=amd64" \
  | jq -r '.nodes[].version' | sort -V | tail -15

export REGISTRY_AUTH_FILE=~/.secrets/pull-secret.json
oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.22 \
  --package=compliance-operator --v2 | tee -a catalog-report-$(date -u +%Y%m%d).txt
```

Repeat the last command for each package in the ISC (use
`registry.redhat.io/redhat/certified-operator-index:v4.22` for the CSI driver), and attach the
report to the pull request that changes `imageset-config.yaml`.

Choose:

1. **OpenShift:** the latest z-stream in `stable-4.22` that has no open blocking issues for your
   hardware, reviewed against the release notes and errata. Set `minVersion` and `maxVersion` to
   it for the first install.
2. **Operators:** for the first import, head of the default channel is usually right. Record any
   channel you pin and why (for example, a channel that matches the RHACS version you have
   tested).
3. **RHACS:** download `roxctl` and the offline vulnerability data for the same version as the
   `rhacs-operator` that will be installed.

## Review checklist for the pull request

- [ ] `imageset-config.yaml` agrees with [Versions and pinned content](../reference/versions.md)
- [ ] The catalog report is attached
- [ ] New operators or images have an owner and a reason (CM-11); remove anything no longer used
- [ ] Release notes and security errata for the new OpenShift version have been reviewed (SI-5)
- [ ] `minVersion` is set for operators that are already installed on the high side
- [ ] `archiveSize` (if set) fits the transfer media
- [ ] A [dry run](mirror-to-disk.md#dry-run) produced the expected image list and size

## After mirroring: the pinned ISC

The OpenShift 4.22 release notes state that oc-mirror v2 pins **operator catalog images** by
digest in the image set configuration, so the same catalog is always used even if the upstream
tag moves. In testing with oc-mirror 4.22, each run wrote `working-dir/isc_pinned_<time>.yaml`
and a matching delete configuration `disc_pinned_<time>.yaml` (these file names are an observed
detail, not documented ones). Copy them into the transfer's `config/` directory (see
[Packaging and transfer](packaging-and-transfer.md#package-layout)). They record which catalog
digests a transfer was built from (CM-8, SA-12); the full list of images is in the oc-mirror log,
which is also in the package. The delete configuration is a starting point for pruning old
content from the mirror registry later (Phase 6).
