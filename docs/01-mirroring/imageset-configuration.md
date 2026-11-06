# ImageSetConfiguration

[← Phase 1](index.md)

`oc-mirror` v2 mirrors what an `ImageSetConfiguration` (ISC) lists. In this repository, the ISC
is **generated** from `versions.env` and **committed**, so that:

- every change to mirrored content is a reviewable diff in a pull request (CM-3),
- the low side mirrors and the high side uploads with the same file (Phase 2 needs it for
  disk-to-mirror), and
- `05-mirror-to-disk.sh` refuses to run if the committed file doesn't match `versions.env`.

```bash
vi versions.env
01-mirror/04-render-imageset-config.sh          # writes 01-mirror/imageset-config.yaml
01-mirror/04-render-imageset-config.sh --check  # what CI and 05-mirror-to-disk.sh run
```

## What gets rendered

| `versions.env` | ISC field | Notes |
|---|---|---|
| `OCP_CHANNEL`, `OCP_MIN_VERSION`, `OCP_MAX_VERSION` | `mirror.platform.channels` | Every release between min and max in the channel. Keep the range small: each z-stream adds many GiB. |
| `OCP_ARCH` | `mirror.platform.architectures` | `amd64` for this design |
| `OCP_MIRROR_GRAPH` | `mirror.platform.graph` | `true` builds the graph-data image for OpenShift Update Service and generates an `UpdateService` manifest |
| `OPERATORS` | `mirror.operators[0]` (Red Hat catalog) | Filtered catalog: only the listed packages |
| `CSI_OPERATORS` | `mirror.operators[1]` (certified catalog) | Only rendered when not empty |
| `ADDITIONAL_IMAGES` | `mirror.additionalImages` | Must use a full registry hostname |
| `MIRROR_ARCHIVE_SIZE_GB` | `archiveSize` | Maximum size of each archive file. Set it to fit your media (for example, `3` for FAT32 media, which has a 4 GiB file limit). |

The render script refuses obviously wrong input: versions outside `OCP_MINOR`, a minimum above
the maximum, or an additional image without a registry hostname.

## Operator entries

Each entry in `OPERATORS` is `package|channels|minVersion|defaultChannel` (the last fields are
optional). The results below follow the filtering table in the Red Hat 4.22 documentation
("How filtering works in the operator catalog"):

```bash
OPERATORS=(
  "compliance-operator||"                     # head bundle of EVERY channel of the package
  "compliance-operator|stable|"               # head of the stable channel
  "rhacs-operator|stable,rhacs-4.11|"         # heads of two channels
  "compliance-operator|stable|1.7.0"          # stable channel, from 1.7.0 up to the head
  "cluster-logging||6.6.0"                    # all channels, from 6.6.0 up to each head
  "rhacs-operator|rhacs-4.11||stable"         # a non-default channel: defaultChannel is required
)
```

Rules from the Red Hat documentation:

- **Dependencies are not added for you.** oc-mirror v2 does not infer bundle or GVK
  dependencies; list every package an operator needs, with compatible versions.
- **Default channel.** If the listed channels don't include the package's default channel, set
  `defaultChannel` (fourth field). Find the default channel with `03-list-operator-channels.sh`.
- **`minVersion`** keeps every version from that version up to the channel head. Red Hat warns
  that version filters can produce a "multiple channel heads" error, because the filter can cut
  the operator's update graph; don't filter out the latest version, and widen the range if the
  error appears.
- The render script puts `minVersion` under each channel when channels are listed, and at
  package level otherwise. Red Hat states that combining channel filters with a package-level
  `minVersion`/`maxVersion` is not allowed, so the script never generates it. `maxVersion` is not
  supported by the script.
- Head-only mirroring is the smallest, but OLM on the high side can only upgrade along versions
  that are present. Once an operator is installed, set `minVersion` to the **installed version**
  so the next import contains a complete upgrade path.

## Choosing versions

```bash
01-mirror/03-list-operator-channels.sh                       # every configured package
01-mirror/03-list-operator-channels.sh compliance-operator   # one package
```

The report (saved under `${MIRROR_REPORTS_DIR}`) lists the latest releases in `OCP_CHANNEL` from
the update graph, and the default channel, channels, and versions of each package from
`oc mirror list operators --v2`. Attach it to the pull request that changes `versions.env`.

Choose:

1. **OpenShift:** the latest z-stream in `stable-4.22` that has no open blocking issues for your
   hardware, reviewed against the release notes and errata. Set `OCP_MIN_VERSION` and
   `OCP_MAX_VERSION` to it for the first install.
2. **Operators:** for the first import, head of the default channel is usually right. Record any
   channel you pin and why (for example, a channel that matches the RHACS version you have
   tested).
3. **RHACS:** set `RHACS_VERSION` to the operator version that will be installed, so `roxctl`
   and the offline vulnerability data match it.

## Review checklist for the pull request

- [ ] `imageset-config.yaml` was regenerated and `--check` passes
- [ ] The catalog report is attached
- [ ] New operators or images have an owner and a reason (CM-11); remove anything no longer used
- [ ] Release notes and security errata for the new OpenShift version have been reviewed (SI-5)
- [ ] `minVersion` is set for operators that are already installed on the high side
- [ ] `MIRROR_ARCHIVE_SIZE_GB` fits the transfer media

## After mirroring: the pinned ISC

The OpenShift 4.22 release notes state that oc-mirror v2 pins **operator catalog images** by
digest in the image set configuration, so the same catalog is always used even if the upstream
tag moves. In testing with oc-mirror 4.22, each run wrote `working-dir/isc_pinned_<time>.yaml`
and a matching delete configuration `disc_pinned_<time>.yaml` (these file names are an observed
detail, not documented ones). The packaging script copies them into the transfer's `config/`
directory when present. They record which catalog digests a transfer was built from (CM-8,
SA-12); the full list of images is in the oc-mirror log, which is also in the package. The
delete configuration is a starting point for pruning old content from the mirror registry later (Phase 6).
