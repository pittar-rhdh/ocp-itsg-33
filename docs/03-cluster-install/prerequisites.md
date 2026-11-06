# Prerequisites and Provisioner Host

[← Phase 3](index.md)

> **Examples only — not validated.** The commands and values on this page are examples. Test and
> adapt them before use. See [Validation status](../reference/validation-status.md).

Facts on this page come from the OpenShift 4.22 *Installing on bare metal* guide, chapter 3
(installer-provisioned infrastructure), unless noted.

## Hardware

| Item | Requirement |
|---|---|
| Nodes | 3 control plane + 3 or more workers (this design). Red Hat: never exactly one worker. Same make, model, and configuration per role is recommended. |
| Minimum resources | Control plane: 4 CPU, 16 GB RAM, 100 GB disk, 300 IOPS. Compute: 2 CPU, 8 GB, 100 GB. Size for ACM, RHACS, and logging on the infra-labelled workers (AD-17). |
| CPU | x86-64-v2 (RHCOS 4.22 is based on RHEL 9.8) |
| Firmware | UEFI. For virtual media, Red Hat lists tested firmware versions (for example HPE iLO 5 2.63+, iLO 6 1.57+; Dell iDRAC 9 v6.10.30.00 or v7.10.x) — check the current table. Delete old, non-generic UEFI boot entries before installing from virtual media. |
| TPM | TPM 2.0 enabled in firmware on every node (disk encryption, AD-06) |
| Secure Boot | Enable manually in firmware (supported with Redfish virtual media), or use managed Secure Boot (`bootMode: UEFISecureBoot`) only on the HPE and Dell generations Red Hat lists |
| BMC | Redfish with virtual media (primary), or IPMI/Redfish network boot for PXE. BMC certificates from the departmental PKI. |
| MTU | 1500 or more on the networks used for inspection |

## Networks

| Network | Virtual media (primary) | PXE (alternative) |
|---|---|---|
| Machine ("baremetal") network | Required; routable; node IPs, VIPs, provisioner | Required |
| Provisioning network | **Not used** (`provisioningNetwork: Disabled`) | Required: non-routed, dedicated NIC (or VLAN) per node, PXE first in boot order, PXE off on every other NIC, no other DHCP server on it |
| BMC (out-of-band) network | Required; the provisioner and control plane nodes must be reachable **from** the BMCs | Required |
| Addressing | Static (NMState `networkConfig`) or DHCP reservations | DHCP reservations (a fully static deployment needs virtual media) |

Reserve on the machine network: the API VIP, the ingress VIP, the provisioner, and one address
per node. With `provisioningNetwork: Disabled`, Red Hat also asks for two machine-network
addresses for the provisioning services (`10.10.0.7` and `10.10.0.8` in the example). The VIPs
and these addresses must be inside the machine network (`10.10.0.0/24` in the example), and the
two VIPs must differ.

### Ports

| Port | From → to | When |
|---|---|---|
| 80/tcp | Nodes → provisioner | Streaming the RHCOS image (no image cache, or virtual media) |
| 123/udp | Nodes → NTP servers | Always |
| 6180/tcp | BMCs → provisioner and control plane nodes | Virtual media without TLS |
| 6183/tcp | BMCs → provisioner and control plane nodes | Virtual media with TLS |
| 6385, 6388 | Ironic API (bootstrap VM, then control plane) | Always |
| 5050, 5051 | Ironic inspector | Always |
| 9999/tcp | Ironic conductor → Ironic Python Agent on the node | Always |
| 67, 68, 69 | DHCP and TFTP on the provisioning network | PXE only |
| 8443/tcp | Nodes and provisioner → mirror registry | Always (this design) |

### DNS

| Record | Type | Value |
|---|---|---|
| `api.<cluster>.<domain>` | A **and PTR** | API VIP (or external load balancer) |
| `*.apps.<cluster>.<domain>` | A (wildcard) | Ingress VIP |
| Each node and the provisioner | A and PTR | Node address. RHCOS uses reverse DNS (or DHCP) to set host names. |

The upstream DNS servers must accept **both TCP and UDP** from the nodes (CoreDNS needs both).
See [Checks](#checks) for the `dig` commands.

### Load balancing (AD-16)

The default (`OpenShiftManagedDefault`) runs keepalived and HAProxy on the nodes for the two
VIPs. A departmental load balancer can be used with `loadBalancer.type: UserManaged`; Red Hat
supports it for the Ingress Controller, the OpenShift API, and the MachineConfig API, and requires
the load balancer to be on the same L2 network (and VLAN) as the control plane nodes, with stable
back-end addresses.

## Provisioner host

The provisioner runs the installer and the temporary bootstrap VM. It can be removed or
repurposed after installation. Build it like the registry host (see
[Registry host](../02-high-side/registry-host.md)): RHEL 9 minimal, **FIPS mode** enabled at
installation, SELinux enforcing, hardened baseline, time synchronized, logs forwarded to the SIEM.

Red Hat's preparation steps, adapted for the high side:

```bash
# Installation user (Red Hat's procedure names it "kni")
sudo useradd kni && sudo passwd kni
echo "kni ALL=(root) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/kni && sudo chmod 0440 /etc/sudoers.d/kni

# Packages from the high-side RHEL content source (no subscription-manager on the high side)
sudo dnf install -y libvirt qemu-kvm mkisofs python3-devel jq ipmitool nmstate bind-utils
sudo usermod --append --groups libvirt kni

sudo systemctl start firewalld
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-port=6180/tcp --add-port=6183/tcp
sudo firewall-cmd --reload

for drv in qemu interface network nodedev nwfilter secret storage; do
  sudo systemctl start virt${drv}d{,-ro,-admin}.socket
done
sudo virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
sudo virsh pool-start default && sudo virsh pool-autostart default
```

- Red Hat's sudo rule gives the installation user unrestricted root. Record it as an accepted
  exception for the install window, restrict who can log in as `kni`, and remove the rule (or the
  host) after installation (AC-6).
- **SSH key:** Red Hat's example uses `ssh-keygen -t ed25519`, but in FIPS mode the key must be
  **RSA or ECDSA**:

  ```bash
  ssh-keygen -t ecdsa -b 384 -N '' -f ~/.ssh/ocp-core_ecdsa
  ```

- The pull secret is **not** a Red Hat pull secret: it is the pull-only mirror credential from
  Phase 2.

### Bridges

The bootstrap VM attaches to a `baremetal` bridge (and a `provisioning` bridge for PXE). Create
them with NMState; NMState rolls back automatically if the change breaks your SSH session.

```yaml
# baremetal-bridge.yaml (static example); apply with: sudo nmstatectl apply baremetal-bridge.yaml
dns-resolver:
  config:
    server:
      - 10.10.0.2
routes:
  config:
    - destination: 0.0.0.0/0
      next-hop-interface: baremetal
      next-hop-address: 10.10.0.1
interfaces:
  - name: eno1
    type: ethernet
    state: up
    ipv4:
      enabled: false
    ipv6:
      enabled: false
  - name: baremetal
    type: linux-bridge
    state: up
    ipv4:
      enabled: true
      dhcp: false
      address:
        - ip: 10.10.0.4
          prefix-length: 24
    bridge:
      options:
        stp:
          enabled: false
      port:
        - name: eno1
```

For PXE, add a `provisioning` bridge on the provisioning NIC with an address in the
provisioning network (`172.22.0.0/24` in the example; Red Hat's example uses `172.22.0.254/24`). Back up the result with
`nmstatectl show > backup-nmstate.yml`.

### Phase 2 hand-off

Copy these from the registry host (see the
[Phase 2 hand-off](../02-high-side/populate-registry.md#hand-off-to-phase-3)) into an inputs
directory on the provisioner, for example `~/ocp-install/inputs`, with `scp` over the MRZ
management network:

| File | Used for |
|---|---|
| `openshift-install-fips`, with its SHA-256 and the release digest recorded in Phase 2 | The installer, pinned to the transferred release |
| `idms-oc-mirror.yaml` | `imageDigestSources` in `install-config.yaml` |
| `cluster-resources/` (whole oc-mirror output directory) | Mirrored catalogs, ITMS, and release signatures after install |
| `cluster-pull-secret.json` (mode 0600) | `pullSecret` (pull-only mirror robot) |
| `ca-bundle.crt` | `additionalTrustBundle`, and `--cacert` for the registry checks |
| `oc`, `butane` | Client tools |

Keep install records in an evidence directory, for example `~/ocp-install/evidence/ocp1`
(mode 0700; Protected B once populated).

```bash
mkdir -p ~/ocp-install/inputs ~/ocp-install/evidence/ocp1
chmod 0700 ~/ocp-install ~/ocp-install/evidence
export PATH=~/ocp-install/inputs:$PATH      # oc, butane, openshift-install-fips
```

## Checks

Run these before preparing `install-config.yaml`, and keep the output with the change record.
One way is to record the session with `script`:

```bash
script ~/ocp-install/evidence/ocp1/environment-check-$(date +%Y%m%d).txt
# ... run the checks below, then: exit
```

### Host settings and packages

```bash
cat /etc/redhat-release                        # Red Hat Enterprise Linux release 9.x
fips-mode-setup --check                        # FIPS mode is enabled.
getenforce                                     # Enforcing
chronyc -n tracking | grep 'Leap status'       # Normal
id                                             # the installation user (not root), in the libvirt group
rpm -q libvirt qemu-kvm nmstate ipmitool jq bind-utils
sudo virsh pool-info default                   # State: running, Autostart: yes
df -h /var/lib/libvirt/images                  # about 100 GiB free for the bootstrap VM
ip -br addr show baremetal                     # 10.10.0.4/24 (and "provisioning" for PXE)
sudo firewall-cmd --list-all                   # services: http; ports: 6180/tcp 6183/tcp
ssh-keygen -lf ~/.ssh/ocp-core_ecdsa.pub       # (ECDSA) or (RSA), never (ED25519) in FIPS mode
```

### Installer and hand-off files

```bash
cd ~/ocp-install/inputs
sha256sum openshift-install-fips               # must match the checksum recorded in Phase 2
./openshift-install-fips version               # release image quay.io/openshift-release-dev/ocp-release@sha256:<release-digest>
stat -c '%a %n' cluster-pull-secret.json       # 600
jq -r '.auths | keys[]' cluster-pull-secret.json   # only registry.example.gc.ca:8443; no Red Hat registries
oc version --client
butane --version
```

### DNS and NTP

```bash
dig +short api.ocp1.example.gc.ca              # 10.10.0.5 (API VIP)
dig +short -x 10.10.0.5                        # api.ocp1.example.gc.ca.
dig +short test.apps.ocp1.example.gc.ca        # 10.10.0.6 (ingress VIP, wildcard)
dig +short api-int.ocp1.example.gc.ca          # empty, or the API VIP
dig +tcp +short api.ocp1.example.gc.ca         # DNS over TCP works too

# Every node needs a PTR record (RHCOS uses it to set the host name)
for ip in 10.10.0.10 10.10.0.11 10.10.0.12 10.10.0.20 10.10.0.21 10.10.0.22; do
  echo "${ip} -> $(dig +short -x "${ip}")"
done

dig +short ntp1.example.gc.ca ntp2.example.gc.ca
chronyc -n sources                             # the departmental servers, one selected (^*)
```

### Mirror registry and release

```bash
cd ~/ocp-install/inputs
curl --cacert ca-bundle.crt -s -o /dev/null -w '%{http_code}\n' \
  https://registry.example.gc.ca:8443/health/instance          # 200
oc image info --registry-config cluster-pull-secret.json --certificate-authority ca-bundle.crt \
  registry.example.gc.ca:8443/mirror/openshift/release-images@sha256:<release-digest>
```

### BMCs

Check every BMC in the inventory, with TLS verification against the CA that signed the BMC
certificates (the same CA as `bmcVerifyCA` in `install-config.yaml`). `curl -u <user>` without a
password prompts for it, so the password is not on the command line or in the shell history.

```bash
# Redfish (virtual media): HTTP 200 means reachable, TLS verified, and credentials accepted
curl --cacert ~/ocp-install/bmc-ca.crt -u '<bmc-username>' -s -o /dev/null -w '%{http_code}\n' \
  https://10.20.0.10/redfish/v1/Systems/1

# Power state and boot settings of one system
curl --cacert ~/ocp-install/bmc-ca.crt -u '<bmc-username>' -s \
  https://10.20.0.10/redfish/v1/Systems/1 | jq '{PowerState, Boot}'

# Dell iDRAC uses a different system ID
curl --cacert ~/ocp-install/bmc-ca.crt -u '<bmc-username>' -s -o /dev/null -w '%{http_code}\n' \
  https://10.20.0.12/redfish/v1/Systems/System.Embedded.1

# IPMI (PXE alternative only; -a prompts for the password)
ipmitool -I lanplus -H 10.20.0.12 -U '<bmc-username>' -a power status
```

A `000` code means the BMC is unreachable or its certificate isn't trusted. With virtual media,
every BMC address in `install-config.yaml` must use a virtual-media driver
(`redfish-virtualmedia://` or `idrac-virtualmedia://`); `redfish+http://` (no TLS) is not
acceptable in this design (SC-8).
