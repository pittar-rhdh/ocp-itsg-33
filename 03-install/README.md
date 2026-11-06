# 03-install — Phase 3: Bare-Metal IPI Cluster Install

> **Examples only — not validated.** These files show what the installation inputs should look
> like for an air-gapped, FIPS, bare-metal IPI install of OpenShift 4.22. They have not been used
> against real hardware or a real installation. Copy them outside the repository, change every
> example value and `<placeholder>`, and test before use.

The steps and commands are in the guide: [Phase 3 — Bare-Metal IPI Cluster Install](../docs/03-cluster-install/index.md).

| File | Purpose |
|---|---|
| `install-config.yaml` | Complete example: Redfish virtual media, no provisioning network, FIPS, 3 control plane + 3 workers with static NMState addressing, mirror-only `imageDigestSources` |
| `install-config-pxe-excerpt.yaml` | Only the parts that differ for the PXE provisioning-network alternative |
| `manifests/99-master-chrony.bu`, `manifests/99-worker-chrony.bu` | Butane: chrony with the departmental NTP servers (AU-8) |
| `manifests/99-master-disk-encryption.bu`, `manifests/99-worker-disk-encryption.bu` | Butane: LUKS2 boot disk encryption bound to TPM 2.0 (SC-28) |
| `manifests/cluster-network-03-config.yml` | OVN-Kubernetes IPsec `Full` (SC-8) |

The filled-in `install-config.yaml` contains BMC passwords and the pull secret: never commit it.
