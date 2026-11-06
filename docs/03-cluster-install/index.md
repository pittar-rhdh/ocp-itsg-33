# Phase 3 — Bare-Metal IPI Cluster Install

[← Back to main](../index.md)

> **Examples only — not validated.** The scripts and configuration in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

Install a highly available OpenShift 4.22 cluster (3 control plane + 3..N workers) on bare metal
with the installer-provisioned infrastructure (IPI) method, using only the mirror registry, and
with the security settings that can only be set at install time.

| | |
|---|---|
| **Where** | High side: provisioner host (RHEL 9, FIPS), BMC network, machine network |
| **Inputs** | Phase 2 [hand-off](../02-high-side/populate-registry.md#hand-off-to-phase-3); hardware inventory (BMC addresses, MAC addresses, root disks); network plan; BMC credentials |
| **Outputs** | Running FIPS cluster with encrypted boot disks, IPsec, chrony, mirror-only content sources, etcd encryption, and audit profile; break-glass credentials sealed in a vault; install records in the evidence directory |
| **Hands off to** | [Phase 4 — ITSG-33 configuration](../04-itsg33-configuration/index.md) |
| **Decisions** | AD-01, AD-04, AD-05, AD-06, AD-11, AD-16, AD-17 ([Architecture decisions](../00-architecture/architecture-decisions.md)) |
| **Key controls** | CM-2, CM-6, CM-7, SC-8, SC-13, SC-28, AU-8, IA-5, AC-2, AC-6(9) |

## Workflow

```text
 registry host ──(hand-off)──> provisioner host
                                 │
 01 check-provisioner ─> 02 validate-environment ─> 03 render-install-config ─> 04 create-manifests
  (RHEL 9 FIPS, libvirt,   (DNS, PTR, registry,      (template + hosts +        (+ chrony, LUKS/TPM2,
   bridges, firewall,       BMC Redfish/IPMI,         credentials + IDMS +        IPsec; evidence copy)
   installer checksum)      NTP; report)              CA; redacted copy)                 │
                                                                                         v
                     06 post-install  <───────────────────────────────────  05 install-cluster
                      (--configure: mirror catalogs, OperatorHub off,        (openshift-install-fips
                       etcd encryption, audit profile; verify FIPS,           create cluster; logs;
                       LUKS, IPsec, chrony, nodes, operators)                 break-glass reminder)
```

## Quick start

```bash
# On the provisioner host, as the installation user (not root)
cp 03-install/hosts.virtualmedia.yaml.example ~/ocp-install/hosts.yaml          # edit
cp 03-install/bmc-credentials.env.example ~/ocp-install/bmc-credentials.env     # edit, chmod 0600
vi 03-install/settings.local.env                                                # cluster values

03-install/01-check-provisioner.sh
03-install/02-validate-environment.sh
03-install/03-render-install-config.sh
03-install/04-create-manifests.sh          # review the manifests before continuing
03-install/05-install-cluster.sh
KUBECONFIG=~/ocp-install/ocp1/auth/kubeconfig 03-install/06-post-install.sh --configure
```

## Pages

| Page | Content |
|---|---|
| [Prerequisites and provisioner host](prerequisites.md) | Hardware, networks, DNS, ports, BMCs, provisioner host build, bridges, the Phase 2 hand-off |
| [install-config.yaml](install-config.md) | Template, host inventory, virtual media and PXE variants, BMC credentials, mirror settings, open questions |
| [Install-time security settings](install-time-security.md) | FIPS, LUKS with TPM 2.0, IPsec, chrony, SSH keys, what can't be changed later |
| [Run and verify the install](run-install.md) | Manifests, running the installer, monitoring, failures, post-install configuration and checks, break-glass handling |

## Repository files

| File | Purpose |
|---|---|
| `03-install/settings.env` | Cluster name, domain, networks, VIPs, provisioning method, security settings, file locations |
| `03-install/install-config.yaml.tmpl` | install-config template |
| `03-install/hosts.virtualmedia.yaml.example` | Host inventory example: Redfish virtual media, static NMState addressing |
| `03-install/hosts.pxe.yaml.example` | Host inventory example: PXE provisioning network, DHCP reservations |
| `03-install/bmc-credentials.env.example` | Per-host BMC credential file format (kept outside Git) |
| `03-install/manifests/*.tmpl` | Butane sources (chrony, disk encryption) and the IPsec network manifest |
| `03-install/01-check-provisioner.sh` … `06-post-install.sh` | The workflow above |

## How this phase supports ITSG-33

| Control | How |
|---|---|
| SC-13 Cryptographic protection | FIPS mode, set at install from a FIPS-mode RHEL 9 host with the FIPS-capable installer; RSA/ECDSA SSH key |
| SC-28 Protection of information at rest | LUKS2 (AES-256-XTS) on every boot disk, bound to TPM 2.0; etcd encryption (`aesgcm`) right after install |
| SC-8 Transmission confidentiality | OVN-Kubernetes IPsec for east-west traffic; TLS to BMCs with certificate verification (no `disableCertificateVerification: true`, no `redfish+http`) |
| AU-8 Time stamps | chrony on every node pointed at departmental NTP from first boot |
| CM-2, CM-6 Baseline and settings | install-config and manifests generated from reviewed templates; redacted install-config and manifests kept with checksums |
| CM-7, CM-11 Least functionality, software | Mirror-only content (IDMS, mirrored catalogs); default OperatorHub sources disabled |
| AU-2, AU-12 Audit | API server audit profile `WriteRequestBodies` from Day 1 |
| AC-2, AC-6(9), IA-5 Accounts and authenticators | Break-glass kubeconfig sealed; `kubeadmin` removed in Phase 4; BMC credentials kept outside Git, per host, rotated after install |
