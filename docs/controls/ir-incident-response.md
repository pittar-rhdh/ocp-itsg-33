# IR — Incident Response

[← Back to control families](index.md) · [← Back to main](../index.md)

Incident response is mostly an organizational process. OpenShift provides the **detection,
containment, and forensic** capabilities that the process depends on.

---

### IR-4 Incident Handling

| Attribute | Value |
|---|---|
| **Responsibility** | Org (SOC / CSIRT), Platform |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | RHACS runtime detection and enforcement, `NetworkPolicy` isolation, node cordon/drain, audit logs, `oc adm must-gather` |

**Implementation guidance — a container platform playbook (excerpt):**

| Phase | Action | OpenShift mechanism |
|---|---|---|
| Detection | Runtime alert (for example, a shell spawned in a container, crypto-mining process) | RHACS runtime policy → SIEM |
| Analysis | Find the deployment, image, and who deployed it | RHACS violation details, API audit log, Git history |
| Containment — network | Isolate the pod or namespace | Apply a quarantine `NetworkPolicy` (deny all) to the affected pods |
| Containment — workload | Stop the workload while keeping evidence | Scale down the deployment, **or** keep the pod running in isolation for forensics |
| Containment — node | Stop new workloads landing on a compromised node | `oc adm cordon <node>` |
| Evidence | Preserve logs and state | Export audit logs from the SIEM, `oc get pod -o yaml`, container logs, `oc adm must-gather` |
| Eradication | Rebuild the image without the vulnerability; rotate exposed secrets | CI pipeline, External Secrets rotation |
| Recovery | Redeploy from a trusted, signed image | GitOps sync |

**Configuration example — quarantine policy (applied during an incident):**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ir-quarantine
  namespace: <affected-namespace>
spec:
  podSelector:
    matchLabels:
      itsg33/quarantine: "true"         # Label the affected pods: oc label pod <pod> itsg33/quarantine=true
  policyTypes: ["Ingress", "Egress"]
```

> Pod labels are also used by `Deployment` and `Service` selectors. Labelling a pod for quarantine
> doesn't remove it from a `Service` unless you also change the labels the `Service` selects on.
> Practise this in an exercise first.

RHACS can also **enforce** runtime policies automatically, for example by killing a pod when a
specific process runs. Use this carefully, because killing the pod destroys volatile evidence.

**Evidence:** IR playbook for the container platform; RHACS notifier configuration; exercise
records.

---

### IR-5 Incident Monitoring / IR-6 Incident Reporting

**Implementation guidance:**

- Send RHACS violations, File Integrity Operator failures, critical Alertmanager alerts, and SIEM
  correlation alerts to the SOC ticketing system.
- Report incidents according to the **GC Cyber Security Event Management Plan (GC CSEMP)**, and to
  the **Canadian Centre for Cyber Security** where required.
- Report incidents involving Red Hat product vulnerabilities to Red Hat Product Security
  (secalert@redhat.com) when they are discovered.

```yaml
# Alertmanager receiver excerpt (openshift-monitoring/alertmanager-main secret)
receivers:
  - name: soc-webhook
    webhook_configs:
      - url: https://soc.example.gc.ca/hooks/openshift
        http_config:
          tls_config:
            ca_file: /etc/alertmanager/secrets/soc-ca/ca.crt
route:
  routes:
    - matchers: ['severity="critical"']
      receiver: soc-webhook
```

---

### IR-8 Incident Response Plan

**Implementation guidance:** Add a **container platform annex** to the departmental IR plan. It
should cover:

- the playbook above,
- roles (platform on-call, SOC, application owner),
- access to the break-glass credential,
- how Red Hat support is engaged (support case severity, and sharing `must-gather` with data
  sanitization), and
- evidence handling for Protected B data.

---

### IR-2 / IR-3 Training and Testing

**Implementation guidance:** Run tabletop exercises at least once a year using platform scenarios,
for example:

- compromised CI credentials pushing a malicious image,
- a container escape attempt, or
- a deleted `ClusterLogForwarder`.
