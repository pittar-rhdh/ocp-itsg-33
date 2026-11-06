# Registry Host

[← Phase 2](index.md)

> **Examples only — not validated.** The commands and configuration on this page are examples.
> Test and adapt them before use. See [Validation status](../reference/validation-status.md).

The registry host serves every image the cluster runs. If it is compromised, everything that
pulls from it is compromised, so build it as a security-relevant platform component, not as a
utility server.

## Sizing

| Resource | Minimum | Recommended | Notes |
|---|---|---|---|
| CPU | 2 vCPU / cores | 4 | The mirror registry requires 2 or more |
| Memory | 8 GiB | 16 GiB | The mirror registry requires 8 GiB |
| OS disk | 50 GiB | 100 GiB | Separate from registry data |
| Registry data (`/data`) | 1 TiB | 2 TiB | Red Hat suggests up to 1 TB per release stream. This design also keeps the oc-mirror cache, workspace, and accepted transfers on the same host; plan for growth with every monthly import and prune with the Phase 6 SOP. |

Physical or virtual is a departmental choice. If virtual, the hypervisor is in scope for the
same zone (MRZ) and the same SA&A.

## Operating system

| Requirement | How |
|---|---|
| RHEL 9, minimal install | No GUI. Install `podman`, `openssl`, `jq`, `git`, `tar`, `gnupg2`, `firewalld`, `audit`, `chrony`, `rsyslog`. |
| FIPS mode | Enabled at installation (`fips=1` on the installer boot line). Check: `fips-mode-setup --check` and `cat /proc/sys/crypto/fips_enabled` = `1` (SC-13). |
| SELinux enforcing | Default; never disable (AC-3, AC-6). The installer sets the labels it needs. |
| Disk encryption | LUKS for `/data` (and the OS disk where policy requires), with keys bound to TPM2 or Tang (SC-28) |
| Patching | From the departmental high-side RHEL content source (see [Supporting services](#supporting-services-checklist)) on the monthly cycle (SI-2) |
| Hardening baseline | The departmental RHEL 9 baseline, or a SCAP Security Guide profile (see below) |
| umask | Red Hat lists `umask 0022` as a prerequisite on hosts that run oc-mirror. Set it in the shell that runs `oc-mirror` (see [Populate the registry](populate-registry.md#disk-to-mirror)); a baseline that enforces a stricter login umask is fine. |

### Hardening with OpenSCAP

```bash
sudo dnf install -y openscap-scanner scap-security-guide
oscap info /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml | grep -i 'profile'
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --results /var/tmp/registry-host-arf.xml --report /var/tmp/registry-host-report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

- Choose the profile your department mandates (CIS Server Level 1/2, DISA STIG, or a tailored
  departmental profile). Keep the ARF results as CM-6 evidence; re-scan after every change and on
  a schedule (CA-7).
- **Test the profile against rootless Podman before applying remediations.** Some rules in
  stricter profiles (for example, limits on user namespaces, `noexec` on `/home`, or SSH
  restrictions for local logins) can stop the mirror registry from running or installing.
  Tailor those rules with a documented rationale rather than weakening the registry setup.

## Service account

The registry runs **rootless** (AD-21) under a dedicated, unprivileged account. Administrators
log in with their own named accounts and switch to it, so every action is attributable (AC-2,
AU-3).

```bash
sudo useradd --create-home --comment "OpenShift mirror registry" quay
sudo grep -E '^quay:' /etc/subuid /etc/subgid       # subordinate IDs for rootless podman
sudo loginctl enable-linger quay                     # services survive logout and reboot
sudo install -d -o quay -g quay -m 0750 /data/quay /data/ocp
```

- No direct login for `quay` (no password; access only through `sudo -iu quay` for members of the
  platform team, logged by `sudo` and auditd).
- The installer connects to `localhost` over SSH with a key it generates
  (`~quay/.ssh/quay_installer`). `sshd` must accept key logins for `quay` from `localhost` while
  installing or upgrading. Restrict with a `Match` block if your baseline otherwise denies it:

  ```text
  # /etc/ssh/sshd_config.d/50-quay-installer.conf
  Match User quay Address 127.0.0.1,::1
      PubkeyAuthentication yes
  ```

## Storage layout

| Path | Content | Back up? |
|---|---|---|
| `/data/quay/install` | Registry configuration, certificates, installer files | Yes |
| `/data/quay/storage` | Image blobs | Yes, or be ready to re-import every transfer |
| `/data/quay/sqlite` | Registry database (users, robots, permissions, tags) | Yes, consistently with storage |
| `/data/ocp/transfers` | Accepted transfer packages | Records only, after import |
| `/data/ocp/oc-mirror-cache` | oc-mirror cache | **Yes**, after every import (Red Hat requirement) |
| `/data/ocp/oc-mirror` | oc-mirror workspace | Not required (regenerated each run), but never delete or modify it |
| `/data/ocp/cluster-resources` | IDMS, ITMS, catalogs, signatures per import | Yes |
| `/data/ocp/tools/<version>` | `oc`, `oc-mirror`, `butane`, mirror registry installer from accepted transfers | Optional (re-creatable from transfers) |
| `/data/ocp/installer/<version>` | Extracted `openshift-install-fips` and `release.env` | Yes |
| `/data/ocp/import-log.md` | Import log (see [Accept a transfer](accept-transfer.md#the-import-log)) | Yes (evidence) |

Mount `/data` as a dedicated filesystem so a full registry can't fill `/`.

## Network and firewall

| Flow | Port | Source | Notes |
|---|---|---|---|
| Image pulls and pushes | `8443/tcp` | Cluster machine network, provisioner host, admin hosts | The only service port |
| Administration | `22/tcp` | Departmental bastion only | Named accounts with MFA |
| DNS, NTP, syslog | Outbound | To departmental services | — |

```bash
sudo firewall-cmd --permanent --new-zone=registry
sudo firewall-cmd --permanent --zone=registry --add-source=<machine-network-cidr>
sudo firewall-cmd --permanent --zone=registry --add-source=<admin-network-cidr>
sudo firewall-cmd --permanent --zone=registry --add-port=8443/tcp
sudo firewall-cmd --reload
```

Restricting sources to known networks is a boundary control (SC-7). The registry has no reason to
make outbound connections other than to DNS, NTP, and the log collector.

## Audit and logging

| Source | Content | How it reaches the SIEM |
|---|---|---|
| auditd | Logins, `sudo`, file access on watched paths | `rsyslog` (`imfile` or `audisp-syslog`) over TLS |
| journald | Registry containers (`quay-app`, `quay-redis`) log with `--log-driver=journald` | `rsyslog` `imjournal` over TLS |
| Registry action log | Pushes, pulls, permission and robot changes (in the registry database) | Reviewed in the UI or through the API; export on the evidence cycle |

Suggested audit watches (add to `/etc/audit/rules.d/50-ocp-registry.rules`):

```text
-w /data/quay/install/quay-config/ -p wa -k ocp-registry-config
-w /data/ocp/import-log.md -p wa -k ocp-import-log
-w /home/quay/.config/ocp-registry/ -p rwa -k ocp-registry-credentials
-w /etc/pki/ocp-registry/ -p rwa -k ocp-registry-tls
-w /etc/pki/ocp-transfer/ -p wa -k ocp-transfer-key
```

## TLS certificate

Request a server certificate from the departmental PKI:

| Field | Value |
|---|---|
| Subject alternative name | `DNS:registry.example.gc.ca` (the name clients use; IP-only access isn't supported) |
| Key | RSA 3072+ or ECDSA P-256/P-384, generated on the host, never leaves it |
| Extended key usage | `serverAuth` |
| Signature | SHA-256 or stronger |
| Validity | Per departmental policy; track expiry and plan renewal at least 60 days ahead |

Place the files on the registry host:

| File | Content |
|---|---|
| `/etc/pki/ocp-registry/registry.crt` | Server certificate followed by any intermediate CA certificates |
| `/etc/pki/ocp-registry/registry.key` | Private key, mode `0600`, readable by `quay` |
| `/etc/pki/ocp-registry/ca-bundle.crt` | Root (and intermediate) CA certificates that clients must trust |

The same CA bundle becomes `additionalTrustBundle` in `install-config.yaml` (Phase 3).

## Supporting services checklist

Confirm before installing:

- [ ] **DNS:** forward and reverse records for the registry host. (Cluster records are a Phase 3
      prerequisite.)
- [ ] **NTP:** `chronyc tracking` shows `Leap status: Normal` against the departmental source
      (AU-8). Clock skew breaks TLS and makes logs unusable as evidence.
- [ ] **PKI:** server certificate issued; CA bundle available; revocation and renewal process known.
- [ ] **Git:** repository created on the departmental Git server; push access for the platform
      team; server certificate trusted by the host.
- [ ] **SIEM:** syslog/TLS destination reachable; registry host onboarded.
- [ ] **RHEL content:** an approved source of RHEL 9 packages and errata on the high side
      (for example, a departmental Satellite, or RHEL content imported through the same transfer
      process). The registry, provisioner, and other high-side RHEL hosts need it for installation
      and monthly patching. This repository's transfers carry OpenShift content only.
- [ ] **Backup:** a backup target for `/data/quay` and `/data/ocp`.
- [ ] **Transfer public key:** installed at `/etc/pki/ocp-transfer/ocp-transfer-key.pub.asc`,
      fingerprint confirmed by a second channel.

## Readiness checks

Run these as `quay` before installing, and again monthly as a configuration check (CM-6, SC-17,
AU-8). Keep the output as evidence.

```bash
# Operating system, FIPS, SELinux, audit
cat /etc/redhat-release                       # Red Hat Enterprise Linux release 9.x
cat /proc/sys/crypto/fips_enabled             # 1
getenforce                                    # Enforcing
systemctl is-active auditd firewalld chronyd  # active (x3)

# Rootless prerequisites
id -un                                        # quay, not root
grep "^$(id -un):" /etc/subuid /etc/subgid    # one entry in each
loginctl show-user "$(id -un)" -p Linger      # Linger=yes

# DNS (forward and reverse) and time
getent ahostsv4 registry.example.gc.ca        # resolves to an address of this host
getent hosts <registry-ip>                    # returns registry.example.gc.ca
chronyc -n tracking | grep 'Leap status'      # Normal

# Storage and firewall
findmnt --target /data/quay                   # a dedicated mount, not / or /home
df -h /data/quay                              # about 1 TiB free or more
firewall-cmd --list-all --zone=registry       # 8443/tcp and the expected sources

# Transfer verification key
gpg --show-keys --with-fingerprint /etc/pki/ocp-transfer/ocp-transfer-key.pub.asc
```

Check the certificate before installing and after every renewal:

```bash
cd /etc/pki/ocp-registry
stat -c '%a %U' registry.key                                  # 600 quay
# Certificate and key match (the two digests are identical)
openssl x509 -in registry.crt -noout -pubkey | openssl sha256
openssl pkey -in registry.key -pubout | openssl sha256
# Name, chain, purpose
openssl x509 -in registry.crt -noout -checkhost registry.example.gc.ca   # "does match"
openssl verify -purpose sslserver -CAfile ca-bundle.crt -untrusted registry.crt registry.crt
# Algorithm, key size, expiry
openssl x509 -in registry.crt -noout -text | grep -E 'Signature Algorithm|Public-Key' | sort -u
openssl x509 -in registry.crt -noout -enddate -checkend $((60*86400))
```

- The signature algorithm must not be SHA-1 or MD5. RSA keys must be at least 2048 bits;
  ITSP.40.111 recommends 3072 or more for use beyond 2030.
- `-checkend` prints `Certificate will expire` if fewer than 60 days remain: start renewal.
