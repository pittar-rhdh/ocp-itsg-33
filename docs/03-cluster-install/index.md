# Phase 3 — Bare-Metal IPI Cluster Install

[← Back to main](../index.md)

> **Examples only — not validated.** The configuration files and commands in this phase are
> examples. They have not been run against a real Red Hat subscription, air-gapped environment, or
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

Versions (OpenShift 4.22 z-stream, Butane 0.29) are listed in
[Versions and pinned content](../reference/versions.md).

## Workflow

All steps run on the provisioner host, as the non-root installation user.

```text
 registry host ──(hand-off)──> provisioner host
                                 │
 1 check provisioner ─> 2 validate environment ─> 3 prepare install-config ─> 4 create manifests
  (RHEL 9 FIPS, libvirt,  (DNS, PTR, registry,      (copy the example, fill    (+ butane: chrony,
   bridges, firewall,      BMC Redfish/IPMI, NTP)    in secrets; keep a         LUKS/TPM2; IPsec;
   installer checksum)                               redacted copy)             evidence copy)
                                                                                      │
                                                                                      v
                     6 Day-1 settings and verification  <──────────────  5 create cluster
                      (mirror catalogs, OperatorHub off, etcd             (openshift-install-fips;
                       encryption, audit profile; verify FIPS,             logs; break-glass
                       LUKS, IPsec, chrony, nodes, operators)              credentials sealed)
```

| Step | Page |
|---|---|
| 1–2 | [Prerequisites and provisioner host](prerequisites.md#checks) |
| 3 | [install-config.yaml](install-config.md#prepare-the-file) |
| 4 | [Install-time security settings](install-time-security.md#add-the-manifests) |
| 5–6 | [Run and verify the install](run-install.md) |

## Pages

| Page | Content |
|---|---|
| [Prerequisites and provisioner host](prerequisites.md) | Hardware, networks, DNS, ports, BMCs, provisioner host build, bridges, the Phase 2 hand-off, checks |
| [install-config.yaml](install-config.md) | Example file, virtual media and PXE variants, host fields, mirror settings, open questions |
| [Install-time security settings](install-time-security.md) | FIPS, LUKS with TPM 2.0, IPsec, chrony, SSH keys, what can't be changed later; creating the manifests |
| [Run and verify the install](run-install.md) | Running the installer, monitoring, failures, Day-1 settings and checks, break-glass handling |

## Example files

| File | Purpose |
|---|---|
| `03-install/install-config.yaml` | Complete example: Redfish virtual media, no provisioning network, FIPS, static NMState addressing |
| `03-install/install-config-pxe-excerpt.yaml` | The parts that differ for a PXE provisioning network |
| `03-install/manifests/99-{master,worker}-chrony.bu` | Butane: chrony with departmental NTP |
| `03-install/manifests/99-{master,worker}-disk-encryption.bu` | Butane: LUKS2 boot disk encryption bound to TPM 2.0 |
| `03-install/manifests/cluster-network-03-config.yml` | OVN-Kubernetes IPsec `Full` |

## How this phase supports ITSG-33

| Control | How |
|---|---|
| SC-13 Cryptographic protection | FIPS mode, set at install from a FIPS-mode RHEL 9 host with the FIPS-capable installer; RSA/ECDSA SSH key |
| SC-28 Protection of information at rest | LUKS2 (AES-256-XTS) on every boot disk, bound to TPM 2.0; etcd encryption (`aesgcm`) right after install |
| SC-8 Transmission confidentiality | OVN-Kubernetes IPsec for east-west traffic; TLS to BMCs with certificate verification (no `disableCertificateVerification: true`, no `redfish+http`) |
| AU-8 Time stamps | chrony on every node pointed at departmental NTP from first boot |
| CM-2, CM-6 Baseline and settings | install-config and manifests built from reviewed examples; redacted install-config and manifests kept with checksums |
| CM-7, CM-11 Least functionality, software | Mirror-only content (IDMS, mirrored catalogs); default OperatorHub sources disabled |
| AU-2, AU-12 Audit | API server audit profile `WriteRequestBodies` from Day 1 |
| AC-2, AC-6(9), IA-5 Accounts and authenticators | Break-glass kubeconfig sealed; `kubeadmin` removed in Phase 4; BMC credentials kept outside Git, per host, rotated after install |
