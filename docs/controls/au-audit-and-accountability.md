# AU — Audit and Accountability

[← Back to control families](index.md) · [← Back to main](../index.md)

OpenShift produces several audit streams:

| Source | Location | Content |
|---|---|---|
| Kubernetes API server audit | `/var/log/kube-apiserver/` on control plane nodes | Every request to the Kubernetes API |
| OpenShift API server audit | `/var/log/openshift-apiserver/` | OpenShift API requests (routes, builds, projects, and so on) |
| OAuth API server / OAuth server audit | `/var/log/oauth-apiserver/`, `/var/log/oauth-server/` | Token operations, login successes and failures |
| Node audit (auditd) | `/var/log/audit/audit.log` on every node | OS-level events (system calls, logins, privileged commands) |
| OVN ACL audit | `/var/log/ovn/acl-audit-log.log` | Allowed and denied network flows for namespaces with ACL logging enabled |
| Application logs | Container stdout/stderr | Application security events (tenant responsibility) |

All streams are collected by OpenShift Logging and forwarded to the departmental SIEM.

---

### AU-2 Auditable Events / AU-12 Audit Generation

| Attribute | Value |
|---|---|
| **Responsibility** | Platform (platform events), Tenant (application events) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | `APIServer` audit profiles and custom rules, RHCOS auditd rules (applied by the Compliance Operator), OVN ACL logging |
| **Automated check** | Compliance Operator (`ocp4-audit-profile-set`, `rhcos4-audit-*` rules) |

**Control intent (summary):** Decide which events the system must be able to audit, and make sure
the system generates audit records for them.

**Implementation guidance:**

- Set the cluster audit profile to **`WriteRequestBodies`**, so the request bodies of all
  changes (`create`, `update`, `patch`, `delete`) are recorded. Use **`AllRequestBodies`** for
  privileged groups if your profile asks for read auditing of sensitive resources. Secrets,
  OAuth tokens, and similar sensitive resources are always logged at metadata level only.
- Never set the profile to `None` on Protected B clusters.
- Apply the **`rhcos4-moderate`** remediations so auditd rules cover logins, privilege use,
  file permission changes, and kernel module loading.
- Turn on **OVN ACL audit logging** for namespaces that hold Protected B data, so allowed and
  denied network flows are recorded.

**Configuration example — API audit policy:**

```yaml
apiVersion: config.openshift.io/v1
kind: APIServer
metadata:
  name: cluster
spec:
  audit:
    profile: WriteRequestBodies
    customRules:
      - group: system:authenticated:oauth   # Human users: also record read request bodies
        profile: AllRequestBodies
      - group: ocp-platform-admins
        profile: AllRequestBodies
```

**Configuration example — network ACL audit logging for a namespace:**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: payments-prod
  annotations:
    k8s.ovn.org/acl-logging: '{"deny": "alert", "allow": "notice"}'
```

**Evidence:**

```bash
oc get apiserver cluster -o jsonpath='{.spec.audit}'
oc adm node-logs --role=master --path=kube-apiserver/ | head
oc adm node-logs <node> --path=audit/audit.log | tail
oc get compliancecheckresults -n openshift-compliance | grep -i audit
```

---

### AU-3 Content of Audit Records

**Implementation guidance:** Kubernetes audit events are structured JSON. Each event includes:

- timestamp (`requestReceivedTimestamp`, `stageTimestamp`),
- event type (`verb`, `objectRef`),
- source (`sourceIPs`, `userAgent`),
- identity (`user.username`, `user.groups`, `impersonatedUser`),
- outcome (`responseStatus.code`), and
- a correlation ID (`auditID`).

auditd records follow the standard Linux format. Together these meet AU-3 and AU-3(1) when they
reach the SIEM unchanged.

**Evidence:** a sample event from each source, showing the required fields.

---

### AU-4 Audit Storage Capacity / AU-5 Response to Audit Processing Failures

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org (SIEM) |
| **OpenShift capabilities** | Node log rotation settings, log forwarding with buffering, alerts on collector health |

**Implementation guidance:**

- Audit logs on nodes rotate locally. **Forwarding to the SIEM is the authoritative store.**
  Size the SIEM for the expected volume. `WriteRequestBodies` produces much more data than
  `Default`.
- The Vector collector buffers events if the output is unavailable. Monitor the collector and
  forwarder with OpenShift Monitoring alerts (for example, collector errors or a growing
  backlog), and send those alerts to the operations team (AU-5).
- Watch node disk usage for `/var/log` with the default `NodeFilesystemSpaceFillingUp` alerts.

**Evidence:** SIEM capacity plan; `oc get prometheusrules -A | grep -i -E 'collector|logging'`;
alert routing configuration in Alertmanager.

---

### AU-6 Audit Review, Analysis, and Reporting

| Attribute | Value |
|---|---|
| **Responsibility** | Org (SOC), Platform (use cases) |
| **OpenShift capabilities** | Forwarding to the SIEM, LokiStack alerting rules, RHACS runtime alerts |

**Implementation guidance:** Define SIEM use cases for OpenShift. Suggested starting set:

| Use case | Source | Indicator |
|---|---|---|
| Privilege escalation | API audit | `create` on `clusterrolebindings` / `rolebindings` that reference `cluster-admin` or `admin` |
| SCC tampering | API audit | `update` / `patch` on `securitycontextconstraints` |
| Interactive access to workloads | API audit | `create` on `pods/exec`, `pods/attach`, `pods/portforward` |
| Node debug access | API audit | Pods created in `openshift-debug-*` namespaces or with `hostPID` / `hostNetwork` |
| Secret access by humans | API audit | `get` / `list` on `secrets` by `system:authenticated:oauth` users |
| Authentication failures | OAuth server, IdP | Repeated failures for the same user or from the same source IP |
| Audit policy changes | API audit | `update` on `apiservers.config.openshift.io` |
| Log forwarding changes | API audit | Changes to `clusterlogforwarders` |
| Runtime threats | RHACS | Policy violations of high or critical severity |
| Integrity violations | File Integrity Operator | `FileIntegrityNodeStatus` showing `Failed` |

**AU-6(1)** automated process integration and **AU-6(3)** correlation across repositories are
handled by the SIEM.

**Evidence:** SIEM use case catalogue; sample alerts; review records.

---

### AU-7 Audit Reduction and Report Generation

**Implementation guidance:** The SIEM provides search and reporting. For on-cluster triage,
**LokiStack** (Logging UI plugin in the console) gives short-term searchable retention. Platform
staff can also use `oc adm node-logs` with filters.

---

### AU-8 Time Stamps

| Attribute | Value |
|---|---|
| **Responsibility** | Platform |
| **OpenShift capabilities** | chrony on RHCOS, configured through `MachineConfig` |
| **Automated check** | Compliance Operator (`rhcos4-chronyd-*` rules) |

**Implementation guidance:** Point every node to the departmental authoritative time sources (for
example, NRC time servers or internal stratum servers synced to them). Timestamps in audit
records are in UTC.

**Configuration example (Butane, compiled with `butane`):**

```yaml
variant: openshift
version: 4.22.0                        # Use the Butane spec version that matches your cluster
metadata:
  name: 99-worker-chrony
  labels:
    machineconfiguration.openshift.io/role: worker
storage:
  files:
    - path: /etc/chrony.conf
      mode: 0644
      overwrite: true
      contents:
        inline: |
          server ntp1.example.gc.ca iburst
          server ntp2.example.gc.ca iburst
          driftfile /var/lib/chrony/drift
          makestep 1.0 3
          rtcsync
          logdir /var/log/chrony
```

Create the same configuration for the `master` role (and any custom pools).

**Evidence:** `oc debug node/<node> -- chroot /host chronyc sources -v`

---

### AU-9 Protection of Audit Information

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org (SIEM) |
| **Inheritable by tenants** | Full |
| **OpenShift capabilities** | RBAC on log access, TLS log forwarding, off-cluster immutable storage |
| **Automated check** | Compliance Operator (`ocp4-audit-log-forwarding-enabled`, file permission rules) |

**Implementation guidance:**

- On nodes, audit log files are readable only by root. Access through the API
  (`oc adm node-logs`) needs cluster-level privileges.
- **Forward audit logs off-cluster in near real time** over TLS (or mTLS) to a SIEM managed by a
  separate team (**AU-9(2)** backup on a separate system; **AU-9(4)** access by a subset of
  privileged users).
- Use **object lock / WORM retention** on long-term log storage where it's supported.
- Restrict who can change `ClusterLogForwarder` resources, and alert on changes (see AU-6).

**Configuration example — forward audit logs to the SIEM over TLS:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: log-collector
  namespace: openshift-logging
---
# Grant the collector permission to collect each log type
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: log-collector-audit
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-audit-logs
subjects:
  - kind: ServiceAccount
    name: log-collector
    namespace: openshift-logging
# Create similar bindings for collect-infrastructure-logs and collect-application-logs
---
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: itsg33-siem
  namespace: openshift-logging
spec:
  serviceAccount:
    name: log-collector
  outputs:
    - name: siem-syslog
      type: syslog
      syslog:
        url: tls://siem.example.gc.ca:6514
        rfc: RFC5424
        facility: local0
      tls:
        ca:
          secretName: siem-tls
          key: ca-bundle.crt
        certificate:
          secretName: siem-tls
          key: tls.crt
        key:
          secretName: siem-tls
          key: tls.key
  pipelines:
    - name: audit-to-siem
      inputRefs: [audit]
      outputRefs: [siem-syslog]
    - name: infra-to-siem
      inputRefs: [infrastructure]
      outputRefs: [siem-syslog]
```

> Other output types (`splunk`, `kafka`, `http`, `elasticsearch`, `cloudwatch`,
> `azureMonitor`, `googleCloudLogging`, `lokiStack`, `otlp`) are available. Choose the one your SIEM
> supports. The outputs' TLS settings follow the cluster API server TLS profile by default.

**Evidence:**

```bash
oc get clusterlogforwarder itsg33-siem -n openshift-logging -o yaml
oc get clusterlogforwarder itsg33-siem -n openshift-logging -o jsonpath='{.status.conditions}'
```

Also collect:

- a SIEM search showing recent audit events from each cluster, and
- the object lock configuration for the archive.

---

### AU-10 Non-repudiation

**Implementation guidance:** Not normally selected for PBMM. Where it is selected:

- tie API audit events to individual identities (no shared accounts; see AC-2, IA-2),
- sign commits in GitOps repositories, and
- sign container images (see SA-12).

---

### AU-11 Audit Record Retention

| Attribute | Value |
|---|---|
| **Responsibility** | Org (SIEM and archive), Platform (on-cluster retention) |

**Implementation guidance:** Keep audit records for the period set in your departmental profile
and records retention schedule (for example, 2 years online plus archive). On-cluster
LokiStack retention can be short (for example, 7 to 30 days) for operational use, because the
SIEM and archive hold the official record.

```yaml
# LokiStack excerpt: on-cluster retention for operational search
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  limits:
    global:
      retention:
        days: 30
  # ... storage, size, tenants omitted
```

**Evidence:** SIEM and archive retention configuration; LokiStack spec.

---

### AU-14 Session Audit

**Implementation guidance:** For interactive container sessions (`oc exec`, `oc rsh`, `oc debug`), the
API audit log records who started the session, when, and against which pod. It does not record
keystrokes. If full session recording is needed, route privileged access through a bastion that
records sessions (Org/Platform).
