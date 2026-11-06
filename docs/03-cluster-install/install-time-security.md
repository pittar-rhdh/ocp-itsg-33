# Install-Time Security Settings

[← Phase 3](index.md)

Some protections can only be set when the cluster is installed. Getting them wrong means
reinstalling the cluster, so they are generated from reviewed templates and checked after the
install.

| Setting | Where | Can it be changed later? | Control |
|---|---|---|---|
| FIPS mode | `install-config.yaml` (`fips: true`) | **No** | SC-13 |
| Boot disk encryption (LUKS2, TPM 2.0) | `openshift/99-{master,worker}-disk-encryption.yaml` | **No** (reinstall or reprovision the node) | SC-28 |
| OVN-Kubernetes IPsec | `manifests/cluster-network-03-config.yml` | Yes, but enabling later causes a rollout; set it from the start | SC-8 |
| chrony (departmental NTP) | `openshift/99-{master,worker}-chrony.yaml` | Yes | AU-8 |
| Cluster, service, and join networks | `install-config.yaml` | **No** | SC-7 |
| Mirror-only image sources and trust | `imageDigestSources`, `additionalTrustBundle` | Yes | CM-11, SI-7 |
| SSH key for `core` | `sshKey` (RSA/ECDSA in FIPS mode) | Yes (MachineConfig) | IA-5 |

`04-create-manifests.sh` adds the manifests after `openshift-install-fips create manifests`,
using Butane for the MachineConfigs, and keeps a copy (with checksums) in `EVIDENCE_DIR`, because
the installer consumes them.

## FIPS

- `fips: true` in `install-config.yaml`.
- Red Hat (since 4.16): the installer must run on a **RHEL 9 host in FIPS mode**, and must be the
  **FIPS-capable** installer (`openshift-install-fips`, extracted in Phase 2). `05-install-cluster.sh`
  refuses to start on a non-FIPS host.
- Red Hat: FIPS 140 validation applies to the RHEL cryptographic libraries on x86_64, ppc64le, and
  s390x. Check the current CMVP status for the RHEL 9 modules in your release (ITSP.40.111).
- In FIPS mode the SSH key must be RSA or ECDSA (Red Hat), and the Butane disk-encryption config
  must include `openshift: fips: true`.

## Boot disk encryption (AD-06)

Red Hat 4.22 (*Installation configuration → Customizing nodes → Boot disk encryption and
mirroring*):

- Modes are **TPM v2** (preferred) and **Tang**. Disks are encrypted with **LUKS2, AES-256-XTS**,
  from first boot, without anyone entering a passphrase.
- **Tang is supported only for bare-metal and vSphere installations on user-provisioned
  infrastructure.** This design uses IPI, so it uses TPM 2.0 only. (A TPM-only binding protects
  data on a disk removed from its server; it doesn't protect a whole stolen server. Record this in
  the TRA, and rely on physical security (PE) for whole-server theft.)
- Encryption covers the installation (boot) disk only, not workload disks. Workload data is
  protected by the storage array or CSI encryption (AD-13).

The template (`03-install/manifests/99-ROLE-disk-encryption.bu.tmpl`) renders to:

```yaml
variant: openshift
version: 4.22.0
metadata:
  name: 99-worker-disk-encryption
  labels:
    machineconfiguration.openshift.io/role: worker
boot_device:
  layout: x86_64
  luks:
    tpm2: true
openshift:
  fips: true
```

Butane 0.29 (transferred in Phase 1) converts it to a MachineConfig with a LUKS device bound to the
TPM through Clevis. Every node needs TPM 2.0 enabled in firmware. Set `DISK_ENCRYPTION=none` only
with a recorded justification; the script warns.

## IPsec (AD-05)

`manifests/cluster-network-03-config.yml`:

```yaml
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  defaultNetwork:
    type: OVNKubernetes
    ovnKubernetesConfig:
      ipsecConfig:
        mode: Full
```

`mode` accepts `Disabled`, `External`, and `Full` (from the `operator.openshift.io/v1` Network API
in `openshift/api`, release-4.22). `Full` encrypts pod-to-pod traffic between nodes. The field
names come from the API source; the install-time procedure (adding this file in the `manifests`
directory) follows the pattern Red Hat documents for network customizations, but was not found as
a 4.22 bare-metal IPI procedure through the documentation search. Confirm in a lab.

## Time (AU-8)

Red Hat: for disconnected clusters, you must configure NTP servers on the nodes. The chrony
template writes `/etc/chrony.conf` for the `master` and `worker` roles with one `server … iburst`
line per entry in `NTP_SERVERS`. `additionalNTPServers` in `install-config.yaml` only helps hosts
sync before installation. Red Hat also notes: define a consistent date and time format in every
node's BIOS, or installation might fail.

## Settings applied right after installation

These can be set after installation, so they're applied by `06-post-install.sh --configure`
before any workload runs, and Phase 4 (GitOps) takes ownership of them afterwards:

| Setting | How | Control |
|---|---|---|
| Disable default (internet) OperatorHub sources | `operatorhub/cluster` `spec.disableAllDefaultSources: true` | CM-7 |
| Mirrored catalogs, ITMS, release signatures | `oc apply` of oc-mirror's cluster resources (not `updateService.yaml`, which needs the OSUS operator) | CM-11, SI-7 |
| etcd encryption | `apiserver/cluster` `spec.encryption.type: aesgcm` | SC-28 |
| API audit profile | `apiserver/cluster` `spec.audit.profile: WriteRequestBodies` | AU-2, AU-12 |
