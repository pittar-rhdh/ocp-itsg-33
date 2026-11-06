# Node Management

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Nodes are managed through the Bare Metal Operator: a `BareMetalHost` (BMH) and BMC Secret per server
in `openshift-machine-api`; workers come from scaling the worker `MachineSet` (Red Hat: *Installing on
bare metal*, "Expanding the cluster"). Every change needs a change ticket and inventory update (CM-8).

## Add a worker node

| | |
|---|---|
| **Purpose** | Add a bare-metal worker with Redfish virtual media (AD-11), static addressing, and the existing workers' security settings |
| **When** | Capacity need or replacement hardware |
| **Roles** | Performs: platform operator, with the data centre team (racking, BMC, firmware). Approves: change board |
| **Prerequisites** | Server racked; BMC on the BMC network with a departmental certificate; firmware supports virtual media; UEFI and Secure Boot on, old boot entries removed. BMC user and password in 0600 files. DNS A/PTR and an IP reserved. Boot MAC and a by-path or WWN root device ([Host fields](../03-cluster-install/install-config.md#host-fields)). Mirror registry reachable |
| **Controls** | CM-2, CM-3, CM-8, MA-2, SC-8, SC-28 |

### Procedure

1. Write `bmh-openshift-worker-3.yaml` (reviewed by a second person). Unlike Red Hat's example,
   credentials stay only in the Secret and certificate verification stays on:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata: {name: openshift-worker-3-network-config-secret, namespace: openshift-machine-api}
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
   metadata: {name: openshift-worker-3, namespace: openshift-machine-api}
   spec:
     online: true
     bootMACAddress: "52:54:00:00:00:50"
     bootMode: UEFI
     bmc:
       address: redfish-virtualmedia://10.20.0.23/redfish/v1/Systems/1   # Dell: idrac-virtualmedia://
       credentialsName: openshift-worker-3-bmc-secret
       disableCertificateVerification: false                            # SC-8: never true
     rootDeviceHints: {deviceName: /dev/disk/by-path/pci-0000:00:17.0-ata-1}
     preprovisioningNetworkDataName: openshift-worker-3-network-config-secret
   ```

2. Create the BMC Secret (password never on the command line) and the host, then, once it is
   `available`, scale the worker MachineSet up by one:

   ```bash
   N=openshift-worker-3
   oc create secret generic "${N}-bmc-secret" -n openshift-machine-api \
     --from-file=username=bmc-user.txt --from-file=password=bmc-password.txt
   oc create -f bmh-openshift-worker-3.yaml
   oc get bmh -n openshift-machine-api "${N}" -w    # registering → inspecting → available
   oc get machinesets -n openshift-machine-api
   oc scale --replicas=<current+1> machineset <worker-machineset> -n openshift-machine-api
   oc get bmh -n openshift-machine-api "${N}" -w    # provisioning → provisioned (30+ min)
   oc get nodes -w; oc get csr | grep Pending       # approve CSRs only if they stay pending
   ```

### Verification

```bash
oc get node <node-name>; oc get mcp worker                  # Ready; UPDATED True, count +1
# Expect FIPS 1, a LUKS crypt device (TPM 2.0, AD-06), chrony sources (install-time MachineConfigs)
oc debug --quiet node/<node-name> -- chroot /host sh -c \
  'cat /proc/sys/crypto/fips_enabled; lsblk -o NAME,TYPE | grep crypt; chronyc -n sources'
oc get fileintegritynodestatuses -n openshift-file-integrity | grep <node-name>
```

### Rollback

Scale the MachineSet back; when the host is `available`, delete the BMH and both Secrets.

### Records

Change ticket, reviewed YAML (no BMC password), verification output, inventory update.

## Replace or decommission a worker

| | |
|---|---|
| **Purpose** | Remove a failed worker and replace it, or remove a server permanently and dispose of its media |
| **When** | Hardware fault; end of life |
| **Roles** | Performs: platform operator, then data centre team. Approves: change board (replace), system owner (decommission). Media disposal: IT security (ITSP.40.006) |
| **Prerequisites** | Workloads tolerate one fewer node (PodDisruptionBudgets); not one of the three infra workers (AD-17) unless their role has moved |
| **Controls** | CM-8, MA-2, MP-6, CP-10 |

### Procedure

1. If the node still answers, [drain it](#drain-and-cordon-for-maintenance).
2. Mark its Machine for deletion, scale down by one, and delete the host:

   ```bash
   H=<failed-host>
   M=$(oc get bmh "${H}" -n openshift-machine-api -o jsonpath='{.spec.consumerRef.name}')
   oc annotate machine "${M}" -n openshift-machine-api machine.openshift.io/delete-machine=true
   oc scale --replicas=<current-1> machineset <worker-machineset> -n openshift-machine-api
   oc get bmh "${H}" -n openshift-machine-api -w    # wait for available (or error)
   oc delete bmh "${H}" -n openshift-machine-api    # then its two Secrets
   ```

3. Clear the TPM in firmware, then sanitize or destroy the disks per ITSP.40.006 for Protected B
   (LUKS2/TPM and BMO disk cleaning are not documented sanitization methods).
4. Replace: [add the new server](#add-a-worker-node) (new MAC; same IP and name if reused).
   Decommission: remove DNS records, IP reservation, BMC account, and inventory entry.

### Verification

`oc get bmh,machines -n openshift-machine-api` and `oc get nodes` no longer list the old host, no
error states; replacement `Ready`; disposal certificate on file.

### Rollback

None once the Machine is deleted; before step 3 the server can be re-added as a new worker.

### Records

Change ticket, hardware fault reference, inventory update, media sanitization or destruction record.

## Replace a failed control plane node

| | |
|---|---|
| **Purpose** | Replace one of three control plane nodes while etcd keeps quorum on the other two |
| **When** | Control plane hardware failure |
| **Roles** | Performs: two platform operators. Approves: system owner (high-risk change) |
| **Prerequisites** | Two healthy control plane nodes; a fresh [etcd backup](backup-and-restore.md#etcd-backup); replacement server prepared as for a worker |
| **Controls** | CP-10, CM-3, MA-2 |

### Procedure

Follow Red Hat exactly: *Backup and restore* → "Replacing an unhealthy etcd member", and
*Installing on bare metal* → "Replacing a bare-metal control plane node". Outline: remove the failed
etcd member; delete the old BMH and `Machine`; create the BMC Secret and a BMH as in Red Hat's example
plus this guide's `rootDeviceHints` and `preprovisioningNetworkDataName`; create a `master` `Machine`
copying `providerSpec` from a healthy one (no control plane MachineSet here); finish the etcd procedure.

### Verification

Three `Ready` masters; `oc get pods -n openshift-etcd`; `oc get co etcd kube-apiserver` not degraded;
`oc get mcp master` updated; FIPS, LUKS, chrony as for a worker.

### Rollback

Last resort only: [etcd restore](backup-and-restore.md#etcd-restore).

### Records

Change ticket, etcd member list before and after, verification output.

## Drain and cordon for maintenance

| | |
|---|---|
| **Purpose** | Take a node out of service for hardware, firmware, or BMC maintenance |
| **When** | Planned maintenance |
| **Roles** | Performs: platform operator. Informed: owners of affected workloads |
| **Prerequisites** | One node at a time; no upgrade or MachineConfig rollout in progress (`oc get mcp`) |
| **Controls** | MA-2, MA-4, CM-3 |

### Procedure

```bash
NODE=<node-name>; H=<bmh-name>
oc adm cordon "${NODE}"
# If a PodDisruptionBudget blocks the drain (oc get pdb -A), agree the next step with its owner;
# never force-delete platform pods.
oc adm drain "${NODE}" --ignore-daemonsets --delete-emptydir-data --timeout=30m
# Power off through the BMO (power changes made at the BMC are reverted)
oc patch bmh "${H}" -n openshift-machine-api --type merge -p '{"spec":{"online":false}}'
# ... maintenance ...
oc patch bmh "${H}" -n openshift-machine-api --type merge -p '{"spec":{"online":true}}'
oc wait --for=condition=Ready node/"${NODE}" --timeout=30m && oc adm uncordon "${NODE}"
```

### Verification

Node `Ready` and schedulable; `oc get mcp` updated; boots without a passphrase prompt (TPM unlock).

### Rollback

`oc adm uncordon "${NODE}"`.

### Records

Maintenance record (MA-2): work done, by whom, firmware versions before and after.

## BMC credential rotation

| | |
|---|---|
| **Purpose** | Rotate the BMC password used by OpenShift |
| **When** | After installation; on the departmental schedule; when someone with access leaves |
| **Roles** | Performs: data centre team (BMC) and platform operator (Secret). Approves: change ticket |
| **Prerequisites** | New password in a 0600 file; no provisioning or power operation running (`oc get bmh -n openshift-machine-api`) |
| **Controls** | IA-5, IA-5(1), AC-2, MA-4 |

### Procedure

Change the password on the BMC, then immediately update the host's Secret:

```bash
H=<bmh-name>
S=$(oc get bmh "${H}" -n openshift-machine-api -o jsonpath='{.spec.bmc.credentialsName}')
oc create secret generic "${S}" -n openshift-machine-api \
  --from-file=username=bmc-user.txt --from-file=password=bmc-password.txt \
  --dry-run=client -o yaml | oc apply -f -
shred -u bmc-password.txt
```

### Verification

After a few minutes, `oc get bmh "${H}" -n openshift-machine-api -o jsonpath='{.status.operationalStatus} {.status.errorType}'`
shows `OK` and no error.

### Rollback

Set the previous password on the BMC and re-apply the previous Secret from the vault.

### Records

Change ticket, hosts rotated, vault update reference (never the password).
