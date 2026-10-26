# SI — System and Information Integrity

[← Back to control families](index.md) · [← Back to main](../index.md)

---

### SI-2 Flaw Remediation

| Attribute | Value |
|---|---|
| **Responsibility** | Red Hat (errata), Platform (cluster updates), Tenant (image rebuilds) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | Cluster Version Operator over-the-air updates, OpenShift Update Service (OSUS) for disconnected clusters, EUS channels, MCO rolling node updates, RHACS fixable-CVE reporting |
| **Automated check** | RHACS, ACM policy (cluster version), Insights Advisor |

**Implementation guidance:**

- **Platform:** a single cluster update covers the control plane, operators, and RHCOS together.
  Apply z-stream updates on a regular schedule (for example, monthly), and sooner for critical
  security errata, following the departmental patch management standard. Use **`eus-4.22`** or
  **`stable-4.22`** channels.
- **SI-2(2) Automated flaw remediation status:** RHACS reports fixable CVEs for images, nodes, and
  platform components. ACM shows cluster versions across the fleet.
- **Layered operators** update through OLM. Use the `Manual` install plan approval in production so
  operator updates follow change control (CM-3).
- **Tenants** rebuild images on updated UBI base images. RHACS policies can block deployments with
  fixable critical CVEs.

**Configuration example — controlled operator updates:**

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: compliance-operator
  namespace: openshift-compliance
spec:
  channel: stable
  name: compliance-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual           # Approve updates through change control
```

**Evidence:**

```bash
oc get clusterversion version -o jsonpath='{.status.history[*].version}{"\n"}'
oc adm upgrade                                # Available updates and channel
oc get installplans -A
```

Also collect the RHACS vulnerability report and the patch compliance report.

---

### SI-3 Malicious Code Protection

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Tenant |
| **OpenShift capabilities** | RHACS runtime detection (process baselines, anomalous activity), image scanning, read-only RHCOS, SELinux, admission control; third-party anti-malware where required |

**Implementation guidance:**

- RHCOS has a **read-only `/usr`** and is managed as an image. This makes persistent compromise of
  the OS much harder.
- RHACS **process baselining** and runtime policies spot unexpected processes, such as shells,
  package managers, network tools, or crypto miners, running in containers.
- If your departmental policy requires signature-based anti-malware on servers, deploy a vendor
  solution certified for OpenShift (as a DaemonSet or operator from the Red Hat Ecosystem Catalog).
  Record its impact on node performance.
- Scan uploaded files inside applications where it matters (Tenant).

**Evidence:** RHACS runtime policies (enabled list); process baseline locks for critical
deployments; anti-malware deployment status (if used).

---

### SI-4 Information System Monitoring

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org (SOC) |
| **Inheritable by tenants** | Full |
| **OpenShift capabilities** | RHACS, OpenShift Monitoring (Prometheus/Alertmanager), Network Observability Operator, OVN ACL audit logs, API audit logs, File Integrity Operator |

**Implementation guidance:**

- **SI-4(2) Automated tools for real-time analysis:** RHACS runtime detection plus SIEM correlation
  (see AU-6 use cases).
- **SI-4(4) Inbound and outbound communications traffic:** the **Network Observability Operator**
  (eBPF flow collection) gives flow logs and dashboards. OVN ACL logs show denied flows. Monitor
  `EgressFirewall` denies.
- **SI-4(5) System-generated alerts:** route Alertmanager and RHACS notifiers to the SOC.

```yaml
apiVersion: flows.netobserv.io/v1beta2
kind: FlowCollector
metadata:
  name: cluster
spec:
  namespace: netobserv
  deploymentModel: Direct
  agent:
    type: eBPF
    ebpf:
      sampling: 50                      # Lower values give more detail and use more resources
      features:
        - PacketDrop
        - DNSTracking
  # Use the flow exporters to send flows to the SIEM
```

---

### SI-5 Security Alerts, Advisories, and Directives

**Implementation guidance:**

- Subscribe the platform team to **Red Hat Security Advisories (RHSA)** for OpenShift and layered
  products, and to the **CCCS alerts and advisories** feed.
- RHACS correlates new CVEs with running workloads.
- Red Hat Insights (if enabled) flags clusters that are affected by known issues.

---

### SI-6 Security Function Verification

**Implementation guidance:** The **Compliance Operator** checks every day that security functions
are configured correctly:

- audit profile,
- TLS profiles,
- encryption,
- banners,
- IdP, and
- network policies.

ACM policies check for drift continuously. Failures produce alerts and POA&M entries (see CA-7).

---

### SI-7 Software, Firmware, and Information Integrity

| Attribute | Value |
|---|---|
| **Responsibility** | Red Hat (signed content), Platform |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | File Integrity Operator (AIDE), RHCOS image-based OS (rpm-ostree / bootc), release image signature verification, `ClusterImagePolicy`, UEFI Secure Boot |
| **Automated check** | Compliance Operator (`ocp4-file-integrity-*` rules), File Integrity Operator status |

**Implementation guidance:**

- Deploy the **File Integrity Operator** to watch node files (AIDE database). Alert on changes that
  weren't expected, and send failures to the SIEM.
- RHCOS content is checked against the signed release payload. MCO checks for drift between the
  rendered `MachineConfig` and the actual on-disk state, and marks the node degraded if they
  differ.
- Turn on **UEFI Secure Boot** on bare-metal and vSphere nodes where supported.
- **SI-7(1) Integrity checks:** run them on a schedule (FIO `gracePeriod`).
- **Container image integrity:** use signature verification (see SA-12) and pull images by digest.

**Configuration example — File Integrity Operator:**

```yaml
apiVersion: fileintegrity.openshift.io/v1alpha1
kind: FileIntegrity
metadata:
  name: worker-fileintegrity
  namespace: openshift-file-integrity
spec:
  nodeSelector:
    node-role.kubernetes.io/worker: ""
  tolerations:
    - key: node-role.kubernetes.io/infra
      operator: Exists
      effect: NoSchedule
  config:
    gracePeriod: 900                    # Seconds between scans
    maxBackups: 5
---
apiVersion: fileintegrity.openshift.io/v1alpha1
kind: FileIntegrity
metadata:
  name: master-fileintegrity
  namespace: openshift-file-integrity
spec:
  nodeSelector:
    node-role.kubernetes.io/master: ""
  tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
  config:
    gracePeriod: 900
```

**Evidence:**

```bash
oc get fileintegrities -n openshift-file-integrity
oc get fileintegritynodestatuses -n openshift-file-integrity
# View details of a failure
oc get fileintegritynodestatus <name> -n openshift-file-integrity -o jsonpath='{.results}'
oc get mcp                                        # No degraded pools
```

> Expected changes (for example, after a `MachineConfig` rollout) trigger AIDE alerts. Re-initialize
> the database after approved changes with
> `oc annotate fileintegrities/<name> -n openshift-file-integrity file-integrity.openshift.io/re-init=`.
> Include this step in the change procedure.

---

### SI-10 Information Input Validation

**Implementation guidance:**

- The Kubernetes API checks every object against its OpenAPI schema.
- Admission control adds organizational rules (`ValidatingAdmissionPolicy`, RHACS admission
  controller).
- Validating application input is a Tenant responsibility. The platform can provide a WAF in the PAZ.

---

### SI-11 Error Handling

**Implementation guidance:** Platform components don't show stack traces or sensitive data to
unauthenticated users. Tenant applications must handle errors safely, and HAProxy custom error pages
can be set on IngressControllers (`httpErrorCodePages`). Detailed errors go to logs, not to clients.

---

### SI-16 Memory Protection

**Implementation guidance:** RHCOS turns on hardware NX/DEP, ASLR, and kernel hardening (for
example, `kernel.randomize_va_space=2`) by default. The `rhcos4-moderate` profile checks the
relevant sysctls.
