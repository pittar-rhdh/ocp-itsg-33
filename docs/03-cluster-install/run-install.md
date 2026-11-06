# Run and Verify the Install

[← Phase 3](index.md)

> **Examples only — not validated.** The commands on this page have not been run against a real
> installation. Test and adapt them before use. See
> [Validation status](../reference/validation-status.md).

The commands use the example locations from the other Phase 3 pages:

```bash
INSTALL_DIR=~/ocp-install/ocp1
EVIDENCE_DIR=~/ocp-install/evidence/ocp1
export PATH=~/ocp-install/inputs:$PATH
```

## Before you start

- [ ] Change approved, installation window booked (CM-3)
- [ ] The [checks](prerequisites.md#checks) pass; their output is in `EVIDENCE_DIR`
- [ ] [install-config.yaml](install-config.md#prepare-the-file) is prepared and the
      [manifests](install-time-security.md#add-the-manifests) are added and reviewed (second
      person, CM-5)
- [ ] All cluster nodes are **powered off** (Red Hat's procedure)
- [ ] No bootstrap VM or storage pool is left from an earlier attempt
- [ ] The vault entry for the break-glass credentials is ready

Red Hat's clean-up for a previous attempt:

```bash
for i in $(sudo virsh list | tail -n +3 | grep bootstrap | awk '{print $2}'); do
  sudo virsh destroy $i; sudo virsh undefine $i
  sudo virsh vol-delete $i --pool $i; sudo virsh vol-delete $i.ign --pool $i
  sudo virsh pool-destroy $i; sudo virsh pool-undefine $i
done
sudo virsh list --all | grep bootstrap      # no output
```

Power off every node through its BMC. With Redfish, use the `ComputerSystem.Reset` action;
Red Hat's example uses IPMI:

```bash
# Redfish (prompts for the BMC password)
curl --cacert ~/ocp-install/bmc-ca.crt -u '<bmc-username>' -X POST \
  -H 'Content-Type: application/json' -d '{"ResetType": "ForceOff"}' \
  https://10.20.0.10/redfish/v1/Systems/1/Actions/ComputerSystem.Reset

# IPMI (PXE alternative only)
ipmitool -I lanplus -H 10.20.0.12 -U '<bmc-username>' -a power off
```

## Install

```bash
fips-mode-setup --check                                 # FIPS mode is enabled.
sha256sum ~/ocp-install/inputs/openshift-install-fips   # the checksum recorded in Phase 2

stamp=$(date +%Y%m%d-%H%M%S)
openshift-install-fips create cluster --dir "${INSTALL_DIR}" --log-level info 2>&1 \
  | tee "${EVIDENCE_DIR}/install-${stamp}.log"

# Keep the installer's detailed log; protect the logs and credentials
cp "${INSTALL_DIR}/.openshift_install.log" "${EVIDENCE_DIR}/openshift_install-${stamp}.log"
chmod 0600 "${EVIDENCE_DIR}"/*.log "${INSTALL_DIR}"/auth/*
(cd "${EVIDENCE_DIR}" && sha256sum install-${stamp}.log openshift_install-${stamp}.log >> SHA256SUMS)
```

Red Hat's overview of what happens:

1. The bootstrap VM starts on the provisioner and runs the metal3 services (Ironic, image
   customization, httpd, and, with PXE, dnsmasq).
2. Each node is **registered** (BMC credentials checked), **inspected**, **cleaned** (all disks
   are wiped), and **deployed**: the Ironic Python Agent writes RHCOS to the disk chosen by
   `rootDeviceHints`.
3. Control passes from the bootstrap VM to the control plane; the bootstrap VM is deleted and the
   VIPs move to the nodes.
4. The Bare Metal Operator deploys the workers.

Follow progress with `tail -f ${INSTALL_DIR}/.openshift_install.log`.

As soon as the installer finishes, seal `auth/kubeconfig` and `auth/kubeadmin-password` in the
departmental vault (see [Credentials](#credentials)).

### If something fails

| Symptom | Next step |
|---|---|
| The installer timed out at the end but the cluster looks healthy | `openshift-install-fips wait-for install-complete --dir ${INSTALL_DIR} --log-level debug` |
| Bootstrap problems | `openshift-install-fips gather bootstrap --dir ${INSTALL_DIR}`; `sudo virsh console <bootstrap-vm>` |
| `ironic-inspector inspection failed: No disks satisfied root device hints` | Fix `rootDeviceHints` (use by-path or WWN), start again from a new directory |
| A node never powers on or mounts the virtual media | BMC firmware version, Redfish address and system ID, BMC reaching the provisioner on 6180/6183, Dell AutoAttach for virtual media |
| Image pull errors | Mirror registry health, `imageDigestSources`, CA bundle, pull-only robot permissions ([registry checks](prerequisites.md#mirror-registry-and-release)) |
| Certificate errors to BMCs | `bmcVerifyCA` must contain the CA that signed the BMC certificates |

A failed install leaves wiped disks and a used installation directory: start again from a new
directory after fixing the cause. See also [Troubleshooting](../06-sops/troubleshooting.md).

## Day-1 settings

Apply the settings described in
[Install-time security settings](install-time-security.md#settings-applied-right-after-installation)
before any workload runs. Phase 4 (GitOps) takes ownership of them later.

```bash
export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig
oc whoami                                    # system:admin

# CM-7: disable the default (internet) OperatorHub sources
oc patch operatorhub cluster --type merge -p '{"spec":{"disableAllDefaultSources":true}}'

# CM-11, SI-7: mirrored catalogs, ITMS, and release signatures from oc-mirror.
# Skip updateService.yaml: its CRD needs the OpenShift Update Service operator (Phase 4/6).
cd ~/ocp-install/inputs/cluster-resources
for f in *.yaml; do
  [ "${f}" = updateService.yaml ] && continue
  oc apply -f "${f}"
done

# SC-28: etcd encryption; AU-2, AU-12: audit profile
oc patch apiserver cluster --type merge \
  -p '{"spec":{"encryption":{"type":"aesgcm"},"audit":{"profile":"WriteRequestBodies"}}}'
```

etcd encryption runs in the background and can take some time to finish.

## Verify

Record the output in `EVIDENCE_DIR` (for example with
`script ${EVIDENCE_DIR}/post-install-$(date +%Y%m%d).txt`) and add it to `SHA256SUMS`.

```bash
# Release and health
oc get clusterversion                                   # 4.22.z, Available True
oc get clusterversion version -o jsonpath='{.status.desired.image}{"\n"}'   # ...@sha256:<release-digest> (the transferred release)
oc get clusteroperators                                 # all Available True, Degraded False
oc get nodes                                            # all Ready
oc get baremetalhosts -n openshift-machine-api          # all provisioned

# On every node: FIPS (1), LUKS device (crypt), chrony source selected (^*)
for n in $(oc get nodes -o name); do
  echo "== ${n}"
  oc debug "${n}" --quiet -- chroot /host sh -c \
    'cat /proc/sys/crypto/fips_enabled; lsblk -o NAME,TYPE | grep crypt; chronyc -n sources'
done

# IPsec and content sources
oc get network.operator cluster \
  -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.ipsecConfig.mode}{"\n"}'   # Full
oc get operatorhub cluster -o jsonpath='{.spec.disableAllDefaultSources}{"\n"}'      # true
oc get imagedigestmirrorsets
oc get catalogsource -n openshift-marketplace

# etcd encryption and audit profile
oc get apiserver cluster -o jsonpath='{.spec.encryption.type} {.spec.audit.profile}{"\n"}'   # aesgcm WriteRequestBodies
oc get openshiftapiserver cluster \
  -o jsonpath='{.status.conditions[?(@.type=="Encrypted")].reason}{"\n"}'   # EncryptionCompleted when done
oc get kubeapiserver cluster \
  -o jsonpath='{.status.conditions[?(@.type=="Encrypted")].reason}{"\n"}'

# kubeadmin still exists until Phase 4
oc get secret kubeadmin -n kube-system
```

Keep the whole evidence directory (it is Protected B once populated) with the change record.

## Credentials

| Credential | Action |
|---|---|
| `auth/kubeconfig` (system:admin) | Break-glass. Seal in the departmental vault immediately; remove from the provisioner once the identity provider works (AC-2, AC-6(9)). |
| `auth/kubeadmin-password` | Keep sealed until an identity provider and a cluster-admin group work. It is removed in Phase 4: after an IdP administrator can log in, `oc delete secret kubeadmin -n kube-system`. |
| BMC passwords | Rotate on every BMC after installation and update the `BareMetalHost` secrets in `openshift-machine-api` ([BMC credential rotation](../06-sops/node-management.md#bmc-credential-rotation)); delete the install-config working copy `~/ocp-install/install-config.ocp1.yaml` (IA-5). |
| `kni` sudo rule | Remove it (or decommission the provisioner) after installation (AC-6). |
| SSH key for `core` | Keep the private key in the vault; node SSH access is for break-glass only (AC-17). |

## Hand-off to Phase 4

| Item | Location |
|---|---|
| Running cluster, Day-1 settings applied | API `https://api.<cluster>.<domain>:6443` |
| Break-glass credentials | Departmental vault |
| Install records | `EVIDENCE_DIR`: environment checks, redacted install-config, manifests and checksums, install logs, post-install verification |
| Mirrored catalog sources | `openshift-marketplace` (used to install OpenShift GitOps) |
