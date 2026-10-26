# Operational and Management Families (AT, MA, MP, PE, PL, PM, PS)

[← Back to control families](index.md) · [← Back to main](../index.md)

These families are mainly **organizational** or **infrastructure** responsibilities. This page
lists the points where the OpenShift platform adds to them or depends on them.

---

## AT — Awareness and Training

| Control | Platform contribution |
|---|---|
| AT-2 Security Awareness | Departmental programme (Org). |
| AT-3 Role-Based Security Training | Platform administrators: train on OpenShift security (for example, Red Hat DO280/DO380, or a security-focused course on OpenShift and RHACS). Tenant developers: secure container development and the platform's guardrails (SCC, network policy, image signing). Keep training records. |

---

## MA — Maintenance

| Control | Platform contribution |
|---|---|
| MA-2 Controlled Maintenance | Cluster updates and node maintenance follow change control (CM-3). `MachineConfigPool` pausing and `maxUnavailable` control the rollout. Node drains respect `PodDisruptionBudgets`. |
| MA-4 Non-local Maintenance | Remote administration only through the API from the MRZ, with MFA (IA-2) and auditing (AU-2). `oc debug node` is preferred over SSH. For managed OpenShift, review the provider's SRE access model and logs. |
| MA-4(2) Document non-local maintenance | The API audit log records `oc debug` and `exec` sessions. Change tickets reference them. |
| MA-5 Maintenance Personnel | Red Hat Support doesn't access self-managed clusters directly. Data is shared through support cases (`must-gather`). Clean the data before uploading. Escort or supervise any vendor remote sessions (screen sharing). |
| MA-6 Timely Maintenance | Red Hat subscription and support. Keep spare capacity (extra nodes) so a failed node can be replaced quickly. |

```bash
# Example: gather diagnostics for a support case, then review before uploading
oc adm must-gather --dest-dir=./must-gather-$(date +%F)
```

---

## MP — Media Protection

| Control | Platform contribution |
|---|---|
| MP-2 Media Access | Persistent volumes and backups hold Protected B data. Limit access with RBAC on PVCs and access controls on backup buckets. |
| MP-4 Media Storage | Off-cluster etcd snapshots and OADP backups are stored encrypted (SC-28, CP-9). |
| MP-5 Media Transport | Backups move over TLS. Physical media (bare-metal disks) are handled by Infrastructure. |
| MP-6 Media Sanitization | When nodes are retired, LUKS-encrypted disks can be crypto-erased by destroying the key (TPM clear / Tang key rotation), and then sanitized according to **ITSP.40.006** (IT Media Sanitization). Storage backends must sanitize freed PVs. |

---

## PE — Physical and Environmental Protection

Fully **Infrastructure** responsibility. For cloud deployments, inherit from the provider's
CCCS assessment. For on-premises deployments, inherit from the data centre's security controls.
Record the inheritance in the SSP.

---

## PL — Planning

| Control | Platform contribution |
|---|---|
| PL-2 System Security Plan | This reference architecture, the traceability matrix, and the architecture decisions (AD-01 to AD-08) form the core of the platform SSP. |
| PL-4 Rules of Behaviour | Platform acceptable-use rules for tenants (for example, no privileged workloads without approval, no secrets in images, and image signing required). Show them on the AC-8 banner and in onboarding. |
| PL-8 Information Security Architecture | [02 — Reference architecture](../02-reference-architecture.md). |

---

## PM — Program Management

Departmental programme controls (Org). The platform provides metrics for PM-6 (security
measures of performance), for example:

- Compliance Operator pass rate,
- mean time to remediate critical CVEs,
- percentage of namespaces with default-deny network policies, and
- percentage of production images signed.

---

## PS — Personnel Security

| Control | Platform contribution |
|---|---|
| PS-3 Personnel Screening | Platform administrators with access to Protected B systems need the right security screening (for example, Reliability Status or higher, as the department decides). This is enforced through membership of IdP groups. |
| PS-4 / PS-5 Termination and Transfer | Removing or changing a user in the IdP takes away their OpenShift access right away. Existing tokens expire within the configured maximum lifetime (AC-12). For immediate effect, delete the user's OAuth access tokens. |
| PS-7 Third-Party Personnel Security | Contractors go through the same IdP groups. For managed OpenShift, check the provider's personnel screening commitments. |

```bash
# Revoke all active OAuth tokens for a departing user (built-in OAuth model, run as cluster-admin)
oc get oauthaccesstokens -o json \
  | jq -r '.items[] | select(.userName=="<user>") | .metadata.name' \
  | xargs -r oc delete oauthaccesstokens
```
