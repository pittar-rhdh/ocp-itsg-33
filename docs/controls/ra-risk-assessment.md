# RA — Risk Assessment

[← Back to control families](index.md) · [← Back to main](../index.md)

---

### RA-2 Security Categorization

**Implementation guidance:** Categorize the platform at the **highest category of the information it
processes** (for example, Protected B / Medium / Medium). Record the categorization of each tenant
namespace with a label (`data-classification`, enforced by the admission policy in AC-3). Use it to
decide placement (for example, dedicated node pools or separate clusters for different categories).

---

### RA-3 Risk Assessment

**Implementation guidance:** Do a **Threat and Risk Assessment (TRA)** of the platform following the
Harmonized TRA Methodology (TRA-1) or your departmental method. Container-specific threats to cover
include:

| Threat | Main mitigations (see controls) |
|---|---|
| Container escape to the node | SCC `restricted-v2`, SELinux, seccomp, RHCOS patching (AC-6, SC-39, SI-2) |
| Lateral movement between tenants | Default-deny network policies, ANP guardrails, separate clusters (AC-4, SC-7) |
| Malicious or vulnerable images | Signature verification, approved registries, RHACS scanning (SA-12, SI-7, RA-5) |
| Credential theft (tokens, kubeconfig) | MFA, short token lifetimes, bound SA tokens, audit (IA-2, IA-5, AC-12) |
| Compromise of the CI/CD supply chain | Signed commits and images, provenance, GitOps approvals (SA-10, SA-12, CM-3) |
| Exposure of etcd data | etcd encryption, disk encryption, restricted access to backups (SC-28, CP-9) |
| Misconfiguration drift | Compliance Operator, ACM policies, GitOps (CM-2, CM-6, CA-7) |
| Denial of service from noisy neighbours | Quotas, limit ranges, API Priority and Fairness (SC-5) |

---

### RA-5 Vulnerability Scanning

| Attribute | Value |
|---|---|
| **Responsibility** | Platform (platform and nodes), Tenant (application images) |
| **Inheritable by tenants** | Partial (the scanning service is provided; fixing images is the tenant's job) |
| **OpenShift capabilities** | RHACS (images, nodes, platform CVEs), Quay with Clair, Compliance Operator (configuration), Red Hat Insights Advisor (if enabled) |
| **Automated check** | Yes |

**Implementation guidance:**

- Scan images **in CI** (`roxctl image check` / `roxctl image scan`), **in the registry** (Clair),
  and **at runtime** (RHACS rescans running images as new CVE data comes in).
- Scan **nodes and platform components** with RHACS node and platform CVE scanning.
- Set remediation timelines that match the departmental patch management standard (for example,
  critical in 14 days and high in 30 days, or as the departmental policy requires).
- **RA-5(2) Update by frequency:** RHACS updates vulnerability data continuously (connected) or
  through offline bundles (disconnected). Record the update frequency for disconnected clusters.
- **RA-5(5) Privileged access:** RHACS uses sensors with cluster-level read access, so scanning is
  credentialed.

**Configuration example — fail CI builds on fixable critical vulnerabilities:**

```bash
roxctl image check \
  --endpoint "${ROX_CENTRAL_ENDPOINT}" \
  --image "registry.example.gc.ca/app/example@${DIGEST}" \
  --categories "Vulnerability Management" \
  --output table
# Exits with a non-zero code if any enforced build-time policy fails
# (for example, "Fixable Severity at least Important")
```

**Evidence:** RHACS vulnerability reports (scheduled and exported); CI pipeline logs; the remediation
tracking record (POA&M).
