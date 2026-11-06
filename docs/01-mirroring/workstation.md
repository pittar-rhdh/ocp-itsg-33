# Mirror Workstation

[← Phase 1](index.md)

The mirror workstation is the only system in this design that talks to Red Hat. Treat it as
part of the platform's supply chain: harden it, restrict who can use it, and keep its records.

## Host build

| Requirement | Detail |
|---|---|
| Operating system | RHEL 9, registered, fully patched |
| FIPS mode | Enabled at installation (add `fips=1` to the installer boot options). Check with `fips-mode-setup --check`. Recommended for consistency with the high side; `02-check-workstation.sh` warns if it is off. |
| Hardening | Departmental RHEL baseline or the OpenSCAP profile used for the registry host (Phase 2) |
| Access | Named accounts only, MFA through the departmental bastion; members of the platform team |
| Network | Outbound HTTPS to `registry.redhat.io`, `quay.io`, `*.quay.io` CDN, `api.openshift.com`, `mirror.openshift.com`, `definitions.stackrox.io` and `install.stackrox.io` (RHACS data). No inbound access. |
| Packages | `jq`, `git`, `curl`, `gnupg2`, `tar` (all in the RHEL 9 base repositories) |
| umask | Red Hat lists `umask 0022` as a prerequisite on hosts that run oc-mirror. `05-mirror-to-disk.sh` sets it for its own run; credential files are still written `0600`. |
| Storage | Dedicated, encrypted (LUKS) filesystem mounted at `MIRROR_BASE` (default `/data/mirror`) |

## Storage sizing

`oc-mirror` keeps a **cache** of every blob it has downloaded, and writes **archives** that hold
the content for one transfer. On the first run, both are about the size of the full content set.

| Area | Default path | Rough size | Keep? |
|---|---|---|---|
| Cache | `/data/mirror/cache` | Grows with every z-stream and operator version mirrored | **Yes**, and back it up after every run. Losing it forces a full re-mirror. |
| Archive working directory | `/data/mirror/archive/working-dir` | Small (metadata, history) | **Yes.** It records what has already been mirrored, so later runs are incremental. |
| Archives (`mirror_*.tar`) | `/data/mirror/archive` | First run ≈ cache size; later runs only the delta | No; moved into the transfer package |
| Transfers | `/data/mirror/transfers` | Size of each package | Until the high side confirms the import; then keep only the records |
| Tools | `/data/mirror/tools` | About 1.2 GiB per OpenShift version | Until superseded |

> **Estimate before you buy disks.** Run `05-mirror-to-disk.sh --dry-run` and review
> `working-dir/dry-run/mapping.txt`. For the operator set in `versions.env`, plan for at least
> **500 GiB** and prefer **1 TiB**: the first import holds the cache and the archives at the same
> time. The minimum checked by `02-check-workstation.sh` is set by `MIRROR_MIN_FREE_GB`.

## Configure the workstation

Settings live in `01-mirror/settings.env`. Override them in `01-mirror/settings.local.env`
(git-ignored) or with exported environment variables. Precedence is: environment, then
`settings.local.env`, then the defaults; paths derived from `MIRROR_BASE` follow it
automatically. For example:

```bash
# 01-mirror/settings.local.env
MIRROR_BASE=/srv/mirror
REGISTRY_AUTH_FILE=/home/mirror-op/.secrets/pull-secret.json
TRANSFER_SIGNING_KEY=0123456789ABCDEF0123456789ABCDEF01234567
```

## Tools

```bash
01-mirror/01-download-tools.sh --install
```

The script downloads the tools for `OCP_MAX_VERSION` into `${MIRROR_BASE}/tools/<version>/`:

| Tool | Source | Verification |
|---|---|---|
| `oc`, `kubectl` | `openshift-client-linux-<arch>-rhel9-<version>.tar.gz` | Checksum list signed by Red Hat release key 2 (`199E2F91FD431D51`), checked with `gpgv` against `/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release` |
| `oc-mirror` (v2) | `oc-mirror.rhel9.tar.gz` from the same release | Same signed checksum list |
| mirror registry | `mirror-registry-<arch>.tar.gz` (`MIRROR_REGISTRY_VERSION`) | Checksum list signed by Red Hat release key 2 |
| `butane` | `openshift-v4/clients/butane/v<BUTANE_VERSION>/butane-<arch>` | **Unsigned** checksum list over TLS (same residual risk as `roxctl`) |
| `roxctl` | RHACS assets for `RHACS_VERSION` | **Unsigned** checksum list over TLS. Record this as a residual risk, or obtain `roxctl` another way: Red Hat's RHACS documentation states that the main image (for example, `registry.redhat.io/advanced-cluster-security/rhacs-main-rhel9:<version>`) includes `roxctl`. |

Use the **RHEL 9 builds** of `oc` and `oc-mirror`. Red Hat's oc-mirror prerequisites say to
install the binary that matches your RHEL version.
`--install` also puts `oc`, `kubectl`, and `oc-mirror` in `~/.local/bin`. The FIPS-capable
installer is **not** downloaded here: it is extracted from the mirrored release on the high side
(Phase 2), so it always matches the release in the mirror registry.

## Pull secret

`oc-mirror` needs a pull secret with credentials for `registry.redhat.io` and `quay.io`.

1. Download it from the Red Hat Hybrid Cloud Console (OpenShift → Downloads → Pull secret), using
   a **departmental (shared, role-based) Red Hat account** rather than a personal one, so access
   survives staff changes (AC-2).
2. Save it with mode `0600` at `REGISTRY_AUTH_FILE`. The default,
   `${XDG_RUNTIME_DIR}/containers/auth.json`, is on a `tmpfs` and disappears at logout; set
   `REGISTRY_AUTH_FILE` to a persistent, protected path instead.
3. Never commit it, and never put it in a transfer package. The high side gets its own
   credentials for the mirror registry in Phase 2.

## Transfer signing key

Each transfer's `SHA256SUMS` is signed with a GPG key that belongs to the **transfer role**, not
to an individual.

| Item | Guidance |
|---|---|
| Algorithm | RSA 3072 or 4096, or ECDSA P-384, with SHA-256 or stronger (ITSP.40.111) |
| Storage | A smart card or token if available; otherwise the workstation keyring, protected by a passphrase |
| Validity | One or two years, with a documented rotation and revocation procedure (SC-12) |
| Distribution | Export the **public** key and deliver it to the high side **out of band** (for example, on separate media, hand-carried), and confirm the fingerprint by a second channel. Never ship it inside a transfer. |

```bash
gpg --quick-gen-key "OCP Transfer <ocp-transfer@example.gc.ca>" rsa3072 sign 1y
gpg --list-secret-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}'   # → TRANSFER_SIGNING_KEY
gpg --armor --export <fingerprint> > ocp-transfer-key.pub.asc                 # → high side, out of band
```

## Readiness check

```bash
01-mirror/02-check-workstation.sh
```

It checks the OS and FIPS mode, the tools and the `oc` version, the pull secret, the Red Hat
release key, free space, connectivity to Red Hat endpoints, and the signing key. It exits
non-zero if any check fails.
