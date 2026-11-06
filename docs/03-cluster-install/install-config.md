# install-config.yaml

[← Phase 3](index.md)

`install-config.yaml` describes the cluster and every bare-metal host. Because it contains BMC
passwords and the pull secret, it is **generated** on the provisioner host and never committed.

```bash
03-install/03-render-install-config.sh
```

| Source | Becomes |
|---|---|
| `03-install/install-config.yaml.tmpl` | Structure and fixed settings (OVN-Kubernetes, 3 control plane nodes, `fips`, `additionalTrustBundlePolicy: Always`) |
| `settings.env` / `settings.local.env` | Cluster name, domain, networks, VIPs, load balancer type, replicas, NTP, provisioning settings |
| `HOSTS_FILE` (from a `hosts.*.yaml.example`) | `platform.baremetal.hosts` |
| `BMC_CREDENTIALS_FILE` (mode 0600) | `bmc.username` / `bmc.password` for each host |
| `idms-oc-mirror.yaml` (oc-mirror) | `imageDigestSources` |
| `ca-bundle.crt` | `additionalTrustBundle` |
| `cluster-pull-secret.json` | `pullSecret` (pull-only mirror robot; no Red Hat credentials, so no Telemetry) |
| `SSH_PUBLIC_KEY_FILE` | `sshKey` (RSA or ECDSA in FIPS mode) |

Outputs:

- `${INSTALL_DIR}/install-config.yaml` (mode 0600, secrets). The installer **consumes** it when it
  creates manifests; a backup is kept at `${INSTALL_BASE}/install-config.<cluster>.yaml.bak`.
- `${EVIDENCE_DIR}/install-config.redacted.yaml`: the same file with BMC passwords and the pull
  secret removed, for the configuration baseline (CM-2).

The script refuses to run into a directory the installer has already used. Red Hat: always use an
empty installation directory, because some assets (bootstrap certificates) expire quickly.

## What the script checks

- exactly three `master` hosts; roles are `master` or `worker`; unique names and boot MAC
  addresses; `COMPUTE_REPLICAS` is 0 or at least 2;
- with `PROVISIONING_METHOD=virtualmedia`, every BMC address uses a virtual-media driver
  (`redfish-virtualmedia://`, `idrac-virtualmedia://`);
- no `redfish+http://` (TLS disabled) and no `disableCertificateVerification: true`: provide the
  BMC CA in `BMC_CA_BUNDLE` instead (SC-8, SC-17);
- every host has credentials in the credentials file (passed to the helper through the
  environment, never on a command line);
- the VIPs (and provisioning IPs, if set) are inside the machine network and the two VIPs differ;
- the IDMS contains the release mirrors;
- each host's `networkConfig` passes `nmstatectl gc` (Red Hat recommends this; the installer
  doesn't check NMState syntax). Skipped with a warning if `nmstatectl` isn't installed.

## Provisioning methods (AD-11)

| | Redfish virtual media (primary) | PXE provisioning network (alternative) |
|---|---|---|
| Example inventory | `hosts.virtualmedia.yaml.example` | `hosts.pxe.yaml.example` |
| `provisioningNetwork` | `Disabled` | `Managed` (Ironic runs DHCP/TFTP on it) |
| BMC address | `redfish-virtualmedia://<bmc>/redfish/v1/Systems/1`; Dell: `idrac-virtualmedia://<bmc>/redfish/v1/Systems/System.Embedded.1` (Red Hat: `redfish-virtualmedia` doesn't work on Dell) | `redfish://…` or `ipmi://<bmc>[:623]` (IPMI is unencrypted; use only on a secured management network) |
| `bootMACAddress` | The machine-network NIC (still required) | The provisioning NIC |
| Addressing | Static NMState `networkConfig` or DHCP reservations | DHCP reservations |
| Extra settings | `CLUSTER_PROVISIONING_IP`, `BOOTSTRAP_PROVISIONING_IP` (two reserved machine-network addresses) | `PROVISIONING_NETWORK_CIDR`, `PROVISIONING_BRIDGE` |
| Manually enabled Secure Boot | Supported | Not supported by Red Hat |

## Host inventory

The inventory uses the `platform.baremetal.hosts` format with two differences: no credentials,
and indentation from column 0. Key fields:

| Field | Guidance |
|---|---|
| `name` | Becomes the `BareMetalHost` name, for example `openshift-master-0` |
| `role` | `master` or `worker` |
| `bmc.address` | See the table above. Red Hat lists vendor-specific formats for Dell, HPE, Fujitsu, and Cisco. |
| `bmc.disableCertificateVerification` | `false`, with `BMC_CA_BUNDLE` set to the CA that signed the BMC certificates |
| `bootMACAddress` | Required |
| `bootMode` | `UEFI` (with Secure Boot enabled manually in firmware); `UEFISecureBoot` only on the hardware Red Hat lists |
| `rootDeviceHints` | Use a persistent attribute: `deviceName: /dev/disk/by-path/...`, `wwn`, or `serialNumber`. `/dev/sdX` names can change between boots. |
| `networkConfig` | NMState for bonds, VLANs, static addresses, routes, DNS. Don't set the `rotate` DNS resolver option (Red Hat: it breaks the internal API's name resolution). |

## Settings in the template

| Setting | Value | Why |
|---|---|---|
| `fips` | `true` | SC-13; cannot be changed after installation |
| `networking.networkType` | `OVNKubernetes` | Only supported value |
| `controlPlane.replicas` | `3` | HA control plane (AD-04) |
| `platform.baremetal.loadBalancer.type` | `OpenShiftManagedDefault` or `UserManaged` | AD-16 |
| `platform.baremetal.additionalNTPServers` | `NTP_SERVERS` | Red Hat: lets hosts sync their clocks before installation; the chrony MachineConfigs set NTP permanently |
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
| Bootstrap VM image | Red Hat states the installer no longer needs `clusterOSImage` because the image is in the release payload. The optional `bootstrapOSImage` / image cache procedure downloads an RHCOS QEMU image from the internet, which isn't possible here. If the installer still tries to download a bootstrap image in your environment, transfer the image (Phase 1, as an additional file), serve it from an internal HTTPS server, and set `BOOTSTRAP_OS_IMAGE`. |
| Provisioning IPs | Red Hat asks for two machine-network addresses when the provisioning network is disabled; the installer source treats `clusterProvisioningIP` and `bootstrapProvisioningIP` as optional. The script sets them when `CLUSTER_PROVISIONING_IP` / `BOOTSTRAP_PROVISIONING_IP` are given and warns otherwise. |
| Trimming capabilities (CM-7) | Disabling optional components needs `baselineCapabilitySet: None` plus an explicit `additionalEnabledCapabilities` list. Bare-metal IPI depends on several capabilities (for example `baremetal`, `MachineAPI`, `Ingress`). Not attempted in this example; test in a lab before using it. |
