# Reference Architecture

[← Back to main](../index.md)

This section describes the target architecture for this repository: a single, highly available
**OpenShift Container Platform 4.22** cluster on **bare metal**, installed with the
**installer-provisioned infrastructure (IPI)** method into an **air-gapped** ("high side")
environment. The cluster hosts Protected B workloads at medium integrity and medium availability
(PBMM).

The architecture is kept deliberately light: one cluster, one mirror registry host, and
departmental services (Git, IdP, PKI, SIEM, storage) that are assumed to exist already. The
decisions behind it are recorded in [Architecture decisions](architecture-decisions.md).

## End-to-end flow

Content and configuration move in one direction, from the connected **low side** to the
disconnected **high side**, through a controlled transfer.

```text
  LOW SIDE (connected)                 TRANSFER                    HIGH SIDE (air-gapped)
 +-------------------------+    +----------------------+    +---------------------------------------+
 | Mirror workstation      |    | Approved media or    |    | Registry / bastion host (MRZ)         |
 | (RHEL 9, FIPS)          |    | one-way transfer     |    |  - mirror registry (rootless, :8443)  |
 |  - oc-mirror v2         |    |  (data diode / CDS)  |    |  - oc, oc-mirror v2, openshift-install|
 |  - ImageSetConfiguration|--->|  - sha256 manifest   |--->|  - disk-to-mirror upload              |
 |  - mirror-to-disk       |    |  - signature         |    +-------------------+-------------------+
 |  - this Git repo        |    |  - chain of custody  |                        | pulls (TLS)
 +-------------------------+    +----------------------+                        v
          Phase 1                     Phase 1/2             +---------------------------------------+
                                                            | Provisioner host (RHEL 9, FIPS)       |
                                                            |  - bootstrap VM (libvirt)              |
                                                            |  - openshift-install (bare metal IPI) |
                                                            +-------------------+-------------------+
                                                                                | Redfish / IPMI
                                                                                v
                                                            +---------------------------------------+
                                                            | OpenShift 4.22 cluster (bare metal)   |
                                                            |  3 control plane + 3..N workers       |
                                                            |  GitOps <- departmental Git           |
                                                            |  ACM / RHACS / Compliance (local)     |
                                                            +---------------------------------------+
                                                                    Phases 3, 4, 5, 6
```

| Phase | Where | Output handed to the next phase |
|---|---|---|
| [1 — Content mirroring](../01-mirroring/index.md) | Low side | Signed, checksummed mirror archive plus this repository |
| [2 — High-side setup](../02-high-side/index.md) | High side | Populated mirror registry, generated `cluster-resources/`, FIPS `openshift-install` |
| [3 — Cluster install](../03-cluster-install/index.md) | High side | Running HA cluster, break-glass credentials in a vault |
| [4 — ITSG-33 configuration](../04-itsg33-configuration/index.md) | High side | Cluster converged to the PBMM baseline through GitOps |
| [5 — Compliance and evidence](../05-compliance-evidence/index.md) | High side | Scan results, policy reports, evidence bundles, SRTM |
| [6 — SOPs](../06-sops/index.md) | Both | Repeatable deployment, Day 2, upgrade, and troubleshooting procedures |

## High-side topology

```text
 +------------------------------------------------------------------------------------------+
 | Management Restricted Zone (MRZ)                                                         |
 |   Registry/bastion host: mirror-registry, admin tooling   Provisioner host (install)     |
 |   Departmental services: Git, IdP (OIDC + MFA), PKI/HSM, SIEM, NTP, DNS, S3, CSI storage  |
 |   BMC network (Redfish/IPMI): reachable only from the provisioner host and admins         |
 +--------------------------------------------+---------------------------------------------+
                                              |
 +--------------------------------------------|---------------------------------------------+
 | Operations Zone (OZ) / Restricted Zone (RZ)                                              |
 |   +---------------------------- OpenShift 4.22 cluster ------------------------------+   |
 |   |  Control plane (3 bare-metal nodes)      Worker nodes (3..N bare-metal nodes)     |   |
 |   |  - kube-apiserver, etcd (encrypted)      - Platform services on "infra"-labelled  |   |
 |   |  - OAuth / OIDC                            workers: routers, monitoring, logging, |   |
 |   |                                            ACM, RHACS Central, GitOps              |   |
 |   |                                          - Tenant namespaces (restricted-v2 SCC,  |   |
 |   |                                            default-deny NetworkPolicy)            |   |
 |   |  OVN-Kubernetes (IPsec east-west), FIPS mode, RHCOS with LUKS bound to TPM 2.0    |   |
 |   +----------------------------------------------------------------------------------+   |
 +------------------------------------------+-----------------------------------------------+
                                            |
                                  +---------+---------+
                                  | Public Access Zone|  Departmental load balancer / WAF
                                  | (PAZ)             |  in front of the "paz" IngressController
                                  +-------------------+
```

## Building blocks

| Component | Purpose | Key ITSG-33 controls |
|---|---|---|
| **OpenShift Container Platform 4.22** (Kubernetes 1.35, RHCOS) | Container platform | Many — see the family guides |
| **RHCOS** (Red Hat Enterprise Linux CoreOS) | Immutable, image-based node OS, managed by the Machine Config Operator | CM-2, CM-6, CM-7, SI-7 |
| **oc-mirror v2** | Mirrors the release, operator catalogs, and additional images from the low side to the high side | CM-11, SA-12, SI-7 |
| **mirror registry for Red Hat OpenShift** | Small Quay-based registry on the high side that serves all mirrored Red Hat content | CM-11, SA-12, SC-8 |
| **Bare metal IPI** (Ironic / Metal3, Bare Metal Operator) | Installs and manages node lifecycle through BMCs (Redfish virtual media or PXE) | CM-2, CM-8, MA-2 |
| **OpenShift Update Service** (OSUS) | Offline update graph so the cluster can pick valid upgrade paths | SI-2, CM-3 |
| **Kubernetes NMState Operator** | Declarative host networking (bonds, VLANs) after install | CM-2, CM-6, SC-7 |
| **MetalLB Operator** | `LoadBalancer` services on bare metal (zone ingress, CUDN exposure) | SC-7, AC-4 |
| **Compliance Operator** | OpenSCAP-based scans against NIST 800-53 Moderate/High content, with automated remediation | CA-2, CA-7, CM-6, SI-6 |
| **File Integrity Operator** | AIDE-based file integrity monitoring on nodes | SI-7, AU-6 |
| **Security Profiles Operator** | Distributes and records seccomp and SELinux profiles | AC-6, CM-7, SC-39 |
| **OpenShift Logging** (Cluster Logging Operator 6.x) | Collects audit, infrastructure, and application logs and forwards them to the SIEM | AU-2 to AU-12 |
| **cert-manager Operator for Red Hat OpenShift** | Certificate lifecycle with enterprise or GC PKI | SC-12, SC-17, IA-5 |
| **External Secrets Operator for Red Hat OpenShift** / Secrets Store CSI driver | Pulls secrets from an external vault or KMS | SC-12, SC-28, IA-5 |
| **OpenShift GitOps** (Argo CD) | Declarative configuration management from the departmental Git server | CM-2, CM-3, CM-5 |
| **OADP** (OpenShift API for Data Protection) | Backup and restore of namespaces and persistent volumes to S3-compatible storage | CP-9, CP-10 |
| **Red Hat Advanced Cluster Management** | Governance policies and compliance reporting for the cluster (`local-cluster`) | CA-7, CM-2, CM-3, CM-6, CM-8 |
| **Red Hat Advanced Cluster Security** | Vulnerability management (offline feeds), admission control, runtime threat detection, network graph | RA-5, SI-3, SI-4, CM-7, IR-4 |
| **Vendor CSI driver** (external storage) | Persistent volumes from departmental enterprise storage | SC-28, CP-9 |

The exact operator list, channels, and versions that get mirrored are pinned in
[`versions.env`](../reference/versions.md) and in the Phase 1 `ImageSetConfiguration`.

## Supporting services (assumed to exist on the high side)

| Service | Used for | Notes |
|---|---|---|
| **DNS** | `api`, `api-int`, `*.apps` records, node and BMC names, registry name | Forward and reverse records for every node |
| **NTP** | Time sync for nodes, BMCs, registry, and provisioner | Same source for all; required for valid certificates and correlated audit logs (AU-8) |
| **DHCP** (optional) | Node addressing on the machine network | Static addressing through NMState `networkConfig` is also supported |
| **PKI** | Certificates for the mirror registry, ingress, API, and IdP; trust bundle for the cluster | Root and intermediate CAs are added to `additionalTrustBundle` |
| **Git** | Source of truth for GitOps (this repository, transferred from the low side) | Departmental GitLab, Bitbucket, or similar, with TLS and audited access |
| **IdP** | OIDC with MFA for platform users | See [Identity architecture](#identity-architecture) |
| **SIEM** | Log and alert destination | Syslog/TLS, Splunk HEC, or Kafka |
| **Enterprise storage** | `ReadWriteOnce` and `ReadWriteMany` volumes through a vendor CSI driver | NFS is acceptable for general RWX workloads, but not for Prometheus, Loki, or other databases |
| **RHEL content** | Packages and errata for the registry, provisioner, and other high-side RHEL hosts | For example, a departmental Satellite, or RHEL content imported through the transfer process. This repository's transfers carry OpenShift content only. |
| **S3-compatible object storage** | LokiStack, OADP backups, and (optionally) the image registry | Needs object lock / retention where logs are kept for AU-11 |

## Cluster topology

### Control plane

- **Three bare-metal control plane nodes**, spread across racks, power feeds, and top-of-rack
  switches where possible. This meets CP-7 and SC-5 expectations for medium availability.
- Control plane nodes do not run tenant workloads. The default `NoSchedule` taint stays in place.
- etcd is **encrypted at rest** with `aesgcm`. See SC-28.

### Worker nodes and platform services

- **Three or more bare-metal workers.** The first three workers carry the
  `node-role.kubernetes.io/infra` label and host routers, monitoring, logging, GitOps, ACM, and
  RHACS Central. This keeps platform services together and apart from most tenant workloads
  (SC-2, SC-3) without buying dedicated infra hardware.
- When the cluster grows, move platform services to **dedicated infra nodes** (a separate
  `MachineConfigPool`, tainted for platform workloads only).
- Tenant workloads run on the remaining worker capacity. **Sensitivity-based node pools** (for
  example, separate pools for Protected B and Unclassified workloads) may be needed if your TRA
  calls for stronger isolation than namespaces provide.
- The `restricted-v2` SCC is the default. Workloads that need more privilege go through a
  documented exception process (AC-6, CM-7).

### Management plane on the same cluster

ACM and RHACS run **on the cluster they manage** (ACM manages itself as `local-cluster`; RHACS
Central and the Secured Cluster services share the cluster). This removes a separate hub cluster
and its hardware, at the cost of co-locating management and workloads:

- Record the decision (AD-04) and its residual risk in the TRA.
- Keep management namespaces on infra-labelled nodes, restrict them with RBAC to the platform
  team, and forward RHACS alerts and ACM policy status to the SIEM so evidence survives a
  cluster compromise or loss.
- If a second cluster is added later, move ACM and RHACS Central to a dedicated management (hub)
  cluster in the MRZ. See [Scaling out](#scaling-out).

### Bare-metal network design

| Network | Purpose | Required |
|---|---|---|
| **Machine (baremetal) network** | Node IPs, API and ingress VIPs, pod egress | Yes |
| **BMC (out-of-band) network** | Redfish or IPMI access to each node's BMC | Yes. Reachable from the provisioner host (and the cluster's Ironic pod for Day 2). Not reachable from tenant workloads. |
| **Provisioning network** | PXE boot and Ironic traffic | Only for the PXE method. Not needed with Redfish virtual media. |
| **Storage network** (optional) | Traffic to enterprise storage | Separate VLAN or bond where the storage vendor recommends it |

Two IPI provisioning methods are documented in [Phase 3](../03-cluster-install/index.md):

| Method | When to use it |
|---|---|
| **Redfish virtual media** (primary) | BMCs support Redfish virtual media. No provisioning network or PXE/DHCP on a dedicated VLAN (`provisioningNetwork: Disabled`). Simplest network design. |
| **PXE with a provisioning network** (alternative) | Older BMCs (IPMI only) or virtual media is blocked by policy. Needs a dedicated, non-routed provisioning network on a separate NIC. |

The API (`api.<cluster>`) and ingress (`*.apps.<cluster>`) VIPs are served by the
platform-managed keepalived and HAProxy by default. A departmental external load balancer can be
used instead (AD-16).

### Scaling out

This repository targets one cluster. If more clusters are added (for example, separate
Protected B and Unclassified clusters, or production and non-production):

- Prefer **separate clusters** over namespace isolation for different security domains.
- Move ACM and RHACS Central to a **management (hub) cluster** in the MRZ, and import the
  workload clusters as managed clusters.
- Reuse the same mirror registry or deploy one per security domain, as the TRA requires.

## Network security zones (ITSP.80.022)

| GC zone | OpenShift mapping |
|---|---|
| **Public Zone** | Outside the cluster |
| **Public Access Zone (PAZ)** | An external load balancer or WAF in front of a **dedicated IngressController** (for example, `paz`) on infra-labelled nodes. Only routes labelled for the PAZ are admitted (route sharding). |
| **Operations Zone (OZ)** | Default `IngressController` for internal users. Most worker nodes and tenant namespaces. |
| **Restricted Zone (RZ)** | A dedicated **ClusterUserDefinedNetwork** (CUDN) for RZ namespaces, a dedicated worker pool, or a separate cluster for sensitive back-end services and data stores. See the [network isolation model](#network-isolation-model). |
| **Management Restricted Zone (MRZ)** | API server endpoint (not exposed to the PAZ), bastions, the registry host, the provisioner host, the BMC network, Git, the SIEM, the PKI, and the IdP |

Design notes:

- **Separate the API endpoint from application ingress.** Publish the Kubernetes API
  (`api.<cluster>`) only to the MRZ. Publish application routes (`*.apps.<cluster>`) through
  zone-specific IngressControllers.
- **Ingress sharding.** Use `routeSelector` or `namespaceSelector` on each IngressController so a
  route reaches the PAZ only when it is explicitly labelled for it.
- **Egress control.** Use an `EgressFirewall` per namespace plus cluster-wide `AdminNetworkPolicy` /
  `BaselineAdminNetworkPolicy`. Use `EgressIP` so the perimeter firewall can recognize tenant
  traffic. The high side has no internet path, so egress rules only need to allow approved
  high-side services (Git, IdP, SIEM, S3, storage, DNS, NTP).
- **East-west encryption.** Turn on OVN-Kubernetes **IPsec** (`Full` mode) where node-to-node
  traffic crosses untrusted network segments, or where your TRA requires it (SC-8).
- **User-defined networks** (UDN / ClusterUserDefinedNetwork) give zones or tenants isolated
  layer 2 or layer 3 networks when namespace-level `NetworkPolicy` is not strong enough. See the
  next section.

## Network isolation model

OpenShift 4.22 offers three tiers of network isolation for workloads. Choose a tier for each
security zone or tenant, and record the choice as architecture decision **AD-09**.

| Tier | Mechanism | Isolation strength | Typical use |
|---|---|---|---|
| **1. Policy isolation** | All namespaces on the default cluster network. Separation comes from `BaselineAdminNetworkPolicy` default-deny, `AdminNetworkPolicy` guardrails, and namespace `NetworkPolicy`. | Depends on policy being correct. A wrong `NetworkPolicy` in a tenant namespace can open a path. | Tenants in the same zone and at the same sensitivity level |
| **2. Network isolation** | Each zone (or tenant) gets its own **primary `ClusterUserDefinedNetwork`**. Separate primary networks are isolated by OVN-Kubernetes by default. | Separation is part of the network topology. A `NetworkPolicy` that tries to allow traffic between namespaces on different primary networks **has no effect**. | Separating zones (for example, OZ and RZ) or high-risk tenants inside one cluster |
| **3. Cluster isolation** | Separate clusters, optionally on separate infrastructure | Strongest. No shared control plane, nodes, or kernel. | Different security domains (for example, Protected B and Unclassified) or production and non-production |

Tiers can be combined. For example, give each zone its own CUDN (tier 2), and inside each zone use
default-deny `NetworkPolicy` for micro-segmentation (tier 1). Tier 2 does not replace tier 3 where
your TRA requires separate control planes or kernels.

### Zone-per-CUDN design (tier 2)

```text
+------------------------------------ OpenShift cluster ---------------------------------------+
|                                                                                               |
|  CUDN "zone-oz" (primary)              CUDN "zone-rz" (primary)          Default network     |
|  ns: hr-app, payments-web              ns: payments-db, records-api      ns: openshift-*     |
|  itsg33/zone=oz                        itsg33/zone=rz                    (platform services) |
|  NetworkPolicy inside the zone         NetworkPolicy inside the zone                          |
|           |                                     |                                             |
|           +--------- no direct path ------------+                                             |
|           |                                     |                                             |
+-----------|-------------------------------------|---------------------------------------------+
            |  LoadBalancer services, or BGP route advertisement into per-zone VRFs           
            v                                     v                                             
   +--------------------------- Zone Interface Point (departmental firewall) -----------------+
   |  All OZ <-> RZ traffic is inspected and logged here (ITSP.80.022)                        |
   +------------------------------------------------------------------------------------------+
```

Design rules:

- **One primary CUDN per zone.** Each CUDN's `namespaceSelector` matches the zone label (for
  example, `itsg33/zone: rz`). Never select `default` or `openshift-*` namespaces, and never
  use an empty selector, which selects every namespace in the cluster.
- **Decide at namespace creation.** A namespace joins a primary user-defined network only if it
  has the `k8s.ovn.org/primary-user-defined-network` label **when it's created**. The label
  can't be added or changed later, and CUDN objects can't be changed after creation. Moving a
  namespace to a different zone means re-creating it. Create zoned namespaces through GitOps,
  and enforce the labels with an admission policy (see
  [AC-4](../04-itsg33-configuration/controls/ac-access-control.md#network-level-segmentation-with-clusteruserdefinednetwork)).
- **Traffic between zones goes through a Zone Interface Point.** Because separate primary networks
  can't reach each other inside the cluster, OZ-to-RZ traffic must leave the cluster. It is
  exposed through a `LoadBalancer` service (for example, MetalLB) or BGP route advertisement, and
  passes through the departmental firewall. This matches the ITSP.80.022 requirement that traffic
  between zones crosses a ZIP.
- **Micro-segmentation inside each zone.** Namespaces on the same CUDN can reach each other unless
  `NetworkPolicy` stops them. Keep the default-deny project template.

Limitations to plan for (from the 4.22 documentation):

| Limitation | Design consequence |
|---|---|
| **Routes are listed as not supported** on primary user-defined networks (Layer2 and Layer3) in the 4.22 "UserDefinedNetwork and NetworkAttachmentDefinition support matrix" | Keep **PAZ-facing web front ends on the default network** behind the sharded `paz` IngressController. Put back ends in the CUDN zones. Expose CUDN workloads with `LoadBalancer` services or BGP-advertised pod networks behind the PAZ load balancer or WAF. Check the matrix again for your exact z-stream. |
| Pods can still reach the Kubernetes API and cluster DNS on the default network | Not a complete air gap. Record this in the SSP. API access is still controlled by RBAC and audited. |
| Kubelet health probes use the default network | A pod can look healthy while its UDN interface is broken. Add application-level monitoring. |
| Pods on the default network can't start connections to UDN pods unless the `k8s.ovn.org/open-default-ports` annotation opens specific ports | Platform monitoring can't scrape metrics endpoints on UDN pods unless those ports are opened. Open only the metrics port. |
| Most default-network services can't be reached, including the internal image registry. Source-to-image builds and `oc new-app` from Git don't work. | Pull images from the departmental registry (Quay). Build images in CI outside the zone (this already matches SA-12). |
| NodePort isolation isn't guaranteed (a pod can reach a NodePort service on another node) | Don't use `NodePort` services in zoned namespaces. Use `LoadBalancer` services instead. Enforce this with an admission policy or RHACS. |
| EgressIP limits on Layer2 networks (no default gateway, Google Cloud, multiple gateways) | Use Layer3 topology where tenants need EgressIP, or test Layer2 EgressIP on your platform |
| When a subnet runs out of addresses, pod creation fails with a generic sandbox error | Size the CUDN subnets for growth. Monitor namespace events. |

> **Policy behaviour still to confirm:** the 4.22 documentation reviewed for this guide doesn't say
> clearly how `AdminNetworkPolicy`, `BaselineAdminNetworkPolicy`, and `EgressFirewall` apply to pods
> on primary user-defined networks. (The route advertisement documentation lists `EgressFirewall`
> and network policies as fully supported with route advertisements.) Test each guardrail on a
> CUDN namespace before relying on it, and keep the test results as CA-2 evidence.

### Mapping zones onto the physical network with BGP (optional)

On **bare-metal** clusters, OVN-Kubernetes can advertise CUDN pod networks to the data centre
network over BGP (`RouteAdvertisements`, using FRR):

- **VRF-lite:** each zone's CUDN is advertised into a matching VRF on the provider edge router
  (`targetVRF: auto`). The departmental firewall then sees real zone addresses and enforces the
  ZIP between VRFs. VRF-lite needs local gateway mode (`routingViaHost: true`) and doesn't support
  EgressIP.
- **BGP EVPN** (new in 4.22): carries primary CUDN traffic over VXLAN to the data centre fabric
  (`spec.network.transport: EVPN`). Bare metal only. Needs `routingViaHost: true` and
  `ipForwarding: Global`.
- **NoOverlay** transport (Technology Preview in 4.22) routes pod traffic directly on the underlay.
  Not recommended for production Protected B workloads while it is a Technology Preview.

> Check the support status of route advertisements and EVPN in the 4.22 release notes before you
> design around them. A BGP misconfiguration can disrupt the whole cluster network, so involve
> the network team and test in a lab first. See the
> [SC-7 configuration example](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-7-boundary-protection).


## Connectivity model: air-gapped

The high side has **no network path** to Red Hat or the internet, including through a proxy. All
content arrives through the controlled transfer described in Phase 1:

| Content | How it reaches the high side |
|---|---|
| OpenShift release images and update graph | `oc-mirror` v2 archive, uploaded into the mirror registry; graph data served by OSUS |
| Operator catalogs and bundles | `oc-mirror` v2 archive (filtered catalogs, only the approved operators and channels) |
| Additional images (tools, base images) | `oc-mirror` v2 `additionalImages` |
| Binaries (`oc`, `oc-mirror`, `openshift-install`, `mirror-registry`) | Transferred with the archive; `openshift-install` is extracted from the mirrored release on the high side |
| RHACS vulnerability definitions | RHACS offline bundle, transferred on the same schedule |
| RHCOS errata and security advisories | Arrive with each new release image; advisories are reviewed on the low side (SI-5) |
| This Git repository | Bundled (`git bundle`) and pushed to the departmental Git server |

Consequences for the design:

- **Telemetry, Insights, and remote health reporting are off.** Support data (`must-gather`) is
  collected on the high side, reviewed and sanitized, and carried out through the approved
  process (MA-4, SA-9).
- **Clusters reference only the mirror registry.** `ImageDigestMirrorSet` and
  `ImageTagMirrorSet` (generated by `oc-mirror`) redirect pulls; the default OperatorHub sources
  are disabled and replaced with the mirrored catalogs (CM-7, CM-11). `ImageContentSourcePolicy`
  is deprecated and not used.
- **Image signature verification** stays in place: release signatures are mirrored with the
  release, and the cluster verifies them (SI-7).
- **Content freshness is a process, not a network setting.** The import cadence (for example,
  monthly plus emergency imports for critical CVEs) is defined in the Day 2 SOPs and drives
  SI-2 and RA-5 timelines.

## Identity architecture

- **OIDC** identity provider on the high side (for example, Red Hat build of Keycloak federated
  to departmental AD) that enforces **MFA** (IA-2(1), IA-2(2)).
- OpenShift either uses the built-in OAuth server with an `OpenID` identity provider, or uses
  **direct authentication with an external OIDC provider**, where the API server validates IdP
  tokens itself. Pick one and record the decision (AD-03). See the
  [IA guide](../04-itsg33-configuration/controls/ia-identification-and-authentication.md).
- Group membership comes from IdP claims (or LDAP group sync) and drives RBAC (AC-2, AC-6).
- The `kubeadmin` user is removed after installation. A sealed, monitored break-glass
  credential (the installer `kubeconfig`) is kept in a vault (AC-2, AC-6(9)).
- Access to BMCs, the provisioner host, and the registry host uses named accounts with MFA
  through the departmental bastion; shared BMC credentials are rotated after install.

## Cryptography architecture

- **FIPS mode** is set at installation (`fips: true`). It cannot be turned on afterwards. The
  install must run from a **RHEL 9 host booted in FIPS mode**, using the FIPS-capable
  `openshift-install` binary extracted from the mirrored release. FIPS uses RHEL cryptographic
  modules submitted for FIPS 140 validation. CCCS recognizes CMVP-validated modules
  (ITSP.40.111). Check the current CMVP certificate status for the RHEL 9 modules in your 4.22
  release.
- The **registry host and provisioner host** also run RHEL 9 in FIPS mode.
- **TLS security profiles** are set on the API server, IngressControllers, and kubelet to meet
  ITSP.40.062 (TLS 1.2 minimum with approved cipher suites, or TLS 1.3 only).
- **Certificates** for the mirror registry, ingress, and API come from the departmental PKI. The
  PKI root and intermediates are added to the cluster trust bundle at install time.
- **Disk encryption:** RHCOS root disks use LUKS2 bound to each node's TPM 2.0, configured at
  install time (AD-06). Red Hat supports Tang (NBDE) for disk encryption only on UPI installs, so
  it is not used in this IPI design.
- **Post-quantum readiness:** OpenShift 4.22 adds PQC readiness features (for example, hybrid
  ML-KEM key exchange where enabled). Track the GC PQC migration roadmap and test these features
  before using them for Protected B.
- **Key management:** etcd encryption keys are managed by the platform. Application secrets
  come from an external vault (HSM-backed where required) through External Secrets or the
  Secrets Store CSI driver.

## Logging and monitoring architecture

```text
 Nodes (auditd, journald)  ---\
 API / OAuth audit logs    ----+--> Vector collector --> ClusterLogForwarder --+--> SIEM (syslog/TLS, Splunk, Kafka)
 OVN ACL audit logs        ---/        (per node)                             +--> LokiStack on S3 (short-term search)
 Application logs          --/
 RHACS runtime alerts  ------------------------------------------------------>  SIEM
 Compliance Operator / FIO results ----> ACM governance (local-cluster) ----->  SIEM / GRC tool
 Registry host / provisioner host (auditd, rsyslog) ------------------------->  SIEM
```

If S3-compatible object storage is not available on the high side, skip LokiStack and rely on
the SIEM for search and retention (AD-14).

## Availability architecture

| Layer | Mechanism |
|---|---|
| Control plane | 3-node etcd quorum spread across racks and power feeds; regular etcd snapshots copied off-cluster |
| Ingress | At least 2 router replicas on infra-labelled workers; API and ingress VIPs (keepalived) or an external load balancer |
| Workloads | `PodDisruptionBudget`, topology spread constraints, `HorizontalPodAutoscaler` |
| Data | Enterprise storage through the vendor CSI driver (replication handled by the array); OADP backups to S3 |
| Mirror registry | Not on the cluster's critical path once images are cached, but required for node replacement, scaling, and upgrades. Back up its data directory and keep the last transfer archive. |
| Site | Rebuild from the mirror archive, this Git repository, and OADP backups. A second site is out of scope for this iteration. |

## Architecture decisions

The decisions behind this design (platform, connectivity, registry, provisioning method, storage,
identity, encryption, and more) are recorded in [Architecture decisions](architecture-decisions.md).
