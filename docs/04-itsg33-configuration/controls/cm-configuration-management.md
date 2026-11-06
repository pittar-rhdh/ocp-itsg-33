# CM — Configuration Management

[← Back to control families](index.md) · [← Back to main](../../index.md)

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

**Configuration — project request template with secure defaults:** in Git. File:
`04-gitops/components/project-template/project-template.yaml`.

Every new project gets restricted Pod Security labels, the tenant and `data-classification` labels,
default-deny network policies (with ingress, monitoring and DNS allowed), a quota and default
limits. The `Project` resource `cluster` points at the template.

See [how the configuration is applied](../platform-configuration.md).

> If namespaces are created by GitOps rather than through `oc new-project`, the project template is
> not used. Instead, put the same defaults in a Kustomize component, or enforce them with ACM
> policies (for example, a `ConfigurationPolicy` with `namespaceSelector` that requires a
> default-deny `NetworkPolicy` in every tenant namespace).
>
> **Zoned namespaces (CUDN):** the network a namespace uses is fixed when it's created. The
> `k8s.ovn.org/primary-user-defined-network` label can't be added later. The project template
> above creates namespaces on the default network, so create namespaces for CUDN zones through
> GitOps with the zone and primary network labels already set (see
> [AC-4](ac-access-control.md#network-level-segmentation-with-clusteruserdefinednetwork)). Record the
> zone of each namespace in the baseline. Because `ClusterUserDefinedNetwork` objects can't be
> changed after creation, changing a zone's subnet means a planned re-creation under change
> control (CM-3).

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

**Evidence:** see [04 — Compliance automation](../../05-compliance-evidence/compliance-automation-and-evidence.md).

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

**Configuration — disable default catalog sources:** in Git. File:
`04-gitops/components/operator-hub/operatorhub.yaml`.

`disableAllDefaultSources: true`. Phase 3 sets it on Day 1 and Git owns it from Phase 4.

See [how the configuration is applied](../platform-configuration.md).

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

**Configuration — restrict image registries:** in Git. File:
`04-gitops/components/image-policy/image.yaml`.

Red Hat: when `allowedRegistries` is set, every other registry is blocked, including
`registry.redhat.io`, `quay.io` and the internal registry, which the release payload and operators
reference. Keep them in the list even on a disconnected cluster (the image digest mirror sets send
those pulls to the mirror), and add the mirror registry and the departmental application registry.

See [how the configuration is applied](../platform-configuration.md).

> Otherwise upgrades and operator installs fail. The Machine Config Operator rolls this change
> out to every node (CRI-O restart, no reboot).

**Evidence:** `oc get image.config.openshift.io cluster -o yaml`; Compliance Operator rules
`ocp4-allowed-registries` and `ocp4-allowed-registries-for-import`; RHACS policy "Image from
unapproved registry".
