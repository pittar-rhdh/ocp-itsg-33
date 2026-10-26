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
| **Restricted Zone (RZ)** | Worker pools or separate clusters for sensitive back-end services and data stores. Reached only through OZ services via `NetworkPolicy` / `AdminNetworkPolicy`. |
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
- **User-defined networks** (UDN / ClusterUserDefinedNetwork) can give tenants isolated
  layer 2 or layer 3 networks when namespace-level `NetworkPolicy` is not strong enough.

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
