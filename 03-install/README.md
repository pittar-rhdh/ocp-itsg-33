# 03-install — Phase 3: Bare-Metal IPI Cluster Install

> **Examples only — not validated.** These scripts have not been run against real hardware, a
> real mirror registry, or a real OpenShift installation. Read them, adapt them, and test them
> before use. See [validation status](../docs/reference/validation-status.md).

Run on the provisioner host (RHEL 9, FIPS mode) as the non-root installation user. Full guidance:
[docs/03-cluster-install](../docs/03-cluster-install/index.md).

| Script | Purpose |
|---|---|
| `01-check-provisioner.sh` | Host, packages, libvirt, bridges, firewall, SSH key type, Phase 2 hand-off and installer checksum |
| `02-validate-environment.sh` | DNS and PTR, mirror registry and release, NTP, every BMC (report to the evidence directory) |
| `03-render-install-config.sh [--force]` | Generate `install-config.yaml` (secrets, 0600) and a redacted evidence copy |
| `04-create-manifests.sh` | `create manifests` + chrony, LUKS/TPM 2.0, and IPsec manifests; evidence copy |
| `05-install-cluster.sh` | `openshift-install-fips create cluster`; logs to the evidence directory |
| `06-post-install.sh [--configure]` | Day-1 settings (mirrored catalogs, OperatorHub, etcd encryption, audit) and verification |

| File | Purpose |
|---|---|
| `settings.env` | Defaults; override in `settings.local.env` (git-ignored) or with exported variables |
| `install-config.yaml.tmpl` | Template rendered by `03-render-install-config.sh` |
| `hosts.virtualmedia.yaml.example`, `hosts.pxe.yaml.example` | Host inventory examples (copy outside the repository) |
| `bmc-credentials.env.example` | BMC credential file format (keep the real file outside Git, mode 0600) |
| `manifests/*.tmpl` | Butane sources and the IPsec network manifest |

Requires on the provisioner: `python3` with `python3-pyyaml`, `jq`, `nmstate`, `bind-utils`,
`libvirt`, `ipmitool` (PXE/IPMI only), and `oc` and `butane` from the Phase 2 hand-off.
