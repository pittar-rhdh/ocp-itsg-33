# SC — System and Communications Protection

[← Back to control families](index.md) · [← Back to main](../index.md)

---

### SC-2 Application Partitioning / SC-3 Security Function Isolation

| Attribute | Value |
|---|---|
| **Responsibility** | Platform |
| **OpenShift capabilities** | Dedicated control plane and infra nodes, platform namespaces (`openshift-*`), node selectors and taints, separate clusters |

**Implementation guidance:**

- The control plane (API server, etcd, controllers) runs only on control plane nodes. Tenants can't
  schedule pods there.
- Platform services (routers, registry, monitoring, logging) run on **infra nodes**.
- User interfaces for management (console, API) are separate from tenant application ingress
  (separate hostnames, IngressControllers, and zones).
- Security functions (Compliance Operator, File Integrity Operator, RHACS, logging collectors) run
  in dedicated namespaces that tenants can't access.
- Platform namespaces (`openshift-*`) always stay on the default cluster network. Tenant zones can
  be put on their own primary `ClusterUserDefinedNetwork`, which keeps tenant traffic apart from
  platform traffic at the network level (see
  [network isolation model](../02-reference-architecture.md#network-isolation-model)).

**Configuration example — move ingress routers to infra nodes:**

```yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  replicas: 3
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra: ""
    tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
```

---

### SC-4 Information in Shared Resources

**Implementation guidance:**

- Containers are isolated with namespaces, cgroups, SELinux MCS labels (each namespace gets a
  unique MCS category pair), and seccomp.
- Storage provisioners give each `PersistentVolumeClaim` its own volume. Set the reclaim policy
  to `Delete` and make sure the storage backend wipes freed volumes, or use encrypted volumes with
  per-volume keys.
- **Network:** pods on different primary `ClusterUserDefinedNetwork`s don't share a layer 2 or layer 3
  segment, and can use overlapping address ranges. This stops traffic between zones that share
  nodes from leaking.
- Where your TRA says namespace isolation isn't enough, use the tiers in the
  [network isolation model](../02-reference-architecture.md#network-isolation-model):
  **CUDN per zone** for network separation, plus **dedicated node pools** (separate kernels and
  nodes) or **separate clusters** for each sensitivity level.

---

### SC-5 Denial of Service Protection

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Infrastructure (upstream DDoS) |
| **OpenShift capabilities** | `ResourceQuota`, `LimitRange`, API Priority and Fairness, router connection limits and rate limiting, PodDisruptionBudgets |

**Implementation guidance:**

- Every tenant namespace gets a `ResourceQuota` and a `LimitRange` (project template, see CM-2).
- API Priority and Fairness (on by default) protects the API server from noisy clients.
- Use route annotations to rate-limit connections on PAZ-facing routes. Rely on the upstream
  WAF or DDoS service for volumetric attacks.
- Use `maxConnections` and timeouts in the `IngressController` `tuningOptions`.

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: public-portal
  namespace: portal-prod
  labels:
    itsg33/zone: paz
  annotations:
    haproxy.router.openshift.io/rate-limit-connections: "true"
    haproxy.router.openshift.io/rate-limit-connections.concurrent-tcp: "100"
    haproxy.router.openshift.io/rate-limit-connections.rate-http: "200"
    haproxy.router.openshift.io/timeout: 30s
spec:
  host: portal.example.gc.ca
  to:
    kind: Service
    name: portal
  tls:
    termination: reencrypt
    insecureEdgeTerminationPolicy: Redirect
```

---

### SC-7 Boundary Protection

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Infrastructure (perimeter firewalls), Org (zone design) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | Zone-specific IngressControllers (route sharding), `ClusterUserDefinedNetwork` per zone, BGP `RouteAdvertisements` (VRF-lite / EVPN), `EgressFirewall`, `EgressIP`, ANP/BANP, cluster-wide proxy, private API endpoint |
| **Automated check** | Compliance Operator (`ocp4-configure-network-policies*`), ACM policy |

**Implementation guidance:**

- **SC-7(3) Access points:** the only ways in are the API load balancer (MRZ) and the
  IngressControllers (one per zone). The only ways out are the departmental proxy and the
  `EgressIP` addresses that the perimeter firewall recognizes.
- **SC-7(4) External telecommunications services / SC-7(5) Deny by default, allow by exception:**
  BANP default-deny, namespace default-deny `NetworkPolicy`, `EgressFirewall` deny-all with
  explicit allows.
- **SC-7(7) Prevent split tunnelling:** for remote admin access, this is handled by the VPN/bastion
  (Org).
- **SC-7(8) Route traffic to authenticated proxy servers:** set up the cluster-wide proxy for
  platform egress. Tenants that need internet access use the proxy too.
- **Internal zone boundaries:** when zones share a cluster, put each zone on its own primary
  `ClusterUserDefinedNetwork` (see [AC-4](ac-access-control.md#network-level-segmentation-with-clusteruserdefinednetwork)).
  There is then no direct path between zones inside the cluster, and traffic between zones must
  cross the departmental Zone Interface Point. On bare metal, BGP route advertisement can put each
  zone's CUDN in its own VRF (example below). The perimeter firewall then sees and filters real
  zone addresses.
- **PAZ ingress and CUDNs:** the 4.22 support matrix lists Routes as not supported on primary
  user-defined networks. Keep PAZ-facing front ends on the default network behind the `paz`
  IngressController. Or expose CUDN workloads through `LoadBalancer` services or BGP-advertised
  pod networks behind the PAZ load balancer or WAF.

**Configuration example — PAZ IngressController with route sharding:**

```yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: paz
  namespace: openshift-ingress-operator
spec:
  domain: paz.example.gc.ca
  replicas: 2
  endpointPublishingStrategy:
    type: LoadBalancerService      # Or HostNetwork / NodePortService behind the PAZ load balancer
    loadBalancer:
      scope: External
  routeSelector:
    matchLabels:
      itsg33/zone: paz             # Only routes explicitly labelled for the PAZ are admitted
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra-paz: ""
  tlsSecurityProfile:
    type: Intermediate
---
# Keep PAZ routes off the default (internal) router
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  routeSelector:
    matchExpressions:
      - key: itsg33/zone
        operator: NotIn
        values: [paz]
```

**Configuration example — cluster-wide proxy:**

```yaml
apiVersion: config.openshift.io/v1
kind: Proxy
metadata:
  name: cluster
spec:
  httpProxy: http://proxy.example.gc.ca:3128
  httpsProxy: http://proxy.example.gc.ca:3128
  noProxy: .cluster.local,.svc,10.0.0.0/8,.example.gc.ca
  trustedCA:
    name: user-ca-bundle            # ConfigMap in openshift-config
```

**Configuration example — EgressIP for tenant identification at the perimeter:**

```yaml
apiVersion: k8s.ovn.org/v1
kind: EgressIP
metadata:
  name: payments-prod
spec:
  egressIPs:
    - 10.10.50.20
    - 10.10.50.21
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: payments-prod
```

> Nodes that may host an egress IP need the `k8s.ovn.org/egress-assignable: ""` label.

**Configuration example — advertise zone CUDNs into per-zone VRFs (VRF-lite, bare metal only):**

> **Illustrative.** Route advertisement is supported only on bare metal and needs BGP to be set up
> on the data centre network first. A misconfiguration can disrupt the cluster network. Check the
> support status and exact fields against the 4.22 "Route advertisements" and "BGP routing"
> documentation, and test in a lab first.

```bash
# 1. Enable the FRR routing provider and route advertisements.
#    VRF-lite also needs local gateway mode (routingViaHost).
oc patch networks.operator.openshift.io cluster --type=merge -p '{
  "spec": {
    "additionalRoutingCapabilities": {"providers": ["FRR"]},
    "defaultNetwork": {"ovnKubernetesConfig": {
      "routeAdvertisements": "Enabled",
      "gatewayConfig": {"routingViaHost": true}
    }}
  }
}'
```

```yaml
# 2. BGP sessions to the provider edge router, one per zone VRF.
#    VRF names must match the CUDN names (15 characters or fewer).
apiVersion: frrk8s.metallb.io/v1beta1
kind: FRRConfiguration
metadata:
  name: itsg33-zone-peers
  namespace: openshift-frr-k8s
  labels:
    itsg33/bgp: zone-peers
spec:
  bgp:
    routers:
      - asn: 64512
        vrf: zone-oz
        neighbors:
          - address: 192.168.110.1        # PE router, OZ VRF (VLAN 110)
            asn: 64600
            toReceive:
              allowed:
                mode: filtered
                prefixes:
                  - prefix: 10.150.0.0/16  # Only what the ZIP allows (here, the RZ range)
      - asn: 64512
        vrf: zone-rz
        neighbors:
          - address: 192.168.120.1        # PE router, RZ VRF (VLAN 120)
            asn: 64600
---
# 3. Advertise the pod networks of every CUDN labelled for advertisement into its matching VRF.
apiVersion: k8s.ovn.org/v1
kind: RouteAdvertisements
metadata:
  name: itsg33-zone-vrfs
spec:
  targetVRF: auto                         # Each CUDN is advertised into the VRF with the same name
  advertisements:
    - PodNetwork
  networkSelectors:
    - networkSelectionType: ClusterUserDefinedNetworks
      clusterUserDefinedNetworkSelector:
        networkSelector:
          matchLabels:
            itsg33/advertise: "true"
  nodeSelector: {}                        # PodNetwork advertisement requires all nodes
  frrConfigurationSelector:
    matchLabels:
      itsg33/bgp: zone-peers
```

Notes for assessors and network teams:

- OZ-to-RZ traffic now crosses the PE router and the departmental firewall between the two VRFs.
  That firewall is the ZIP, and its rule set and logs are the SC-7 evidence for the boundary.
- VRF-lite doesn't support EgressIP. EgressIPs from Layer2 CUDNs aren't advertised. Plan egress
  identification by zone subnet instead.
- **BGP EVPN** (new in 4.22, bare metal only) is an alternative to VRF-lite. It sets
  `spec.network.transport: EVPN` on the CUDN, and needs `routingViaHost: true` and
  `ipForwarding: Global`. See "BGP EVPN for user-defined networks" in the 4.22 documentation.

**Evidence:**

```bash
oc get ingresscontrollers -n openshift-ingress-operator -o yaml
oc get routes -A -l itsg33/zone=paz
oc get proxy cluster -o yaml
oc get egressips
oc get clusteruserdefinednetworks --show-labels
oc get routeadvertisements -o yaml                          # If BGP is used
oc get frrconfigurations -n openshift-frr-k8s -o yaml       # If BGP is used
```

Also collect:

- the perimeter firewall rule set and the network flow matrix,
- the ZIP firewall rules between zone VRFs (if BGP is used), and
- the [AC-4 negative connectivity test](ac-access-control.md#network-level-segmentation-with-clusteruserdefinednetwork)
  results.

---

### SC-8 Transmission Confidentiality and Integrity

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Tenant (application protocols) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | TLS security profiles (API server, ingress, kubelet), OVN-Kubernetes IPsec, re-encrypt/passthrough routes, service-serving certificates, service mesh mTLS |
| **Automated check** | Compliance Operator (TLS and IPsec rules) |

**Implementation guidance:**

- **Control plane traffic** (API server, etcd, kubelet) always uses TLS with mutual authentication.
- **SC-8(1) Cryptographic protection:** set TLS security profiles to meet ITSP.40.062. Use
  `Intermediate` (TLS 1.2+ with ECDHE/AEAD suites) as the minimum, or a `Custom` profile that
  limits cipher suites to the ITSP.40.062 list. Use `Modern` (TLS 1.3 only) where all clients
  support it.
- **East-west encryption:** turn on OVN-Kubernetes **IPsec** to encrypt pod traffic between nodes.
  Do this where the underlying network isn't trusted at the Protected B level, or where your
  profile requires it.
- **Application routes:** use `reencrypt` or `passthrough` termination for Protected B
  traffic, so data is encrypted all the way to the pod. Use **service-serving certificates**
  (`service.beta.openshift.io/serving-cert-secret-name`) for TLS inside the cluster.
- Redirect HTTP to HTTPS (`insecureEdgeTerminationPolicy: Redirect`). Enable HSTS through the
  `haproxy.router.openshift.io/hsts_header` annotation, or enforce it with the
  `requiredHSTSPolicies` setting on the `ingresses.config.openshift.io` resource.

**Configuration example — TLS profiles aligned to ITSP.40.062:**

```yaml
# API server (also inherited by many platform components)
apiVersion: config.openshift.io/v1
kind: APIServer
metadata:
  name: cluster
spec:
  tlsSecurityProfile:
    type: Custom
    custom:
      minTLSVersion: VersionTLS12
      ciphers:
        - TLS_AES_128_GCM_SHA256
        - TLS_AES_256_GCM_SHA384
        - ECDHE-ECDSA-AES128-GCM-SHA256
        - ECDHE-RSA-AES128-GCM-SHA256
        - ECDHE-ECDSA-AES256-GCM-SHA384
        - ECDHE-RSA-AES256-GCM-SHA384
---
# Ingress (set on each IngressController)
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  tlsSecurityProfile:
    type: Custom
    custom:
      minTLSVersion: VersionTLS12
      ciphers:
        - TLS_AES_128_GCM_SHA256
        - TLS_AES_256_GCM_SHA384
        - ECDHE-ECDSA-AES128-GCM-SHA256
        - ECDHE-RSA-AES128-GCM-SHA256
        - ECDHE-ECDSA-AES256-GCM-SHA384
        - ECDHE-RSA-AES256-GCM-SHA384
---
# Kubelet
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: itsg33-kubelet-tls
spec:
  machineConfigPoolSelector:
    matchLabels:
      pools.operator.machineconfiguration.openshift.io/worker: ""
  tlsSecurityProfile:
    type: Intermediate
```

> Check the cipher list against the current ITSP.40.062 and ITSP.40.111 revisions. TLS 1.3 cipher
> suites can't be configured in Go-based components. They're always on when TLS 1.3 is negotiated,
> and all of them are approved AEAD suites. CHACHA20-POLY1305 suites are left out on purpose,
> because they aren't FIPS-approved.

**Configuration example — enable IPsec for east-west traffic:**

```bash
oc patch networks.operator.openshift.io cluster --type=merge -p \
  '{"spec":{"defaultNetwork":{"ovnKubernetesConfig":{"ipsecConfig":{"mode":"Full"}}}}}'
```

**Evidence:**

```bash
oc get apiserver cluster -o jsonpath='{.spec.tlsSecurityProfile}'
oc get ingresscontrollers -n openshift-ingress-operator -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.tlsSecurityProfile}{"\n"}{end}'
oc get kubeletconfigs -o yaml
oc get networks.operator.openshift.io cluster -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.ipsecConfig}'
# Check the negotiated protocol and cipher from the MRZ
openssl s_client -connect api.prod.example.gc.ca:6443 -tls1_1 </dev/null   # Expect: handshake failure
openssl s_client -connect api.prod.example.gc.ca:6443 -tls1_2 </dev/null
```

Also collect `oc get routes -A` filtered on `.spec.tls.termination` to show there are no plaintext
routes for Protected B namespaces.

---

### SC-10 Network Disconnect

**Implementation guidance:** OAuth token inactivity timeouts end idle sessions (AC-12). Router
timeouts (`haproxy.router.openshift.io/timeout`, `tuningOptions.clientTimeout`) close idle
application connections.

---

### SC-12 Cryptographic Key Establishment and Management / SC-17 PKI Certificates

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org (PKI / HSM) |
| **OpenShift capabilities** | Automatic platform CA and certificate rotation, custom API and ingress certificates, cert-manager, etcd encryption key rotation, External Secrets Operator / Secrets Store CSI driver |

**Implementation guidance:**

- **Internal platform PKI:** operators issue and rotate internal certificates automatically. Record
  the rotation periods from the 4.22 "Certificate types and descriptions" documentation.
- **External-facing certificates (SC-17):** replace the self-signed ingress and API certificates
  with certificates from the departmental or GC-approved PKI, issued through cert-manager.
- **etcd encryption keys** rotate automatically (weekly by default) when encryption is on.
- **Application secrets and keys** are stored in an external vault (HSM-backed for high-value keys)
  and synced with the **External Secrets Operator for Red Hat OpenShift** or mounted with the
  **Secrets Store CSI driver**.

**Configuration example — custom API server and default ingress certificates:**

```yaml
apiVersion: config.openshift.io/v1
kind: APIServer
metadata:
  name: cluster
spec:
  servingCerts:
    namedCertificates:
      - names: [api.prod.example.gc.ca]
        servingCertificate:
          name: api-server-cert          # TLS secret in openshift-config (see IA-5 cert-manager example)
---
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  defaultCertificate:
    name: apps-wildcard-cert           # TLS secret in openshift-ingress
```

**Configuration example — External Secrets from a vault:**

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: dept-vault
spec:
  provider:
    vault:
      server: https://vault.example.gc.ca
      path: kv
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes/ocp-prod
          role: external-secrets
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: payments-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: dept-vault
  target:
    name: db-credentials
  data:
    - secretKey: password
      remoteRef:
        key: payments/prod/db
        property: password
```

> Check the External Secrets API version (`v1` or `v1beta1`) supported by the operator version you
> install.

---

### SC-13 Use of Cryptography

| Attribute | Value |
|---|---|
| **Responsibility** | Red Hat (modules), Platform (FIPS mode, profiles), Tenant (application crypto) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | FIPS mode, TLS security profiles, RHEL crypto-policies |
| **Automated check** | Compliance Operator (`ocp4-fips-mode-enabled-on-all-nodes`, `rhcos4-*fips*` rules) |

**Implementation guidance:**

- **Install with `fips: true`.** FIPS mode can't be turned on after installation. In FIPS mode, RHCOS
  and the OpenShift components (Go binaries built with the FIPS-capable toolchain) use the RHEL
  cryptographic modules that were submitted for FIPS 140 validation.
- CCCS recognizes **CMVP-validated** modules for protecting Protected B information. Check the
  **current CMVP status** of the RHEL 9 modules used by the RHCOS in your 4.22 release, and keep
  that check in the SSP.
- Make sure algorithms in use follow **ITSP.40.111** (for example, AES-128/256, SHA-256/384,
  RSA ≥ 2048, ECDSA P-256/P-384).
- **Post-quantum cryptography:** 4.22 adds PQC readiness features (for example, hybrid ML-KEM key
  exchange where enabled). The GC has a published PQC migration roadmap. Track PQC features
  as part of your crypto-agility plan, and check how they interact with FIPS mode before you
  turn them on for Protected B.
- Tenants should use the crypto libraries in UBI base images, which follow FIPS mode on the node,
  and not bundle their own crypto.

**Configuration example (install-config.yaml excerpt):**

```yaml
apiVersion: v1
metadata:
  name: prod
fips: true
```

**Evidence:**

```bash
oc get cm cluster-config-v1 -n kube-system -o jsonpath='{.data.install-config}' | grep fips
oc debug node/<node> -- chroot /host cat /proc/sys/crypto/fips_enabled     # Expect: 1
oc debug node/<node> -- chroot /host update-crypto-policies --show         # Expect: FIPS
```

---

### SC-23 Session Authenticity

**Implementation guidance:**

- OAuth tokens are bearer tokens sent only over TLS.
- Console sessions use secure, HTTP-only cookies.
- Service-to-service authenticity relies on TLS with service-serving certificates, or mTLS through
  service mesh (Tenant choice).

---

### SC-28 Protection of Information at Rest

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Infrastructure (storage), Tenant (application-level encryption) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | etcd encryption (`aescbc` / `aesgcm`, external KMS where supported), RHCOS LUKS disk encryption (TPM2 / Tang), encrypted storage classes (ODF, CSI driver encryption) |
| **Automated check** | Compliance Operator (`ocp4-api-server-encryption-provider-cipher` and related rules) |

**Implementation guidance:**

- **etcd encryption** protects Secrets, ConfigMaps, Routes, OAuth tokens, and other sensitive
  resources stored in etcd. Turn it on right after installation. Where your key management policy
  requires an external KMS / HSM, check whether 4.22 supports an external KMS provider on your
  platform. See "External encryption key management" in the 4.22 docs.
- **Node disk encryption:** turn on LUKS for the RHCOS root disk at installation, bound to **TPM2**
  and/or **Tang** (NBDE) servers in the MRZ.
- **Persistent volumes:** use encrypted storage classes. For example, ODF cluster-wide or per-PV
  encryption with KMS, cloud provider encryption with customer-managed keys in Canadian regions,
  or vSphere VM encryption.
- **Backups** are encrypted at rest in object storage (see CP-9).

**Configuration example — etcd encryption:**

```yaml
apiVersion: config.openshift.io/v1
kind: APIServer
metadata:
  name: cluster
spec:
  encryption:
    type: aesgcm
```

**Configuration example — RHCOS disk encryption with TPM2 and Tang (Butane, applied at installation):**

```yaml
variant: openshift
version: 4.22.0                         # Use the Butane spec version that matches your cluster
metadata:
  name: worker-storage
  labels:
    machineconfiguration.openshift.io/role: worker
boot_device:
  layout: x86_64
  luks:
    tpm2: true
    tang:
      - url: http://tang1.mrz.example.gc.ca:7500
        thumbprint: <tang-thumbprint>
      - url: http://tang2.mrz.example.gc.ca:7500
        thumbprint: <tang-thumbprint>
    threshold: 2                        # Any 2 of the 3 pins (TPM2 + a Tang server, or both Tang servers)
openshift:
  fips: true
```

> Disk encryption must be set at installation. Generate the manifests with
> `openshift-install create manifests` and add the compiled MachineConfigs for both the `master` and
> `worker` roles.

**Evidence:**

```bash
oc get apiserver cluster -o jsonpath='{.spec.encryption.type}'
oc get openshiftapiserver -o=jsonpath='{range .items[0].status.conditions[?(@.type=="Encrypted")]}{.reason}{"\n"}{.message}{"\n"}'
oc get kubeapiserver -o=jsonpath='{range .items[0].status.conditions[?(@.type=="Encrypted")]}{.reason}{"\n"}{.message}{"\n"}'
oc debug node/<node> -- chroot /host lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINT   # Expect: crypt device for root
oc debug node/<node> -- chroot /host clevis luks list -d /dev/<root-partition>
oc get storageclass -o yaml | grep -i -E 'encrypt|kms'
```

---

### SC-39 Process Isolation

**Implementation guidance:** Each container runs in its own Linux namespaces, with:

- SELinux MCS confinement,
- the `RuntimeDefault` seccomp profile, and
- cgroup limits.

The default runtime is **crun** (runC is deprecated in 4.22). Where workloads must run as root
inside the container, Linux **user namespaces** (`hostUsers: false` on the pod) map container root
to an unprivileged host UID. Check which SCCs allow this in 4.22. The **Security Profiles Operator**
can record and distribute custom seccomp and SELinux profiles for workloads that need them.
