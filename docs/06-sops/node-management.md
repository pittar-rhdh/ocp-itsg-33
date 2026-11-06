# Node Management

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Bare-metal nodes are managed through the Bare Metal Operator: a `BareMetalHost` (BMH) per server
in `openshift-machine-api`, BMC credentials in a Secret, and worker `Machine`s created by scaling
the worker `MachineSet`. Red Hat's reference is OpenShift 4.22 *Installing on bare metal*,
chapter 5 "Expanding the cluster". All changes need a change ticket (CM-3, MA-2) and update the
hardware inventory (CM-8).

## Add a worker node

### Purpose and scope

Add a bare-metal worker with Redfish virtual media (AD-11), static addressing, and the same
security settings as the existing workers.

### Roles

Performs: platform operator. Supports: data centre team (racking, cabling, BMC network, firmware).
Approves: change board.

### Prerequisites

- Server racked, BMC on the BMC network with a departmental certificate, firmware at the level
  required for virtual media, UEFI and Secure Boot enabled, old UEFI boot entries removed.
- BMC account created for OpenShift; username and password in files (mode 0600) on the admin host.
- DNS A and PTR records for the node; an IP address reserved on the machine network.
- The node's boot MAC address and a persistent root device path (by-path or WWN), as in
  [Host fields](../03-cluster-install/install-config.md#host-fields).
- The mirror registry is reachable: the node pulls the release images during provisioning.

### Procedure

1. Create the BMC Secret without putting the password on the command line:

   ```bash
   N=openshift-worker-3
   oc create secret generic "${N}-bmc-secret" -n openshift-machine-api \
     --from-file=username=bmc-user.txt --from-file=password=bmc-password.txt
   ```

2. Create the NMState network Secret and the `BareMetalHost` (`bmh-openshift-worker-3.yaml`,
   reviewed by a second person):

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: openshift-worker-3-network-config-secret
     namespace: openshift-machine-api
   type: Opaque
   stringData:
     nmstate: |
       interfaces:
         - name: eno1
           type: ethernet
           state: up
           mac-address: "52:54:00:00:00:50"
           ipv4: {enabled: true, dhcp: false, address: [{ip: 10.10.0.23, prefix-length: 24}]}
           ipv6: {enabled: false}
       dns-resolver: {config: {server: [10.10.0.2]}}
       routes: {config: [{destination: 0.0.0.0/0, next-hop-address: 10.10.0.1, next-hop-interface: eno1}]}
   ---
   apiVersion: metal3.io/v1alpha1
   kind: BareMetalHost
   metadata:
     name: openshift-worker-3
     namespace: openshift-machine-api
   spec:
     online: true
     bootMACAddress: "52:54:00:00:00:50"
     bootMode: UEFI
     bmc:
       address: redfish-virtualmedia://10.20.0.23/redfish/v1/Systems/1   # Dell: idrac-virtualmedia://...
       credentialsName: openshift-worker-3-bmc-secret
       disableCertificateVerification: false                            # SC-8: never true
     rootDeviceHints:
       deviceName: /dev/disk/by-path/pci-0000:00:17.0-ata-1
     preprovisioningNetworkDataName: openshift-worker-3-network-config-secret
   ```

   ```bash
   oc create -f bmh-openshift-worker-3.yaml
   oc get bmh -n openshift-machine-api "${N}" -w     # registering → inspecting → available
   ```

   Red Hat's example also shows `bmc.username` and `bmc.password` and sets
   `disableCertificateVerification: True`; this guide keeps credentials only in the Secret and
   keeps verification on.

3. When the host is `available`, scale the worker MachineSet by one:

   ```bash
   oc get machinesets -n openshift-machine-api
   oc scale --replicas=<current+1> machineset <worker-machineset> -n openshift-machine-api
   oc get bmh -n openshift-machine-api "${N}" -w     # provisioning → provisioned (30 min or more)
   ```

4. Wait for the node, and approve CSRs only if they stay pending (normally the machine approver
   handles IPI machines): `oc get nodes -w`, `oc get csr | grep Pending`.

### Verification

```bash
oc get node <node-name>                                     # Ready, role worker
oc get mcp worker                                           # UPDATED True, machine count +1
oc debug --quiet node/<node-name> -- chroot /host sh -c \
  'cat /proc/sys/crypto/fips_enabled; lsblk -o NAME,TYPE | grep crypt; chronyc -n sources'
oc get fileintegritynodestatuses -n openshift-file-integrity | grep <node-name>
```

FIPS (`1`), the LUKS device (TPM 2.0, AD-06), and chrony come from the worker MachineConfigs
created at install time (`03-install/manifests/99-worker-*.bu`), which the Machine Config Operator
serves to every new worker. The next Compliance Operator node scan includes the node.

### Rollback

Scale the MachineSet back, wait for the host to return to `available`, then
`oc delete bmh "${N}" -n openshift-machine-api` and delete both Secrets.

### Records and evidence

Change ticket, reviewed YAML (without the BMC password), verification output, inventory update.

### Related controls

CM-2, CM-3, CM-8, MA-2, SC-8, SC-28.

## Replace a failed worker

### Purpose and scope

Remove a failed worker and bring in replacement hardware.

### Roles

As for [Add a worker node](#add-a-worker-node).

### Prerequisites

The workloads tolerate one fewer node (PodDisruptionBudgets, infra components on the remaining
infra workers, AD-17).

### Procedure

1. If the node still answers, drain it ([Drain and cordon](#drain-and-cordon-for-maintenance)).
2. Mark its Machine for deletion and scale the MachineSet down by one:

   ```bash
   M=$(oc get bmh <failed-host> -n openshift-machine-api -o jsonpath='{.spec.consumerRef.name}')
   oc annotate machine "${M}" -n openshift-machine-api machine.openshift.io/delete-machine=true
   oc scale --replicas=<current-1> machineset <worker-machineset> -n openshift-machine-api
   ```

3. When the host is `available` (or in error, if it is dead), delete it:
   `oc delete bmh <failed-host> -n openshift-machine-api`, and its two Secrets.
4. Sanitize or return the old disks ([Decommission](#decommission-a-node)), then add the new server
   with [Add a worker node](#add-a-worker-node) (new MAC, same IP and name if you reuse them).

### Verification

`oc get nodes` shows the new node `Ready`; the old node is gone; `oc get bmh` has no error states.

### Rollback

Not applicable once the Machine is deleted; re-add the original server if it is repaired.

### Records and evidence

Change ticket, hardware fault reference, media disposition record.

### Related controls

CM-8, MA-2, MP-6, CP-10.

## Replace a failed control plane node

### Purpose and scope

Replace one of the three control plane nodes while etcd keeps quorum with the other two. Follow
Red Hat's procedures exactly: *Backup and restore* → "Replacing an unhealthy etcd member", and
*Installing on bare metal* → "Replacing a bare-metal control plane node". This page only frames
them.

### Roles

Performs: two platform operators. Approves: system owner (high-risk change).

### Prerequisites

Two healthy control plane nodes; a fresh [etcd backup](backup-and-restore.md#etcd-backup) (Red Hat
requires one); the replacement server prepared as for a worker.

### Procedure

1. Remove the failed etcd member as in "Replacing an unhealthy etcd member" (the case depends on
   whether the machine is running and whether etcd is crash-looping).
2. Delete the old `BareMetalHost` and `Machine`; the node object is removed by the machine controller.
3. Create the BMC Secret and a `BareMetalHost` with `externallyProvisioned: false`,
   `automatedCleaningMode: disabled`, `bootMode: UEFI`, the Redfish address, and boot MAC (Red Hat's
   example), plus this guide's `rootDeviceHints` and `preprovisioningNetworkDataName`.
4. Create a `Machine` with role `master`, copying `providerSpec` from a healthy control plane
   Machine (there is no control plane MachineSet in this design).
5. Complete the etcd member procedure: Red Hat notes the new etcd pod crash-loops until it does.

### Verification

`oc get nodes` three `Ready` masters; `oc get pods -n openshift-etcd`; `oc get co etcd kube-apiserver`
available and not degraded; `oc get mcp master` updated; FIPS, LUKS, and chrony checks as for a worker.

### Rollback

Restore from the etcd backup only as a last resort ([etcd restore](backup-and-restore.md#etcd-restore)).

### Records and evidence

Change ticket, etcd member list before and after, verification output.

### Related controls

CP-10, CM-3, MA-2.

## Drain and cordon for maintenance

### Purpose and scope

Take a node out of service for hardware, firmware, or BMC maintenance.

### Roles

Performs: platform operator. Informed: application owners of affected workloads.

### Prerequisites

One node at a time; no upgrade or MachineConfig rollout in progress (`oc get mcp`).

### Procedure

```bash
NODE=<node-name>; H=<bmh-name>
oc adm cordon "${NODE}"
oc adm drain "${NODE}" --ignore-daemonsets --delete-emptydir-data --timeout=30m
# Power off through the Bare Metal Operator (powering off at the BMC is reverted by the BMO)
oc patch bmh "${H}" -n openshift-machine-api --type merge -p '{"spec":{"online":false}}'
# ... maintenance ...
oc patch bmh "${H}" -n openshift-machine-api --type merge -p '{"spec":{"online":true}}'
oc wait --for=condition=Ready node/"${NODE}" --timeout=30m
oc adm uncordon "${NODE}"
```

If the drain stops on a PodDisruptionBudget, find it with `oc get pdb -A` and agree the next step
with the owner; never force-delete platform pods.

### Verification

Node `Ready` and schedulable; `oc get mcp` updated; the TPM still unlocks the disk (the node boots
without a passphrase prompt).

### Rollback

`oc adm uncordon "${NODE}"`.

### Records and evidence

Maintenance record (MA-2): what was done, by whom, the firmware versions before and after.

### Related controls

MA-2, MA-4, CM-3.

## BMC credential rotation

### Purpose and scope

Rotate the BMC password used by OpenShift: after installation, on the departmental schedule, and
when someone with access leaves.

### Roles

Performs: data centre team (BMC) with the platform operator (Secret). Approves: change ticket.

### Prerequisites

The new password in a file (mode 0600). No provisioning or power operation running
(`oc get bmh -n openshift-machine-api`).

### Procedure

1. Change the password on the BMC.
2. Update the Secret the host uses, straight away:

   ```bash
   H=<bmh-name>
   S=$(oc get bmh "${H}" -n openshift-machine-api -o jsonpath='{.spec.bmc.credentialsName}')
   oc create secret generic "${S}" -n openshift-machine-api \
     --from-file=username=bmc-user.txt --from-file=password=bmc-password.txt \
     --dry-run=client -o yaml | oc apply -f -
   shred -u bmc-password.txt
   ```

### Verification

`oc get bmh "${H}" -n openshift-machine-api -o jsonpath='{.status.operationalStatus} {.status.errorType}{"\n"}'`
shows `OK` and no error after a few minutes.

### Rollback

Set the previous password on the BMC and re-apply the previous Secret from the vault.

### Records and evidence

Change ticket, list of hosts rotated, vault update reference (never the password).

### Related controls

IA-5, IA-5(1), AC-2, MA-4.

## Decommission a node

### Purpose and scope

Remove a server permanently and dispose of its media.

### Roles

Performs: platform operator, then data centre team. Approves: system owner. Media disposal: IT
security (ITSP.40.006).

### Prerequisites

Capacity remains for the workloads; the node is not one of the three infra workers unless their
role has moved.

### Procedure

1. Follow steps 1–3 of [Replace a failed worker](#replace-a-failed-worker).
2. Remove the node's DNS records, IP reservation, BMC account, and inventory entry.
3. Sanitize the media. The root disk is LUKS2-encrypted with a key sealed to the server's TPM
   (AD-06), and the Bare Metal Operator's cleaning removes disk metadata, but neither is a
   documented sanitization method. Clear the TPM in firmware and then sanitize or destroy the
   disks as ITSP.40.006 requires for Protected B.

### Verification

`oc get bmh`, `oc get machines`, and `oc get nodes` no longer list it; the disposal certificate is
on file.

### Rollback

Before step 3, the server can be re-added as a new worker.

### Records and evidence

Change ticket, inventory update, media sanitization or destruction record.

### Related controls

CM-8, MP-6, MA-2.
