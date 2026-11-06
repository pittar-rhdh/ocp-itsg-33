# Mirror Registry

[← Phase 2](index.md)

> **Examples only — not validated.** The commands and configuration on this page are examples.
> Test and adapt them before use. See [Validation status](../reference/validation-status.md).

The **mirror registry for Red Hat OpenShift** is a small, single-host Red Hat Quay with a local
SQLite database and local storage. It is included with OpenShift subscriptions and is supported
for hosting the content needed to install and run a disconnected cluster: release images and
Red Hat operator content (AD-10). The version is pinned in
[Versions and pinned content](../reference/versions.md) (2.0.9 at the time of writing).

Its limits shape how it is used here:

- It is **not highly available**. Running pods keep running if it is down, but anything that
  needs an image a node doesn't already have fails: pods rescheduled to another node, node
  replacement, scaling, upgrades, and operator installs. Back it up, and monitor it.
- It is **not for application images**. Tenant images belong in a departmental registry (AD-20).
- Red Hat discourages using one mirror registry for **more than one cluster**. If the platform
  grows, use this cluster to host a production registry (for example, Red Hat Quay) for the rest.

## Install

Run as the registry service account, rootless (AD-21; see
[Registry host](registry-host.md#service-account)), after the
[readiness checks](registry-host.md#readiness-checks) pass:

```bash
sudo -iu quay
V=4.22.18
mkdir -p /data/quay/installer-2.0.9 /data/quay/install /data/quay/storage /data/quay/sqlite
chmod 0750 /data/quay /data/quay/install
tar -xzf /data/ocp/tools/"$V"/mirror-registry-amd64.tar.gz -C /data/quay/installer-2.0.9
cd /data/quay/installer-2.0.9

# Break-glass administrator password: 12+ characters, no whitespace. Seal a copy in the
# departmental vault.
install -d -m 0700 ~/.config/ocp-registry
( umask 077; openssl rand -base64 24 | tr -d '/+=' > ~/.config/ocp-registry/quayadmin.password )

./mirror-registry install \
  --quayHostname registry.example.gc.ca:8443 \
  --quayRoot /data/quay/install \
  --quayStorage /data/quay/storage \
  --sqliteStorage /data/quay/sqlite \
  --sslCert /etc/pki/ocp-registry/registry.crt \
  --sslKey /etc/pki/ocp-registry/registry.key \
  --initUser quayadmin \
  --initPassword "$(cat ~/.config/ocp-registry/quayadmin.password)" \
  --no-color
```

> The installer takes the administrator password as a command-line argument, so it is visible in
> the process list while the installer runs. Install when no other users are logged in to the
> host, and don't keep the installer output where others can read it.

The installer uses Ansible over SSH to `localhost` with a key it generates
(`~/.ssh/quay_installer`). The registry then runs as user-level systemd services `quay-pod`,
`quay-redis`, and `quay-app`:

```bash
systemctl --user status quay-pod quay-redis quay-app
journalctl --user -u quay-app -n 100        # or: journalctl CONTAINER_NAME=quay-app
```

### Trust the registry CA

Clients validate the departmental certificate. For rootless Podman, `skopeo`, and `oc-mirror`
under the `quay` account:

```bash
mkdir -p ~/.config/containers/certs.d/registry.example.gc.ca:8443
install -m 0644 /etc/pki/ocp-registry/ca-bundle.crt \
  ~/.config/containers/certs.d/registry.example.gc.ca:8443/ca.crt
```

`oc` uses the system trust store, or `--certificate-authority` per command (as on
[Populate the registry](populate-registry.md#extract-the-installer)). If the departmental CA isn't
already trusted host-wide:

```bash
sudo cp /etc/pki/ocp-registry/ca-bundle.crt /etc/pki/ca-trust/source/anchors/ocp-registry-ca.crt
sudo update-ca-trust extract
```

## Hardening

The installer's defaults suit a lab. Change these top-level keys in
`/data/quay/install/quay-config/config.yaml` (keep a dated copy first):

| Setting | Default | Hardened | Why |
|---|---|---|---|
| `FEATURE_USER_CREATION` | `true` | `false` | Anyone who can reach the UI could create an account (AC-2) |
| `FEATURE_ANONYMOUS_ACCESS` | `true` | `false` | Every pull must be authenticated (AC-3, AC-14) |
| `FEATURE_REPO_MIRROR` | `true` | `false` | Pull-based repository mirroring has no use on an air-gapped host (CM-7) |
| `SUPER_USERS` | `[admin]` | `[quayadmin]` | The default names an account that doesn't exist; with sign-up enabled, whoever registered `admin` would become a superuser (AC-6) |
| `SSL_PROTOCOLS` | not set | `[TLSv1.2, TLSv1.3]` | Explicit protocol floor (SC-8, ITSP.40.062) |

After editing, those keys read (replace the existing lines; don't add duplicates):

```yaml
# /data/quay/install/quay-config/config.yaml (excerpt)
FEATURE_ANONYMOUS_ACCESS: false
FEATURE_REPO_MIRROR: false
FEATURE_USER_CREATION: false
SSL_PROTOCOLS: [TLSv1.2, TLSv1.3]
SUPER_USERS:
  - quayadmin
```

```bash
cd /data/quay/install/quay-config
mkdir -p /data/quay/config-backups
cp -p config.yaml /data/quay/config-backups/config.yaml."$(date -u +%Y%m%dT%H%M%SZ)"
vi config.yaml
systemctl --user restart quay-app

# Verify
CA=/etc/pki/ocp-registry/ca-bundle.crt
curl -s -o /dev/null -w '%{http_code}\n' --cacert "$CA" \
  https://registry.example.gc.ca:8443/health/instance          # 200 (may take a minute)
curl -s -o /dev/null -w '%{http_code}\n' --cacert "$CA" \
  https://registry.example.gc.ca:8443/v2/_catalog              # 401: anonymous access refused
for p in tls1_2 tls1_3; do
  openssl s_client -connect registry.example.gc.ca:8443 -servername registry.example.gc.ca \
    -"$p" -CAfile "$CA" -verify_return_error </dev/null >/dev/null 2>&1 && echo "$p OK"
done

# Record what was verified (CM-6 evidence)
sha256sum config.yaml ssl.cert | tee -a /data/quay/hardening.log
```

Re-check these settings after every upgrade and monthly (`grep -E` the keys above, and compare
the digest with `/data/quay/hardening.log`).

Test what the commands above can't: scan `https://registry.example.gc.ca:8443` with the
departmental TLS scanner to confirm that TLS 1.0/1.1 and weak cipher suites are refused (CA-2). A
FIPS-mode client can't attempt those protocols, so it can't prove the server refuses them.

## Access model

| Identity | Type | Rights | Used by | Credential |
|---|---|---|---|---|
| `quayadmin` | User, superuser | Everything | Break-glass and one-off administration only | Password sealed in the departmental vault (AC-2, AC-6(9)) |
| `mirror+importer` | Robot | Member of team `importers` (role **creator**): create and push repositories in `mirror` | `oc-mirror` disk to mirror | `~quay/.config/ocp-registry/importer-auth.json`, on the registry host only |
| `mirror+cluster_pull` | Robot | **Read** on every repository in `mirror` | The OpenShift cluster (install-time pull secret) | `~quay/.config/ocp-registry/cluster-pull-secret.json` → `install-config.yaml` |

All mirrored content lives in a single organization, `mirror`, so one default permission covers
every repository oc-mirror creates. Day-to-day work happens under named OS accounts on the
registry host (`sudo -iu quay`), which attributes registry actions to people through auditd.

> Red Hat's documentation warns against giving the cluster a pull secret with push access: every
> node would get write access to the mirror. The cluster only ever gets `cluster_pull`.

### Set it up

In the web UI (`https://registry.example.gc.ca:8443`), signed in as `quayadmin`:

1. Create the organization **`mirror`**.
2. In it, open **Applications**, create an application (for example, `ocp-setup`), and generate
   an access token with the **Administer Organization** and **Administer Repositories** scopes.
3. Save the token to `~/.config/ocp-registry/oauth.token` with mode `0600`.

Then create the robots, team, and default permission. You can do the same in the UI
(organization → **Robot accounts**, **Teams**, **Default permissions**); with the Quay API:

```bash
API=https://registry.example.gc.ca:8443/api/v1
CA=/etc/pki/ocp-registry/ca-bundle.crt
# Keep the token out of the process list: curl reads the header from a file.
( umask 077; printf 'Authorization: Bearer %s\n' "$(cat ~/.config/ocp-registry/oauth.token)" \
    > ~/.config/ocp-registry/auth.hdr )
quay_api() { curl -sS --cacert "$CA" -H @"$HOME/.config/ocp-registry/auth.hdr" \
               -H 'Content-Type: application/json' "$@"; }

# Robots (the response includes the robot token)
quay_api -X PUT "$API/organization/mirror/robots/importer" \
  --data '{"description":"oc-mirror disk-to-mirror on the registry host; push only"}'
quay_api -X PUT "$API/organization/mirror/robots/cluster_pull" \
  --data '{"description":"OpenShift cluster pull secret; read only"}'

# Team "importers" (role creator) containing the importer robot
quay_api -X PUT "$API/organization/mirror/team/importers" \
  --data '{"role":"creator","description":"Robots that import mirrored content"}'
quay_api -X PUT "$API/organization/mirror/team/importers/members/mirror+importer"

# Default permission: cluster_pull can read every new repository in the organization
quay_api -X POST "$API/organization/mirror/prototypes" \
  --data '{"role":"read","delegate":{"name":"mirror+cluster_pull","kind":"user"}}'
```

The default permission applies to repositories created **after** it exists. If any repositories
already existed, grant read on each one:

```bash
quay_api "$API/repository?namespace=mirror" | jq -r '.repositories[].name'
quay_api -X PUT "$API/repository/mirror/<repository>/permissions/user/mirror+cluster_pull" \
  --data '{"role":"read"}'
```

Write the credential files. `podman login` checks each credential against the registry as it
writes the file:

```bash
umask 077
quay_api "$API/organization/mirror/robots/importer" | jq -r .token |
  podman login --authfile ~/.config/ocp-registry/importer-auth.json \
    --username 'mirror+importer' --password-stdin registry.example.gc.ca:8443
quay_api "$API/organization/mirror/robots/cluster_pull" | jq -r .token |
  podman login --authfile ~/.config/ocp-registry/cluster-pull-secret.json \
    --username 'mirror+cluster_pull' --password-stdin registry.example.gc.ca:8443
```

When this is done, **delete the token** in the UI (or the whole application) and remove
`oauth.token` and `auth.hdr`. Create a new token only when needed again. Check the result in the
UI (organization → Robot accounts, Teams, Default permissions) the first time.

### Rotate robot tokens

Regenerate a robot token (UI: robot account → **Regenerate token**, or
`quay_api -X POST "$API/organization/mirror/robots/<robot>/regenerate"`), then rewrite its
credential file with `podman login` as above.

Rotating `cluster_pull` invalidates the cluster's pull secret. Update the cluster's global pull
secret immediately afterwards ([Registry robot token rotation](../06-sops/access-management.md#registry-robot-token-rotation)). Rotate on the departmental schedule, and whenever
someone with access to the files leaves (IA-5).

## Certificate rotation

Check the renewed certificate (see [TLS certificate](registry-host.md#tls-certificate) and the
certificate checks in [Readiness checks](registry-host.md#readiness-checks)), then:

```bash
cd /data/quay/install/quay-config
cp -p ssl.cert /data/quay/config-backups/ssl.cert."$(date -u +%Y%m%dT%H%M%SZ)"
install -m 0640 /etc/pki/ocp-registry/registry.crt ssl.cert
install -m 0600 /etc/pki/ocp-registry/registry.key ssl.key
systemctl --user restart quay-app
```

Then repeat the verification commands from [Hardening](#hardening). If the **issuing CA** changes,
update the cluster's trust bundle **before** rotating ([Certificate rotation](../06-sops/certificate-rotation.md#update-the-cluster-trust-bundle)), or nodes will stop pulling.

## Upgrades

When a new mirror registry version arrives in a transfer, back up `/data/quay` (see below), then
run the new installer with the same paths and certificate:

```bash
mkdir -p /data/quay/installer-<new-version>
tar -xzf /data/ocp/tools/<version>/mirror-registry-amd64.tar.gz -C /data/quay/installer-<new-version>
cd /data/quay/installer-<new-version>
./mirror-registry upgrade \
  --quayHostname registry.example.gc.ca:8443 \
  --quayRoot /data/quay/install \
  --quayStorage /data/quay/storage \
  --sqliteStorage /data/quay/sqlite \
  --sslCert /etc/pki/ocp-registry/registry.crt \
  --sslKey /etc/pki/ocp-registry/registry.key \
  --no-color
```

Then re-check the [hardening](#hardening) settings: an upgrade can rewrite `config.yaml`.

## Backup and restore

| What | How | Frequency |
|---|---|---|
| `/data/quay/install`, `/data/quay/sqlite` | Stop `quay-app` (`systemctl --user stop quay-app`), copy, start | Weekly and before upgrades |
| `/data/quay/storage` | Filesystem or block snapshot, taken together with the database | Weekly |
| `/data/ocp` (cache, cluster resources, import log) | File backup | After every import |

If the registry can't be restored, it can be rebuilt: reinstall, repeat the access setup, and
re-import from the low side (a full mirror with `--since` set before the first transfer). Plan
for the time this takes in the contingency plan (CP-2, CP-10).

## Troubleshooting

| Symptom | Check |
|---|---|
| Install fails at SSH | `sshd` must accept key login for `quay` from `localhost`; see [Service account](registry-host.md#service-account) |
| Install fails at the certificate | Repeat the certificate checks in [Readiness checks](registry-host.md#readiness-checks); the SAN must match `registry.example.gc.ca` |
| `quay-app` restarts in a loop | `journalctl --user -u quay-app -n 200`; a typo in `config.yaml` is the usual cause; restore from `/data/quay/config-backups/` |
| Rootless networking errors after a RHEL update (`pasta failed`) | Red Hat documents setting `default_rootless_network_cmd = "slirp4netns"` in the `[network]` section of `~/.config/containers/containers.conf`, then `podman system migrate` |
| `x509: certificate signed by unknown authority` from oc-mirror | `~/.config/containers/certs.d/registry.example.gc.ca:8443/ca.crt` missing; see [Trust the registry CA](#trust-the-registry-ca) |
| `unauthorized` when pushing | `importer` isn't in the `importers` team, or its token was rotated and `importer-auth.json` not rewritten |
