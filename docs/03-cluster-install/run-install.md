# Run and Verify the Install

[← Phase 3](index.md)

## Before you start

- [ ] Change approved, installation window booked (CM-3)
- [ ] `01-check-provisioner.sh` and `02-validate-environment.sh` pass; the environment report is in
      `EVIDENCE_DIR`
- [ ] `03-render-install-config.sh` and `04-create-manifests.sh` ran; the manifests were reviewed
      (second person, CM-5)
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
```

Power off with your BMC tooling; Red Hat's example uses IPMI
(`ipmitool -I lanplus -U <user> -P <password> -H <bmc> power off`). With Redfish, use the
vendor tool or the Redfish `ComputerSystem.Reset` action with `ForceOff`.

## Install

```bash
03-install/05-install-cluster.sh
```

It checks the installer checksum, FIPS mode on the provisioner, and leftover bootstrap VMs, then
runs `openshift-install-fips create cluster --dir ${INSTALL_DIR}`. Red Hat's overview of what
happens:

1. The bootstrap VM starts on the provisioner and runs the metal3 services (Ironic, image
   customization, httpd, and, with PXE, dnsmasq).
2. Each node is **registered** (BMC credentials checked), **inspected**, **cleaned** (all disks
   are wiped), and **deployed**: the Ironic Python Agent writes RHCOS to the disk chosen by
   `rootDeviceHints`.
3. Control passes from the bootstrap VM to the control plane; the bootstrap VM is deleted and the
   VIPs move to the nodes.
4. The Bare Metal Operator deploys the workers.

Follow progress in `${INSTALL_DIR}/.openshift_install.log`. The console log and the installer log
are kept in `EVIDENCE_DIR` (mode 0600).

### If something fails

| Symptom | Next step |
|---|---|
| The installer timed out at the end but the cluster looks healthy | `openshift-install-fips wait-for install-complete --dir ${INSTALL_DIR} --log-level debug` |
| Bootstrap problems | `openshift-install-fips gather bootstrap --dir ${INSTALL_DIR}`; `sudo virsh console <bootstrap-vm>` |
| `ironic-inspector inspection failed: No disks satisfied root device hints` | Fix `rootDeviceHints` (use by-path or WWN), start again from a new directory |
| A node never powers on or mounts the virtual media | BMC firmware version, Redfish address and system ID, BMC reaching the provisioner on 6180/6183, Dell AutoAttach for virtual media |
| Image pull errors | Mirror registry health, `imageDigestSources`, CA bundle, pull-only robot permissions (`02-validate-environment.sh`) |
| Certificate errors to BMCs | `BMC_CA_BUNDLE` must contain the CA that signed the BMC certificates |

A failed install leaves wiped disks and a used installation directory: start again from a new
directory after fixing the cause. Phase 6 has the full troubleshooting SOP.

## After the install

```bash
export KUBECONFIG=~/ocp-install/ocp1/auth/kubeconfig
03-install/06-post-install.sh --configure
```

`--configure` applies the Day-1 settings described in
[Install-time security settings](install-time-security.md#settings-applied-right-after-installation),
then the script verifies:

- ClusterVersion is Available and runs the **transferred release digest**;
- every cluster operator is Available and not Degraded; every node is Ready; every
  `BareMetalHost` is provisioned;
- on every node (through `oc debug`): FIPS enabled, a LUKS (`crypt`) device present, chrony
  synchronized to a source;
- IPsec mode; default OperatorHub sources disabled; IDMS and catalog sources present;
- etcd encryption type and status; audit profile;
- whether `kubeadmin` still exists.

The report is written to `EVIDENCE_DIR` and added to its `SHA256SUMS`. Keep the whole evidence
directory (it is Protected B once populated) with the change record.

## Credentials

| Credential | Action |
|---|---|
| `auth/kubeconfig` (system:admin) | Break-glass. Seal in the departmental vault immediately; remove from the provisioner once the identity provider works (AC-2, AC-6(9)). |
| `auth/kubeadmin-password` | Keep sealed until an identity provider and a cluster-admin group work (Phase 4), then delete the `kubeadmin` secret (`oc delete secret kubeadmin -n kube-system`). |
| BMC passwords | Rotate on every BMC after installation and update the `BareMetalHost` secrets in `openshift-machine-api` (Phase 6 SOP); delete `bmc-credentials.env` and the install-config backup (IA-5). |
| `kni` sudo rule | Remove it (or decommission the provisioner) after installation (AC-6). |
| SSH key for `core` | Keep the private key in the vault; node SSH access is for break-glass only (AC-17). |

## Hand-off to Phase 4

| Item | Location |
|---|---|
| Running cluster, Day-1 settings applied | API `https://api.<cluster>.<domain>:6443` |
| Break-glass credentials | Departmental vault |
| Install records | `EVIDENCE_DIR`: environment check, redacted install-config, manifests and checksums, install logs, post-install report |
| Mirrored catalog sources | `openshift-marketplace` (used to install OpenShift GitOps) |
