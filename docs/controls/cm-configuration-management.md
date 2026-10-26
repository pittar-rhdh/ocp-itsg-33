# CM — Configuration Management

[← Back to control families](index.md) · [← Back to main](../index.md)

OpenShift is managed through declarative APIs and operators. This fits configuration management
controls well. The reference architecture keeps **all cluster configuration in Git** and applies
it with OpenShift GitOps (Argo CD) and ACM policies.

---

### CM-2 Baseline Configuration

| Attribute | Value |
|---|---|
| **Responsibility** | Platform |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | Declarative cluster configuration (`config.openshift.io`), Machine Config Operator, RHCOS image-based OS, GitOps, project request templates |
| **Automated check** | ACM policy, Argo CD drift detection |

**Implementation guidance:**

- The **baseline** consists of:
  1. the OpenShift release (version and release image digest),
  2. the `install-config.yaml` used at installation,
  3. the Git repository of day-2 configuration, and
  4. the tailored compliance profile.
- RHCOS is delivered as a versioned OS image tied to the OpenShift release. Node changes are made
  only through `MachineConfig`, which the MCO renders and applies the same way across each pool.
- **CM-2(1) Reviews and updates:** review the baseline at every minor version upgrade, and at
  least once a year.
- **CM-2(2) Automation support:** Argo CD keeps the cluster in sync with Git and reports drift.
- **CM-2(3) Retention of previous configurations:** Git history; `ClusterVersion` history.

**Suggested repository layout:**

```text
cluster-config/
  base/
    apiserver/          # audit profile, TLS profile, etcd encryption
    oauth/              # IdP, token settings, login template
    console/            # banners
    image/              # registry sources, signature policies
    network/            # ANP/BANP, IPsec
    logging/            # ClusterLogForwarder
    compliance/         # ScanSetting, TailoredProfile, ScanSettingBinding
    rbac/               # cluster role bindings to IdP groups
    machineconfig/      # chrony, auditd, SSH, banners
    project-template/   # default NetworkPolicy, quota, limits
  overlays/
    prod-pbmm/
    nonprod/
```

**Configuration example — project request template with secure defaults:**

```yaml
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: itsg33-project-request
  namespace: openshift-config
objects:
  - apiVersion: project.openshift.io/v1
    kind: Project
    metadata:
      name: ${PROJECT_NAME}
      annotations:
        openshift.io/description: ${PROJECT_DESCRIPTION}
        openshift.io/display-name: ${PROJECT_DISPLAYNAME}
        openshift.io/requester: ${PROJECT_REQUESTING_USER}
      labels:
        itsg33/tenant: "true"
        pod-security.kubernetes.io/enforce: restricted
        pod-security.kubernetes.io/audit: restricted
        pod-security.kubernetes.io/warn: restricted
  - apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: admin
      namespace: ${PROJECT_NAME}
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: admin
    subjects:
      - apiGroup: rbac.authorization.k8s.io
        kind: User
        name: ${PROJECT_ADMIN_USER}
  - apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-all
      namespace: ${PROJECT_NAME}
    spec:
      podSelector: {}
      policyTypes: ["Ingress", "Egress"]
  - apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-from-openshift-ingress
      namespace: ${PROJECT_NAME}
    spec:
      podSelector: {}
      ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                  policy-group.network.openshift.io/ingress: ""
      policyTypes: ["Ingress"]
  - apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-from-openshift-monitoring
      namespace: ${PROJECT_NAME}
    spec:
      podSelector: {}
      ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                  network.openshift.io/policy-group: monitoring
      policyTypes: ["Ingress"]
  - apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-dns-egress
      namespace: ${PROJECT_NAME}
    spec:
      podSelector: {}
      egress:
        - to:
            - namespaceSelector:
                matchLabels:
                  kubernetes.io/metadata.name: openshift-dns
          ports:
            - protocol: UDP
              port: 5353
            - protocol: TCP
              port: 5353
      policyTypes: ["Egress"]
  - apiVersion: v1
    kind: ResourceQuota
    metadata:
      name: default-quota
      namespace: ${PROJECT_NAME}
    spec:
      hard:
        requests.cpu: "8"
        requests.memory: 16Gi
        limits.memory: 32Gi
        pods: "50"
  - apiVersion: v1
    kind: LimitRange
    metadata:
      name: default-limits
      namespace: ${PROJECT_NAME}
    spec:
      limits:
        - type: Container
          default:
            memory: 512Mi
          defaultRequest:
            cpu: 100m
            memory: 256Mi
parameters:
  - name: PROJECT_NAME
  - name: PROJECT_DISPLAYNAME
  - name: PROJECT_DESCRIPTION
  - name: PROJECT_ADMIN_USER
  - name: PROJECT_REQUESTING_USER
---
apiVersion: config.openshift.io/v1
kind: Project
metadata:
  name: cluster
spec:
  projectRequestTemplate:
    name: itsg33-project-request
```

> If namespaces are created by GitOps rather than through `oc new-project`, the project template is
> not used. Instead, put the same defaults in a Kustomize component, or enforce them with ACM
> policies (for example, a `ConfigurationPolicy` with `namespaceSelector` that requires a
> default-deny `NetworkPolicy` in every tenant namespace).

**Evidence:**

```bash
oc get clusterversion version -o jsonpath='{.status.history}' | jq
oc get project.config.openshift.io cluster -o yaml
oc get machineconfigpools
oc get applications.argoproj.io -n openshift-gitops   # sync and health status
```

Also collect the Git repository tag or commit that matches the authorized baseline.

---

### CM-3 Configuration Change Control

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org (change advisory board) |
| **OpenShift capabilities** | GitOps with pull-request approvals, Argo CD sync windows, `MachineConfigPool` pause, update channels |

**Implementation guidance:**

- All changes go through a **pull request** with required reviewers, CI validation (`kubeconform`,
  `oc apply --dry-run=server`, policy checks), and a link to the change ticket.
- Use **Argo CD sync windows** to restrict automated syncs to approved change windows in production.
- Plan **cluster upgrades** as changes. Pin the channel (for example, `eus-4.22` or `stable-4.22`),
  and **pause `MachineConfigPools`** to control when nodes reboot.
- **CM-3(2) Test, validate, and document changes:** promote through non-production clusters first.

```bash
# Control when worker nodes pick up new MachineConfigs
oc patch mcp worker --type merge -p '{"spec":{"paused":true}}'
```

**Evidence:** PR history with approvals; Argo CD sync history; change tickets; `ClusterVersion`
history.

---

### CM-4 Security Impact Analysis

**Implementation guidance:**

- Before each minor upgrade, review the OpenShift release notes. Pay attention to the "Deprecated
  and removed features" and "Technology Preview" sections.
- Run Compliance Operator scans in a non-production cluster on the target version, and compare the
  results with production.
- Changes to security-relevant resources need sign-off from a security reviewer through
  `CODEOWNERS`. These resources include `APIServer`, `OAuth`, SCCs, ANP/BANP, `ClusterLogForwarder`,
  `Image` config, and TLS profiles.

---

### CM-5 Access Restrictions for Change

**Implementation guidance:**

- Only the GitOps controller and the break-glass platform admin group hold write access to
  cluster-scoped configuration.
- Humans get read-only access in production by default.
- Protect the Git repository with branch protection and signed commits.
- **CM-5(1) Automated access enforcement / auditing:** RBAC plus API audit logs.

**Evidence:** Argo CD service account RBAC; Git branch protection settings; an audit log query that
shows production changes made only by the GitOps service account.

---

### CM-6 Configuration Settings

| Attribute | Value |
|---|---|
| **Responsibility** | Platform |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | Compliance Operator (scan and remediate), MCO, ACM policies |
| **Automated check** | **Yes — this is the main Compliance Operator use case** |

**Implementation guidance:**

- The tailored `ocp4-moderate` / `rhcos4-moderate` profile **is** the documented configuration
  setting baseline (CM-6 a.).
- Review `ComplianceRemediation` objects and apply them through Git (export the remediation
  objects into the repository). Don't use `autoApplyRemediations: true` in production unless
  change control allows it.
- **CM-6(1) Automated central management:** ACM policies across the fleet.
- Record deviations with a rationale (`TailoredProfile.disableRules[].rationale`).

**Evidence:** see [04 — Compliance automation](../04-compliance-automation-and-evidence.md).

---

### CM-7 Least Functionality

| Attribute | Value |
|---|---|
| **Responsibility** | Platform |
| **OpenShift capabilities** | Cluster capabilities (optional components), OperatorHub source control, SCC/PSA, RHACS policies, minimal RHCOS |

**Implementation guidance:**

- **Disable optional cluster capabilities** you don't need at installation, using
  `capabilities.baselineCapabilitySet` and `additionalEnabledCapabilities` in `install-config.yaml`.
  Capabilities that are turned on cannot be turned off later, so decide at installation.
- **Restrict the operator catalog:** turn off default catalog sources and provide a curated
  catalog built from mirrored, approved operators.
- Block privileged features for tenants: no `hostNetwork`, `hostPID`, `hostPath`, or privileged
  containers (SCC/PSA). RHACS policies can enforce this at deploy time.
- RHCOS ships a minimal package set. You can't install extra packages with `dnf`. Extensions go
  through `MachineConfig` and are reviewed.

**Configuration example — install-time capabilities (excerpt):**

```yaml
# install-config.yaml (excerpt)
fips: true
capabilities:
  baselineCapabilitySet: None
  additionalEnabledCapabilities:
    - marketplace
    - OperatorLifecycleManager
    - Console
    - Ingress
    - ImageRegistry
    - Build
    - DeploymentConfig        # Omit if no tenant needs DeploymentConfigs (deprecated)
    - CSISnapshot
    - NodeTuning
    - CloudCredential         # Needed on cloud platforms
    - Storage
    - MachineAPI              # Needed for MachineSets / installer-provisioned infrastructure
    # Insights deliberately omitted pending data residency review (see SA-9)
    # openshift-samples omitted (Cluster Samples Operator is deprecated in 4.22)
```

> The set of capabilities, and which ones are required, changes by release and platform. Check the
> 4.22 "Cluster capabilities" documentation before installing.

**Configuration example — disable default catalog sources:**

```yaml
apiVersion: config.openshift.io/v1
kind: OperatorHub
metadata:
  name: cluster
spec:
  disableAllDefaultSources: true
```

**Evidence:**

```bash
oc get clusterversion version -o jsonpath='{.status.capabilities}' | jq
oc get operatorhub cluster -o yaml
oc get catalogsources -n openshift-marketplace
```

---

### CM-8 Information System Component Inventory

**Implementation guidance:** The platform keeps a live inventory:

- **Nodes:** `oc get nodes -o wide` and `Machine` objects
- **Platform components:** `ClusterVersion` and `ClusterOperators`
- **Installed operators:** `ClusterServiceVersions`
- **Workloads and images:** RHACS, plus ACM Search across the fleet
- **Software bill of materials:** SBOMs for Red Hat content, and SBOMs produced by your pipelines
  (see SA-12)

**CM-8(3) Automated unauthorized component detection:** RHACS flags deployments that don't
match policy (for example, images from unapproved registries). Red Hat Insights (if enabled) reports
cluster components.

```bash
oc get clusteroperators
oc get csv -A
oc get nodes -o custom-columns=NAME:.metadata.name,ROLE:.metadata.labels,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion
```

---

### CM-11 User-Installed Software

**Implementation guidance:**

- Tenants may deploy only images from **approved registries**. Configure this through
  `image.config.openshift.io` `registrySources.allowedRegistries` and, more strongly, through
  signature verification (see SI-7 / SA-12).
- Operator installation is limited to platform administrators and the curated catalog.

```yaml
apiVersion: config.openshift.io/v1
kind: Image
metadata:
  name: cluster
spec:
  registrySources:
    allowedRegistries:
      - quay-mirror.example.gc.ca          # Mirror registry (disconnected)
      - registry.example.gc.ca             # Departmental application registry
      - image-registry.openshift-image-registry.svc:5000
      # Connected clusters also need: registry.redhat.io, registry.access.redhat.com, quay.io
```

> When you set `allowedRegistries`, include every registry the platform itself pulls from (the
> release and operator images, or their mirrors). Otherwise upgrades and operator installs will
> fail. The Machine Config Operator rolls this change out to every node.

**Evidence:** `oc get image.config.openshift.io cluster -o yaml`; Compliance Operator rules
`ocp4-allowed-registries` and `ocp4-allowed-registries-for-import`; RHACS policy "Image from
unapproved registry".
