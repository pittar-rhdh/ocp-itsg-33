# install-config.yaml

[← Phase 3](index.md)

> **Examples only — not validated.** The example file and commands on this page have not been
> used for a real installation. Test and adapt them before use. See
> [Validation status](../reference/validation-status.md).

`install-config.yaml` describes the cluster and every bare-metal host. The repository has a
complete example, `03-install/install-config.yaml` (Redfish virtual media, no provisioning network),
and `03-install/install-config-pxe-excerpt.yaml` with the parts that differ for PXE. The real file
contains BMC passwords and the pull secret, so it is prepared on the provisioner host and never
committed.

## Prepare the file

```bash
# A new, empty installation directory. Red Hat: never reuse one; some assets
# (bootstrap certificates) expire quickly.
INSTALL_DIR=~/ocp-install/ocp1
mkdir -m 0700 "${INSTALL_DIR}"

# Working copy outside the installation directory (the installer deletes its copy)
cp 03-install/install-config.yaml ~/ocp-install/install-config.ocp1.yaml
chmod 0600 ~/ocp-install/install-config.ocp1.yaml
```

Edit the working copy: cluster name, domain, networks, VIPs, provisioning addresses, NTP servers,
and every host. Then replace the placeholders with values from the Phase 2 hand-off:

| Placeholder | Source |
|---|---|
| `imageDigestSources` | The `spec.imageDigestMirrors` entries of `idms-oc-mirror.yaml` (same `mirrors` / `source` structure) |
| `<departmental-ca-pem>` (`additionalTrustBundle`) | `ca-bundle.crt`, indented two spaces |
| `<bmc-issuing-ca-pem>` (`bmcVerifyCA`) | The CA that signed the BMC certificates, indented six spaces |
| `<bmc-username>`, `<bmc-password>` | A dedicated, least-privilege BMC account per host (IA-5, AC-6) |
| `<cluster-pull-secret-json>` | `cluster-pull-secret.json` as one line: pull-only mirror robot, no Red Hat credentials, so no Telemetry |
| `<ecdsa-or-rsa-public-key>` | `~/.ssh/ocp-core_ecdsa.pub` (RSA or ECDSA in FIPS mode) |

These commands print the values in the form to paste:

```bash
cd ~/ocp-install/inputs
cat idms-oc-mirror.yaml                     # copy spec.imageDigestMirrors entries
sed 's/^/  /' ca-bundle.crt                 # additionalTrustBundle
sed 's/^/      /' ~/ocp-install/bmc-ca.crt  # bmcVerifyCA
jq -c . cluster-pull-secret.json            # pullSecret (inside single quotes)
cat ~/.ssh/ocp-core_ecdsa.pub               # sshKey
```

### Check it

```bash
cd ~/ocp-install
grep -nv '^ *#' install-config.ocp1.yaml | grep '<'   # no placeholders left (comments ignored)
grep -n 'disableCertificateVerification: true\|redfish+http' install-config.ocp1.yaml   # no output
openshift-install-fips explain installconfig.platform.baremetal   # accepted field names

# Test each host's networkConfig block (saved as its own file) with NMState;
# the installer does not check NMState syntax.
nmstatectl gc openshift-master-0.nmstate.yaml
```

Review against the example: exactly three `master` hosts; roles `master` or `worker`; unique
names and boot MAC addresses; `compute.replicas` 0 or at least 2; VIPs and provisioning addresses
inside the machine network; the two VIPs differ; the release mirrors
(`quay.io/openshift-release-dev/...`) present in `imageDigestSources`.

### Install and keep a redacted copy

```bash
cp ~/ocp-install/install-config.ocp1.yaml "${INSTALL_DIR}/install-config.yaml"

# Redacted copy for the configuration baseline (CM-2): BMC passwords and pull secret removed
EVIDENCE_DIR=~/ocp-install/evidence/ocp1
sed -E -e 's/^( *password: ).*/\1REDACTED/' -e "s/^(pullSecret: ).*/\1'REDACTED'/" \
  ~/ocp-install/install-config.ocp1.yaml > "${EVIDENCE_DIR}/install-config.redacted.yaml"
chmod 0600 "${EVIDENCE_DIR}/install-config.redacted.yaml"
(cd "${EVIDENCE_DIR}" && sha256sum install-config.redacted.yaml >> SHA256SUMS)
```

The working copy (`~/ocp-install/install-config.ocp1.yaml`) is the backup; delete it after the
install (see [Credentials](run-install.md#credentials)).

## Provisioning methods (AD-11)

| | Redfish virtual media (primary) | PXE provisioning network (alternative) |
|---|---|---|
| Example | `03-install/install-config.yaml` | `03-install/install-config-pxe-excerpt.yaml` |
| `provisioningNetwork` | `Disabled` | `Managed` (Ironic runs DHCP/TFTP on it) |
| BMC address | `redfish-virtualmedia://<bmc>/redfish/v1/Systems/1`; Dell: `idrac-virtualmedia://<bmc>/redfish/v1/Systems/System.Embedded.1` (Red Hat: `redfish-virtualmedia` doesn't work on Dell) | `redfish://…` or `ipmi://<bmc>[:623]` (IPMI is unencrypted; use only on a secured management network) |
| `bootMACAddress` | The machine-network NIC (still required) | The provisioning NIC |
| Addressing | Static NMState `networkConfig` or DHCP reservations | DHCP reservations |
| Extra settings | `clusterProvisioningIP`, `bootstrapProvisioningIP` (two reserved machine-network addresses) | `provisioningNetworkCIDR`, `provisioningBridge` |
| Manually enabled Secure Boot | Supported | Not supported by Red Hat |

## Host fields

| Field | Guidance |
|---|---|
| `name` | Becomes the `BareMetalHost` name, for example `openshift-master-0` |
| `role` | `master` or `worker` |
| `bmc.address` | See the table above. Red Hat lists vendor-specific formats for Dell, HPE, Fujitsu, and Cisco. |
| `bmc.username`, `bmc.password` | Per host; the cluster keeps them as Secrets in `openshift-machine-api` for Day 2 node management. Rotate after install. |
| `bmc.disableCertificateVerification` | `false`, with `bmcVerifyCA` set to the CA that signed the BMC certificates (SC-8, SC-17) |
| `bootMACAddress` | Required |
| `bootMode` | `UEFI` (with Secure Boot enabled manually in firmware); `UEFISecureBoot` only on the hardware Red Hat lists |
| `rootDeviceHints` | Use a persistent attribute: `deviceName: /dev/disk/by-path/...`, `wwn`, or `serialNumber`. `/dev/sdX` names can change between boots. |
| `networkConfig` | NMState for bonds, VLANs, static addresses, routes, DNS. Don't set the `rotate` DNS resolver option (Red Hat: it breaks the internal API's name resolution). |

## Settings in the example

| Setting | Value | Why |
|---|---|---|
| `fips` | `true` | SC-13; cannot be changed after installation |
| `networking.networkType` | `OVNKubernetes` | Only supported value |
| `controlPlane.replicas` | `3` | HA control plane (AD-04) |
| `platform.baremetal.loadBalancer.type` | `OpenShiftManagedDefault` (`UserManaged` as a commented alternative) | AD-16 |
| `platform.baremetal.additionalNTPServers` | `ntp1.example.gc.ca`, `ntp2.example.gc.ca` | Red Hat: lets hosts sync their clocks before installation; the chrony MachineConfigs set NTP permanently |
| `imageDigestSources` | From the oc-mirror IDMS | Nodes pull only from the mirror registry |
| `additionalTrustBundle` + `additionalTrustBundlePolicy: Always` | Departmental CA | Nodes trust the mirror registry; `Always` adds the bundle to the cluster proxy trust even without a proxy |
| `pullSecret` | Pull-only robot | The cluster never gets push credentials (Red Hat warns against this) |
| `capabilities` | Not set (default `vCurrent`) | See "Open questions" |

## Open questions to settle in a lab

These were found while preparing the example and must be checked against the exact 4.22 z-stream
installer before a real install (`openshift-install-fips explain installconfig...` shows the
accepted fields):

| Topic | What was found |
|---|---|
| `imageDigestSources` vs `imageContentSources` | The 4.22 documentation examples and parameter tables still show `imageContentSources`. The 4.22 installer source marks `imageContentSources` as deprecated and accepts `imageDigestSources`, which matches oc-mirror v2's IDMS output. This repository uses `imageDigestSources`. |
| BMC CA field name | Red Hat's 4.22 bare-metal text uses `bmcCACert` in examples but `bmcVerifyCA` in the parameter table. The 4.22 installer source defines `bmcVerifyCA`; this repository uses that. |
| Bootstrap VM image | Red Hat states the installer no longer needs `clusterOSImage` because the image is in the release payload. The optional `bootstrapOSImage` / image cache procedure downloads an RHCOS QEMU image from the internet, which isn't possible here. If the installer still tries to download a bootstrap image in your environment, transfer the image (Phase 1, as an additional file), serve it from an internal HTTPS server, and set `bootstrapOSImage` (commented out in the example). |
| Provisioning IPs | Red Hat asks for two machine-network addresses when the provisioning network is disabled; the installer source treats `clusterProvisioningIP` and `bootstrapProvisioningIP` as optional. The example sets them so the addresses are explicit and reserved. |
| Trimming capabilities (CM-7) | Disabling optional components needs `baselineCapabilitySet: None` plus an explicit `additionalEnabledCapabilities` list. Bare-metal IPI depends on several capabilities (for example `baremetal`, `MachineAPI`, `Ingress`). Not attempted in this example; test in a lab before using it. |
