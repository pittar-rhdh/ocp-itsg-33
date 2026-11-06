# Mirror Workstation

[← Phase 1](index.md)

> **Examples only — not validated.** Test and adapt the commands before use. See
> [Validation status](../reference/validation-status.md).

The mirror workstation is the only system in this design that talks to Red Hat. Treat it as
part of the platform's supply chain: harden it, restrict who can use it, and keep its records.

## Host build

| Requirement | Detail |
|---|---|
| Operating system | RHEL 9, registered, fully patched |
| FIPS mode | Enabled at installation (add `fips=1` to the installer boot options). Recommended for consistency with the high side (AD-18). |
| Hardening | Departmental RHEL baseline or the OpenSCAP profile used for the registry host (Phase 2) |
| Access | Named accounts only, MFA through the departmental bastion; members of the platform team |
| Network | Outbound HTTPS to `registry.redhat.io`, `quay.io`, `*.quay.io` CDN, `api.openshift.com`, `mirror.openshift.com`, `definitions.stackrox.io` and `install.stackrox.io` (RHACS data). No inbound access. |
| Packages | `jq`, `git`, `curl`, `gnupg2`, `tar` (all in the RHEL 9 base repositories) |
| umask | Red Hat lists `umask 0022` as a prerequisite on hosts that run oc-mirror. Set it in the shell that runs `oc-mirror`; keep credential files at `0600`. |
| Storage | Dedicated, encrypted (LUKS) filesystem, for example mounted at `/data/mirror` |

## Storage sizing

`oc-mirror` keeps a **cache** of every blob it has downloaded, and writes **archives** that hold
the content for one transfer. On the first run, both are about the size of the full content set.

| Area | Example path | Rough size | Keep? |
|---|---|---|---|
| Cache | `/data/mirror/cache` | Grows with every z-stream and operator version mirrored | **Yes**, and back it up after every run. Losing it forces a full re-mirror. |
| Archive working directory | `/data/mirror/archive/working-dir` | Small (metadata, history) | **Yes.** It records what has already been mirrored, so later runs are incremental. |
| Archives (`mirror_*.tar`) | `/data/mirror/archive` | First run ≈ cache size; later runs only the delta | No; moved into the transfer package |
| Transfers | `/data/mirror/transfers` | Size of each package | Until the high side confirms the import; then keep only the records |
| Tools | `/data/mirror/tools/<version>` | About 1.2 GiB per OpenShift version | Until superseded |
| RHACS data | `/data/mirror/rhacs` | Hundreds of MiB per download | No; moved into the next transfer package |

```bash
sudo mkdir -p /data/mirror/{cache,archive,tools,rhacs,transfers}
sudo chown -R "$(id -un):" /data/mirror
```

> **Estimate before you buy disks.** Run a [dry run](mirror-to-disk.md#dry-run) and review
> `working-dir/dry-run/mapping.txt`. For the operator set in `01-mirror/imageset-config.yaml`,
> plan for at least **500 GiB** and prefer **1 TiB**: the first import holds the cache and the
> archives at the same time.

## Tools

Download the tools for the target release (`4.22.18` here; see
[Versions and pinned content](../reference/versions.md)) from `mirror.openshift.com`, and check
them against checksum lists before trusting them (SA-12, SI-7).

| Tool | Source | Verification |
|---|---|---|
| `oc`, `kubectl` | `openshift-client-linux-amd64-rhel9-<version>.tar.gz` | Checksum list signed by Red Hat release key 2 (`199E2F91FD431D51`), checked with `gpgv` against `/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release` |
| `oc-mirror` (v2) | `oc-mirror.rhel9.tar.gz` from the same release | Same signed checksum list |
| mirror registry | `mirror-registry-amd64.tar.gz` (version 2.0.9) | Checksum list signed by Red Hat release key 2 |
| `butane` | `butane-amd64` (version 0.29.0-1), used in Phase 3 | **Unsigned** checksum list over TLS (same residual risk as `roxctl`) |
| `roxctl` | RHACS assets for the RHACS version that is mirrored | **Unsigned** checksum list over TLS. Record this as a residual risk, or obtain `roxctl` another way: Red Hat's RHACS documentation states that the main image (for example, `registry.redhat.io/advanced-cluster-security/rhacs-main-rhel9:<version>`) includes `roxctl`. |

```bash
OCP_VERSION=4.22.18
mkdir -p /data/mirror/tools/${OCP_VERSION} && cd /data/mirror/tools/${OCP_VERSION}

# gpgv needs a binary keyring made from the Red Hat release key.
gpg --dearmor < /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release > /data/mirror/redhat-release.gpg

# oc, kubectl, oc-mirror: verify the signed checksum list, then the files.
BASE=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_VERSION}
curl -fsSL -o sha256sum.ocp-clients.txt.gpg "${BASE}/sha256sum.txt.gpg"
gpgv --keyring /data/mirror/redhat-release.gpg \
  --output sha256sum.ocp-clients.txt sha256sum.ocp-clients.txt.gpg    # must report "Good signature"
curl -fsSLO "${BASE}/openshift-client-linux-amd64-rhel9-${OCP_VERSION}.tar.gz"
curl -fsSLO "${BASE}/oc-mirror.rhel9.tar.gz"
sha256sum --check --ignore-missing sha256sum.ocp-clients.txt

# mirror registry
BASE=https://mirror.openshift.com/pub/cgw/mirror-registry/2.0.9
curl -fsSL -o sha256sum.mirror-registry.txt.gpg "${BASE}/sha256sum.txt.gpg"
gpgv --keyring /data/mirror/redhat-release.gpg \
  --output sha256sum.mirror-registry.txt sha256sum.mirror-registry.txt.gpg
curl -fsSLO "${BASE}/mirror-registry-amd64.tar.gz"
sha256sum --check --ignore-missing sha256sum.mirror-registry.txt

# butane (unsigned checksum list)
BASE=https://mirror.openshift.com/pub/openshift-v4/clients/butane/v0.29.0-1
curl -fsSL -o sha256sum.butane.txt "${BASE}/sha256sum.txt"
curl -fsSLO "${BASE}/butane-amd64"
sha256sum --check --ignore-missing sha256sum.butane.txt

# roxctl (unsigned checksum list)
BASE=https://mirror.openshift.com/pub/rhacs/assets/<rhacs-version>/bin/Linux
curl -fsSL -o sha256sum.rhacs.txt "${BASE}/sha256sum.txt"
curl -fsSLO "${BASE}/roxctl"
sha256sum --check --ignore-missing sha256sum.rhacs.txt
chmod 0755 butane-amd64 roxctl
```

Each `sha256sum --check` line must say `OK` for every file you downloaded. Keep the checksum
lists with the binaries: they travel in the transfer package as evidence.

Install the clients on the workstation:

```bash
mkdir -p ~/.local/bin
tar -xzf openshift-client-linux-amd64-rhel9-${OCP_VERSION}.tar.gz -C ~/.local/bin oc kubectl
tar -xzf oc-mirror.rhel9.tar.gz -C ~/.local/bin oc-mirror
chmod 0755 ~/.local/bin/oc ~/.local/bin/kubectl ~/.local/bin/oc-mirror
```

Use the **RHEL 9 builds** of `oc` and `oc-mirror`. Red Hat's oc-mirror prerequisites say to
install the binary that matches your RHEL version. The FIPS-capable installer is **not**
downloaded here: it is extracted from the mirrored release on the high side (Phase 2), so it
always matches the release in the mirror registry.

## Pull secret

`oc-mirror` needs a pull secret with credentials for `registry.redhat.io` and `quay.io`.

1. Download it from the Red Hat Hybrid Cloud Console (OpenShift → Downloads → Pull secret), using
   a **departmental (shared, role-based) Red Hat account** rather than a personal one, so access
   survives staff changes (AC-2).
2. Save it with mode `0600` at a persistent, protected path, for example
   `~/.secrets/pull-secret.json`, and pass it to `oc-mirror` with `--authfile`. (The default
   container auth file, `${XDG_RUNTIME_DIR}/containers/auth.json`, is on a `tmpfs` and disappears
   at logout.)
3. Never commit it, and never put it in a transfer package. The high side gets its own
   credentials for the mirror registry in Phase 2.

```bash
install -d -m 0700 ~/.secrets
install -m 0600 ~/Downloads/pull-secret.txt ~/.secrets/pull-secret.json
```

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
gpg --list-secret-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}'   # fingerprint
gpg --armor --export <fingerprint> > ocp-transfer-key.pub.asc                 # → high side, out of band
```

## Readiness check

Before the first mirror run (and after workstation changes), check:

```bash
cat /etc/redhat-release                    # Red Hat Enterprise Linux release 9.x
fips-mode-setup --check                    # FIPS mode is enabled
oc version --client                        # 4.22.x
oc-mirror --v2 --help > /dev/null && echo "oc-mirror v2 available"
stat -c '%a' ~/.secrets/pull-secret.json   # 600
jq -r '.auths | keys[]' ~/.secrets/pull-secret.json   # must include registry.redhat.io and quay.io
df -h /data/mirror                         # at least 500 GiB free
gpg --list-secret-keys <fingerprint>       # transfer signing key available

# Connectivity: any HTTP code (200, 30x, 401) is fine; 000 means no route.
for url in https://registry.redhat.io/v2/ https://quay.io/v2/ \
           https://api.openshift.com/api/upgrades_info/v1/graph https://mirror.openshift.com/pub/; do
  printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url")" "$url"
done
```

Resolve every failure before mirroring, or record it as an accepted deviation.
