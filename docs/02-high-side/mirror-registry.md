# Mirror Registry

[← Phase 2](index.md)

The **mirror registry for Red Hat OpenShift** is a small, single-host Red Hat Quay with a local
SQLite database and local storage. It is included with OpenShift subscriptions and is supported
for hosting the content needed to install and run a disconnected cluster: release images and
Red Hat operator content (AD-10).

Its limits shape how it is used here:

- It is **not highly available**. Running pods keep running if it is down, but anything that
  needs an image a node doesn't already have fails: pods rescheduled to another node, node
  replacement, scaling, upgrades, and operator installs. Back it up, and monitor it.
- It is **not for application images**. Tenant images belong in a departmental registry (AD-20).
- Red Hat discourages using one mirror registry for **more than one cluster**. If the platform
  grows, use this cluster to host a production registry (for example, Red Hat Quay) for the rest.

## Install

Run as the registry service account (see [Registry host](registry-host.md#service-account)):

```bash
sudo -iu quay
install -d -m 0700 ~/.config/ocp-registry
( umask 077; openssl rand -base64 24 | tr -d '/+=' > ~/.config/ocp-registry/quayadmin.password )
02-high-side/03-install-mirror-registry.sh
```

The script:

1. Re-checks the certificate (`02-check-registry-host.sh --tls-only`).
2. Extracts `mirror-registry-<arch>.tar.gz` (version `MIRROR_REGISTRY_VERSION`) from the accepted
   tools and runs:

   ```bash
   ./mirror-registry install \
     --quayHostname <REGISTRY_FQDN>:8443 \
     --quayRoot /data/quay/install --quayStorage /data/quay/storage --sqliteStorage /data/quay/sqlite \
     --sslCert <TLS_CERT> --sslKey <TLS_KEY> \
     --initUser quayadmin --initPassword <from file>
   ```

3. Masks the password in the saved log, trusts the CA for rootless Podman
   (`~/.config/containers/certs.d/<host>:8443/ca.crt`), and runs the hardening script.

The registry runs as three user-level systemd services: `quay-pod`, `quay-redis`, and `quay-app`
(`systemctl --user status quay-app`). Logs: `journalctl --user -u quay-app` or
`journalctl CONTAINER_NAME=quay-app`.

> The installer takes the administrator password as a command-line argument, so it is visible in
> the process list while the installer runs. Install when no other users are logged in to the
> host.

## Hardening

The installer's defaults suit a lab. `04-harden-mirror-registry.sh` changes the registry's
`config.yaml` and checks the running service:

| Setting | Default | Hardened | Why |
|---|---|---|---|
| `FEATURE_USER_CREATION` | `true` | `false` | Anyone who can reach the UI could create an account (AC-2) |
| `FEATURE_ANONYMOUS_ACCESS` | `true` | `false` | Every pull must be authenticated (AC-3, AC-14) |
| `FEATURE_REPO_MIRROR` | `true` | `false` | Pull-based repository mirroring has no use on an air-gapped host (CM-7) |
| `SUPER_USERS` | `[admin]` | `[quayadmin]` | The default names an account that doesn't exist; with sign-up enabled, whoever registered `admin` would become a superuser (AC-6) |
| `SSL_PROTOCOLS` | not set | `[TLSv1.2, TLSv1.3]` | Explicit protocol floor (SC-8, ITSP.40.062) |

After changing anything it restarts `quay-app`, then verifies that:

- `/health/instance` answers over TLS validated against `TLS_CA_BUNDLE`,
- an anonymous request to `/v2/_catalog` returns `401`,
- TLS 1.2 and TLS 1.3 handshakes succeed with certificate verification.

```bash
02-high-side/04-harden-mirror-registry.sh            # apply (idempotent)
02-high-side/04-harden-mirror-registry.sh --check    # report drift only; exit 1 on drift
```

Each run appends the SHA-256 of `config.yaml` and `ssl.cert` to `/data/quay/hardening.log`, and
backups go to `/data/quay/config-backups/`. Run `--check` monthly and after any upgrade (CM-6).

Test what the script can't: scan `https://<REGISTRY_FQDN>:8443` with the departmental TLS scanner
to confirm that TLS 1.0/1.1 and weak cipher suites are refused (CA-2). A FIPS-mode client can't
attempt those protocols, so it can't prove the server refuses them.

## Access model

| Identity | Type | Rights | Used by | Credential |
|---|---|---|---|---|
| `quayadmin` | User, superuser | Everything | Break-glass and one-off administration only | Password sealed in the departmental vault (AC-2, AC-6(9)) |
| `mirror+importer` | Robot | Member of team `importers` (role **creator**): create and push repositories in `mirror` | `06-disk-to-mirror.sh` | `IMPORTER_AUTH_FILE` on the registry host only |
| `mirror+cluster_pull` | Robot | **Read** on every repository in `mirror` | The OpenShift cluster (install-time pull secret) | `CLUSTER_PULL_SECRET_FILE` → `install-config.yaml` |

All mirrored content lives in a single organization (`MIRROR_NAMESPACE`, default `mirror`), so one
default permission covers every repository oc-mirror creates. Day-to-day work happens under named
OS accounts on the registry host (`sudo -iu quay`), which attributes registry actions to people
through auditd.

> Red Hat's documentation warns against giving the cluster a pull secret with push access: every
> node would get write access to the mirror. The cluster only ever gets `cluster_pull`.

### Set it up

One-time steps in the web UI (`https://<REGISTRY_FQDN>:8443`), signed in as `quayadmin`:

1. Create the organization **`mirror`**.
2. In it, open **Applications**, create an application (for example, `ocp-setup`), and generate
   an access token with the **Administer Organization** and **Administer Repositories** scopes.
3. Save the token to `QUAY_OAUTH_TOKEN_FILE` with mode `0600`.

Then:

```bash
02-high-side/05-configure-registry-access.sh
```

It creates the two robots and the `importers` team, adds a default permission that gives
`cluster_pull` read on new repositories, grants read on any existing ones, writes both credential
files (mode `0600`), and checks each credential against the registry. It is safe to re-run.

When it succeeds, **delete the token** in the UI (or the whole application) and remove the token
file. Create a new one only when the script is needed again.

> `05-configure-registry-access.sh` follows the Red Hat Quay API documentation. It has been tested
> only against a mock of that API, not against a live mirror registry. Check the result in the UI
> (organization → Robot accounts, Teams, Default permissions) the first time you run it.

### Rotate robot tokens

```bash
02-high-side/05-configure-registry-access.sh --rotate cluster_pull   # or: --rotate importer
```

Rotating `cluster_pull` invalidates the cluster's pull secret. Update the cluster's global pull
secret immediately afterwards (Phase 6 SOP). Rotate on the departmental schedule, and whenever
someone with access to the files leaves (IA-5).

## Certificate rotation

```bash
# Put the renewed certificate and key at TLS_CERT and TLS_KEY, then:
02-high-side/02-check-registry-host.sh --tls-only
02-high-side/04-harden-mirror-registry.sh --rotate-cert
```

The script checks the new certificate, backs up the old one, installs the new one as `ssl.cert` /
`ssl.key`, restarts the registry, and verifies TLS. If the **issuing CA** changes, update the
cluster's trust bundle **before** rotating (Phase 6 SOP), or nodes will stop pulling.

## Upgrades

Upgrade the mirror registry when a new version arrives in a transfer (change
`MIRROR_REGISTRY_VERSION` in `versions.env` on the low side):

```bash
02-high-side/03-install-mirror-registry.sh --upgrade
```

This runs `mirror-registry upgrade` with the same paths and certificate, then re-applies and
verifies the hardening. Back up `/data/quay` first.

## Backup and restore

| What | How | Frequency |
|---|---|---|
| `/data/quay/install`, `/data/quay/sqlite` | Stop `quay-app` (`systemctl --user stop quay-app`), copy, start | Weekly and before upgrades |
| `/data/quay/storage` | Filesystem or block snapshot, taken together with the database | Weekly |
| `/data/ocp` (cache, cluster resources, ledger) | File backup | After every import |

If the registry can't be restored, it can be rebuilt: reinstall, re-run access setup, and
re-import from the low side (a full mirror with `--since` set before the first transfer). Plan
for the time this takes in the contingency plan (CP-2, CP-10).

## Troubleshooting

| Symptom | Check |
|---|---|
| Install fails at SSH | `sshd` must accept key login for `quay` from `localhost`; see [Service account](registry-host.md#service-account) |
| Install fails at the certificate | Run `02-check-registry-host.sh --tls-only`; the SAN must match `REGISTRY_FQDN` |
| `quay-app` restarts in a loop | `journalctl --user -u quay-app -n 200`; a typo in `config.yaml` is the usual cause; restore from `/data/quay/config-backups/` |
| Rootless networking errors after a RHEL update (`pasta failed`) | Red Hat documents setting `default_rootless_network_cmd = "slirp4netns"` in `~/.config/containers/containers.conf` |
| `x509: certificate signed by unknown authority` from oc-mirror | `~/.config/containers/certs.d/<host>:8443/ca.crt` missing; any script in this phase re-creates it |
| `unauthorized` when pushing | `importer` isn't in the `importers` team, or its token was rotated; re-run `05-configure-registry-access.sh` |
