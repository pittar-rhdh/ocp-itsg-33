# Phase 3 — Bare-Metal IPI Cluster Install

[← Back to main](../index.md)

> **Examples only — not validated.** The scripts and configuration in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

> **Status:** Planned. This page defines the scope of the phase. The procedures and
> configuration files are added in the Phase 3 work.

Install a highly available OpenShift 4.22 cluster (3 control plane + 3..N workers) on bare metal
with the installer-provisioned infrastructure method, using only the mirror registry, with the
security settings that can only be set at install time.

| | |
|---|---|
| **Where** | High side (provisioner host, BMC network, machine network) |
| **Inputs** | Phase 2 [hand-off](../02-high-side/populate-registry.md#hand-off-to-phase-3): `release.env` and `openshift-install-fips`, the IDMS, the pull-only pull secret, and the CA bundle; hardware inventory (BMC addresses, credentials, MAC addresses, root disks); network plan |
| **Outputs** | Running cluster; `kubeadmin` removed after an IdP is configured; break-glass `kubeconfig` sealed in a vault; install logs kept as evidence |
| **Hands off to** | [Phase 4 — ITSG-33 configuration](../04-itsg33-configuration/index.md) |
| **Decisions** | AD-01, AD-04, AD-05, AD-06, AD-11, AD-16, AD-17 ([Architecture decisions](../00-architecture/architecture-decisions.md)) |
| **Key controls** | CM-2, CM-6, CM-7, SC-8, SC-13, SC-28, IA-5, AC-2 |

## Planned content

| Page | Content |
|---|---|
| Hardware and network prerequisites | Firmware, UEFI Secure Boot, BMC (Redfish) checks, VLANs, VIPs, DNS validation |
| Provisioner host | RHEL 9 in FIPS mode, libvirt, `baremetal` (and optional `provisioning`) bridges |
| `install-config.yaml` — Redfish virtual media (primary) | `provisioningNetwork: Disabled`, per-host BMC and `rootDeviceHints`, NMState `networkConfig` |
| `install-config.yaml` — PXE provisioning network (alternative) | Provisioning network settings and the differences from virtual media |
| Install-time security settings | `fips: true`, `imageDigestSources`, `additionalTrustBundle`, trimmed `capabilities`, OperatorHub sources disabled |
| Install-time manifests | LUKS with TPM2 and/or Tang, IPsec, chrony, API server audit profile, etcd encryption |
| Run and verify the install | Running the installer, watching the bootstrap, post-install validation |
| First steps after install | Mirrored catalog sources, IdP, removing `kubeadmin`, sealing break-glass credentials, rotating BMC credentials |

## Planned repository files

```text
03-install/
  install-config.virtualmedia.yaml.example
  install-config.pxe.yaml.example
  manifests/                    # install-time-only MachineConfigs and cluster settings
  validate-prereqs.sh
  post-install-checks.sh
```
