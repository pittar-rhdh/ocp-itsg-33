# Prerequisites and Provisioner Host

[← Phase 3](index.md)

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
addresses for the provisioning services. The VIPs must be inside `MACHINE_NETWORK_CIDR` (the
render script checks this).

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
`02-validate-environment.sh` checks all of this from the provisioner.

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
sudo dnf install -y libvirt qemu-kvm mkisofs python3-devel jq ipmitool nmstate python3-pyyaml bind-utils
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

For PXE, add a `provisioning` bridge on the provisioning NIC with an address in
`PROVISIONING_NETWORK_CIDR` (Red Hat's example uses `172.22.0.254/24`). Back up the result with
`nmstatectl show > backup-nmstate.yml`.

### Phase 2 hand-off

Copy these from the registry host into `INPUTS_DIR` (default `~/ocp-install/inputs`), for
example with `scp` over the MRZ management network:

| File | From the registry host |
|---|---|
| `release.env`, `openshift-install-fips` | `/data/ocp/installer/<version>/` |
| `idms-oc-mirror.yaml` | `/data/ocp/cluster-resources/current/` |
| `cluster-resources/` (whole directory) | `/data/ocp/cluster-resources/current/` (used after install) |
| `cluster-pull-secret.json` (mode 0600) | `CLUSTER_PULL_SECRET_FILE` |
| `ca-bundle.crt` | `TLS_CA_BUNDLE` |
| `oc`, `butane` | `/data/ocp/tools/<version>/bin/` |

`01-check-provisioner.sh` verifies the installer against the checksum in `release.env` and that
it is pinned to the transferred release.

## Checks

```bash
03-install/01-check-provisioner.sh     # host, packages, bridges, firewall, SSH key, hand-off
03-install/02-validate-environment.sh  # DNS, PTR, registry, NTP, every BMC (report kept as evidence)
```
