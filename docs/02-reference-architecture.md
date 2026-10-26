# 02 — Reference Architecture

[← Back to main](index.md)

This section describes a target architecture for an OpenShift 4.22 platform that hosts
Protected B workloads at medium integrity and medium availability.

## Architecture overview

```text
                         Internet / GC network (Untrusted / Public)
                                        |
                             +----------+-----------+
                             | Public Access Zone   |   WAF, DDoS protection, reverse proxy,
                             | (PAZ)                |   external load balancer
                             +----------+-----------+
                                        |
 +--------------------------------------|--------------------------------------------------+
 | Operations Zone (OZ) / Restricted Zone (RZ)                                              |
 |                                                                                          |
 |   +------------------------------- OpenShift 4.22 workload cluster -------------------+  |
 |   |                                                                                   |  |
 |   |  Control plane (3 nodes)     Infra nodes (3+)              Worker nodes (N)       |  |
 |   |  - kube-apiserver            - IngressController "paz"     - Tenant namespaces    |  |
 |   |  - etcd (encrypted)          - IngressController "internal"- restricted-v2 SCC    |  |
 |   |  - OAuth / OIDC              - Logging collectors          - Default-deny netpol  |  |
 |   |                              - Monitoring, registry        - Egress via EgressIP  |  |
 |   |                                                                                   |  |
 |   |  OVN-Kubernetes (IPsec east-west), FIPS mode, RHCOS with LUKS disk encryption     |  |
 |   +-----------------------------------------------------------------------------------+  |
 |                                                                                          |
 +------------------------------------------------------------------------------------------+
                                        |
 +--------------------------------------|--------------------------------------------------+
 | Management Restricted Zone (MRZ)                                                         |
 |   - Hub cluster: ACM (governance, GitOps), RHACS Central, Quay (mirror registry)          |
 |   - Identity provider (OIDC with MFA), PKI / HSM / KMS, SIEM, bastion / jump hosts       |
 |   - Backup target (OADP object storage), Git repositories                                |
 +------------------------------------------------------------------------------------------+
```

## Building blocks

| Component | Purpose | Key ITSG-33 controls |
|---|---|---|
| **OpenShift Container Platform 4.22** (Kubernetes 1.35, RHCOS) | Container platform | Many — see the family guides |
| **RHCOS** (Red Hat Enterprise Linux CoreOS) | Immutable, image-based node OS, managed by the Machine Config Operator | CM-2, CM-6, CM-7, SI-7 |
| **Compliance Operator** | OpenSCAP-based scans against NIST 800-53 Moderate/High content, with automated remediation | CA-2, CA-7, CM-6, SI-6 |
| **File Integrity Operator** | AIDE-based file integrity monitoring on nodes | SI-7, AU-6 |
| **Security Profiles Operator** | Distributes and records seccomp and SELinux profiles | AC-6, CM-7, SC-39 |
| **OpenShift Logging** (Cluster Logging Operator 6.x) | Collects audit, infrastructure, and application logs and forwards them to the SIEM | AU-2 to AU-12 |
| **cert-manager Operator for Red Hat OpenShift** | Certificate lifecycle with enterprise or GC PKI | SC-12, SC-17, IA-5 |
| **External Secrets Operator for Red Hat OpenShift** / Secrets Store CSI driver | Pulls secrets from an external vault or KMS | SC-12, SC-28, IA-5 |
| **OpenShift GitOps** (Argo CD) | Declarative configuration management | CM-2, CM-3, CM-5 |
| **OADP** (OpenShift API for Data Protection) | Backup and restore of namespaces and persistent volumes | CP-9, CP-10 |
| **Red Hat Advanced Cluster Management** | Multi-cluster lifecycle, governance policies, compliance reporting | CA-7, CM-2, CM-3, CM-6, CM-8 |
| **Red Hat Advanced Cluster Security** | Vulnerability management, admission control, runtime threat detection, network graph | RA-5, SI-3, SI-4, CM-7, IR-4 |
| **Red Hat Quay** (with Clair) | Private registry, mirroring for disconnected installs, image scanning | CM-11, RA-5, SA-12 |
| **NBDE Tang Server Operator** (optional) | Network-Bound Disk Encryption key servers | SC-28, SC-12 |

## Cluster topology

### Control plane

- **Three control plane nodes**, spread across failure domains (availability zones, racks, or
  vSphere hosts with anti-affinity). This meets CP-7 and SC-5 expectations for medium
  availability.
- Control plane nodes do not run tenant workloads. The default `NoSchedule` taint stays in place.
- etcd is **encrypted at rest** with `aesgcm` (or a KMS provider where supported). See SC-28.

### Infrastructure nodes

- Dedicated **infra** `MachineConfigPool` / `MachineSet` for routers, the registry, monitoring,
  and logging. This keeps platform services apart from tenant workloads (SC-2, SC-3).
- Infra nodes that host the PAZ-facing `IngressController` can be put in a separate network
  segment from the other workers.

### Worker nodes

- Tenant workloads run on worker pools. **Sensitivity-based node pools** (for example, separate
  pools for Protected B and Unclassified workloads) may be needed if your TRA calls for stronger
  isolation than namespaces provide.
- The `restricted-v2` SCC is the default. Workloads that need more privilege go through a
  documented exception process (AC-6, CM-7).

### Multi-cluster

- A **hub cluster** in the MRZ runs ACM and RHACS Central and manages **spoke (workload) clusters**.
- Prefer **separate clusters** over namespace isolation for different security domains (for
  example, Protected B and Unclassified, or production and non-production).

## Network security zones (ITSP.80.022)

| GC zone | OpenShift mapping |
|---|---|
| **Public Zone** | Outside the cluster |
| **Public Access Zone (PAZ)** | An external load balancer or WAF in front of a **dedicated IngressController** (for example, `paz`) on infra nodes. Only routes labelled for the PAZ are admitted (route sharding). |
| **Operations Zone (OZ)** | Default `IngressController` for internal users. Most worker nodes and tenant namespaces. |
| **Restricted Zone (RZ)** | A dedicated **ClusterUserDefinedNetwork** (CUDN) for RZ namespaces, a dedicated worker pool, or a separate cluster for sensitive back-end services and data stores. See the [network isolation model](#network-isolation-model). |
| **Management Restricted Zone (MRZ)** | API server endpoint (not exposed to the PAZ), bastions, the hub cluster, the SIEM, the PKI, and the IdP |

Design notes:

- **Separate the API endpoint from application ingress.** Publish the Kubernetes API
  (`api.<cluster>`) only to the MRZ. Publish application routes (`*.apps.<cluster>`) through
  zone-specific IngressControllers.
- **Ingress sharding.** Use `routeSelector` or `namespaceSelector` on each IngressController so a
  route reaches the PAZ only when it is explicitly labelled for it.
- **Egress control.** Use an `EgressFirewall` per namespace plus cluster-wide `AdminNetworkPolicy` /
  `BaselineAdminNetworkPolicy`. Use `EgressIP` so the perimeter firewall can recognize tenant
  traffic. Route all outbound internet traffic through the departmental proxy (cluster-wide proxy
  configuration).
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
  [AC-4](controls/ac-access-control.md#network-level-segmentation-with-clusteruserdefinednetwork)).
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
> [SC-7 configuration example](controls/sc-system-and-communications-protection.md#sc-7-boundary-protection).

## Connectivity model

| Model | Description | Considerations |
|---|---|---|
| **Connected via proxy** | Cluster reaches Red Hat services (update service, registries, Telemetry) through the departmental proxy | Simplest. Review Telemetry and Insights data flows for data residency (SA-9). |
| **Disconnected** | Content is mirrored with `oc-mirror` v2 into Quay in the MRZ. Clusters use `ImageDigestMirrorSet` / `ImageTagMirrorSet` (ICSP is deprecated). | Strongest control over the supply chain (SA-12, CM-11). Needs a process to import content. |

## Identity architecture

- **OIDC** identity provider (for example, Red Hat build of Keycloak federated to departmental
  Entra ID or AD) that enforces **MFA** (IA-2(1), IA-2(2)).
- OpenShift either uses the built-in OAuth server with an `OpenID` identity provider, or uses
  **direct authentication with an external OIDC provider**, where the API server validates IdP
  tokens itself. Pick one and record the decision. See the [IA guide](controls/ia-identification-and-authentication.md).
- Group membership comes from IdP claims (or LDAP group sync) and drives RBAC (AC-2, AC-6).
- The `kubeadmin` user is removed after installation. A sealed, monitored break-glass
  credential (the installer `kubeconfig`) is kept in a vault (AC-2, AC-6(9)).

## Cryptography architecture

- **FIPS mode** is set at installation (`fips: true`). It cannot be turned on afterwards. FIPS
  uses RHEL cryptographic modules submitted for FIPS 140 validation. CCCS recognizes CMVP-validated
  modules (ITSP.40.111). Check the current CMVP certificate status for the RHEL 9 modules in your
  4.22 release.
- **TLS security profiles** are set on the API server, IngressControllers, and kubelet to meet
  ITSP.40.062 (TLS 1.2 minimum with approved cipher suites, or TLS 1.3 only).
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
 OVN ACL audit logs        ---/        (per node)                             +--> LokiStack (short-term search)
 Application logs          --/                                                +--> Object storage with retention lock
 RHACS runtime alerts  ------------------------------------------------------>  SIEM
 Compliance Operator / FIO results ----> ACM governance dashboard ----------->  SIEM / GRC tool
```

## Availability architecture

| Layer | Mechanism |
|---|---|
| Control plane | 3-node etcd quorum spread across failure domains; regular etcd snapshots |
| Ingress | At least 2 router replicas on infra nodes, behind a redundant load balancer |
| Workloads | `PodDisruptionBudget`, topology spread constraints, `HorizontalPodAutoscaler` |
| Data | Replicated storage (for example, OpenShift Data Foundation); OADP backups to off-cluster object storage |
| Site | A second cluster in an alternate site, managed by ACM; GitOps for rebuilds; optional ODF Regional-DR |

## Architecture decisions to record

| ID | Decision | Options |
|---|---|---|
| AD-01 | Deployment platform | Bare metal / vSphere / cloud (Canadian region) / managed (ROSA, ARO) |
| AD-02 | Connectivity | Connected via proxy / disconnected |
| AD-03 | Authentication model | Built-in OAuth + OIDC IdP / direct external OIDC |
| AD-04 | Cluster tenancy | Shared multi-tenant / dedicated per security domain |
| AD-05 | East-west encryption | IPsec Full / IPsec External / none (with TRA justification) |
| AD-06 | Disk encryption key source | TPM2 / Tang (NBDE) / both / cloud-provider encryption |
| AD-07 | Log destination and retention | SIEM product, retention period, immutability |
| AD-08 | Telemetry and remote health reporting | Enabled / disabled (data residency review) |
| AD-09 | Network isolation model (per zone or tenant) | Tier 1 policy isolation / tier 2 CUDN per zone / tier 3 separate cluster; with or without BGP route advertisement (VRF-lite / EVPN) |
