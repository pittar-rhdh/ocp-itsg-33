# Deployment Checklist

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Each line links to the page with the commands; this page doesn't repeat them. Copy it into the
deployment change record and tick a line only when its record exists.

| | |
|---|---|
| **Purpose** | Track the first deployment (or a disaster rebuild) of `ocp1.example.gc.ca` through Phases 0–5 to authorization hand-off; records that each phase handed off cleanly and the PBMM baseline was reached before the decision (CA-6). Doesn't replace the SA&A package |
| **When** | Once per cluster |
| **Roles** | Performs: platform engineer. Reviews: second reviewer, never the author (CM-5, AC-5). Signs: platform lead (technical gates), content-transfer officer (media custody, MP-5), DSO/ISSO (decision, transfer, evidence gates; owns POA&M). Approves windows: change manager (CAB). Decides: authorizer |
| **Prerequisites** | Approved change ticket(s); [supporting services](../00-architecture/reference-architecture.md#supporting-services-assumed-to-exist-on-the-high-side) in place (DNS, NTP, PKI, Git, IdP, SIEM, storage, S3, RHEL content); access-controlled evidence location (Protected B once populated); this repository at a reviewed commit with the [pinned versions](../reference/versions.md) |
| **Controls** | CA-2, CA-5, CA-6, CA-7, CM-2, CM-3, CM-5, MP-5, PL-2, SA-12, SI-7 |

## Procedure

Work through the gates in order. A gate passes when every line is ticked and the signer has signed
the named record.

### 1. Phase 0: decisions and responsibilities

| | Item | Detail |
|---|---|---|
| [ ] | **Department** decisions recorded | AD-03, AD-07, AD-09, AD-14, AD-15, AD-20 in the [decision log](../00-architecture/architecture-decisions.md#decision-log), each with a [decision record](../00-architecture/architecture-decisions.md#recording-a-decision) |
| [ ] | **Default** decisions confirmed or changed | AD-05, AD-11, AD-16, AD-17, AD-18, AD-19, AD-21, AD-22, AD-23; reason recorded for each change |
| [ ] | Shared responsibilities agreed | [Shared responsibility model](../00-architecture/shared-responsibility.md), with infrastructure, shared-services, and content-transfer teams |
| [ ] | Residual risks in the TRA | For example AD-04 (management plane on the same cluster), AD-06 (TPM-only binding) |
| [ ] | Import cadence agreed and in the SSP | [Recommended cadence](../01-mirroring/ongoing-imports.md#recommended-cadence) (SI-2, RA-5(2)) |

**Gate 0 — DSO and platform lead.** Record: decision records, signed responsibility matrix.

### 2. Phase 1: content on the low side

| | Item | Detail |
|---|---|---|
| [ ] | Workstation ready; tools verified against the Red Hat key | [Mirror workstation](../01-mirroring/workstation.md#readiness-check) |
| [ ] | Transfer signing key created; fingerprint sent out of band | [Transfer signing key](../01-mirroring/workstation.md#transfer-signing-key) |
| [ ] | `01-mirror/imageset-config.yaml` reviewed and merged with the catalog report | [Review checklist](../01-mirroring/imageset-configuration.md#review-checklist-for-the-pull-request) |
| [ ] | Mirror-to-disk clean from a clean checkout; cache backed up | [Mirror to disk](../01-mirroring/mirror-to-disk.md#run) |
| [ ] | RHACS data downloaded for the mirrored RHACS version | [RHACS vulnerability data](../01-mirroring/mirror-to-disk.md#rhacs-vulnerability-data) |
| [ ] | Package built, signed, verified on the media | [Build](../01-mirroring/packaging-and-transfer.md#build-the-package), [Verify](../01-mirroring/packaging-and-transfer.md#verify-the-package) |

**Gate 1 — content-transfer officer (transfer record section 2).** Record: `MANIFEST.json`,
`SHA256SUMS`, `SHA256SUMS.asc`, low-side verification result.

### 3. Phase 2: transfer acceptance and registry readiness

| | Item | Detail |
|---|---|---|
| [ ] | Transfer public key installed; fingerprint confirmed via a second channel | [Supporting services checklist](../02-high-side/registry-host.md#supporting-services-checklist) |
| [ ] | Transfer verified on media, copied, verified again; `accepted` row | [Accept a transfer](../02-high-side/accept-transfer.md#verify-on-the-media), [Import log](../02-high-side/accept-transfer.md#the-import-log) |
| [ ] | Registry host readiness checks pass (FIPS, SELinux, auditd, NTP, DNS, storage, certificate) | [Readiness checks](../02-high-side/registry-host.md#readiness-checks) |
| [ ] | Mirror registry hardened; anonymous access refused; TLS 1.2/1.3 only | [Hardening](../02-high-side/mirror-registry.md#hardening) |
| [ ] | Robot accounts and default permissions set; temporary OAuth token deleted | [Access model](../02-high-side/mirror-registry.md#access-model) |
| [ ] | Disk-to-mirror succeeded; `cluster-resources/<ID>` kept with checksums; `imported` row | [Disk to mirror](../02-high-side/populate-registry.md#disk-to-mirror) |
| [ ] | Installer extracted, pinned to the release digest; `release.env` written | [Extract the installer](../02-high-side/populate-registry.md#extract-the-installer) |
| [ ] | Repository fast-forwarded to departmental Git; `published` row | [Publish the repository](../02-high-side/populate-registry.md#publish-the-repository) |

**Gate 2 — DSO (transfer receipt, section 4) and platform lead (registry readiness).** Record:
import log rows, readiness output, `/data/quay/hardening.log`, `release.env`.

### 4. Phase 3: pre-install validation and install

| | Item | Detail |
|---|---|---|
| [ ] | Provisioner, DNS, NTP, registry, BMC checks pass; output kept | [Checks](../03-cluster-install/prerequisites.md#checks) |
| [ ] | `install-config.yaml` prepared and checked; redacted copy kept | [Prepare the file](../03-cluster-install/install-config.md#prepare-the-file) |
| [ ] | Manifests (LUKS/TPM 2.0, chrony, IPsec) reviewed by a second person | [Add the manifests](../03-cluster-install/install-time-security.md#add-the-manifests) |
| [ ] | Install window approved; nodes off; vault entry ready | [Before you start](../03-cluster-install/run-install.md#before-you-start) |
| [ ] | Install completed; logs kept; break-glass credentials sealed immediately | [Install](../03-cluster-install/run-install.md#install), [Credentials](../03-cluster-install/run-install.md#credentials) |
| [ ] | Day-1 settings applied (default sources off, mirrored catalogs, etcd encryption, audit profile) | [Day-1 settings](../03-cluster-install/run-install.md#day-1-settings) |
| [ ] | Verification recorded: FIPS, LUKS, IPsec, chrony, release digest, operators | [Verify](../03-cluster-install/run-install.md#verify) |
| [ ] | BMC passwords rotated; `kni` sudo rule removed; install-config working copy deleted | [Credentials](../03-cluster-install/run-install.md#credentials) |

**Gate 3 — platform lead; second reviewer for install inputs.** Record: evidence directory with
`SHA256SUMS`, vault entry reference (never the secret).

### 5. Phase 4: Day-1 configuration and GitOps convergence

| | Item | Detail |
|---|---|---|
| [ ] | `04-gitops/` validation passes (render, kubeconform, yamllint, review rules) | [Validation and CI](../04-itsg33-configuration/repository-layout.md#validation-and-ci) |
| [ ] | GitOps bootstrapped; root app applied; commit recorded | [GitOps bootstrap](../04-itsg33-configuration/gitops-bootstrap.md#steps) |
| [ ] | Install plans approved in the documented order | [Approving install plans](../04-itsg33-configuration/operators.md#approving-install-plans), [Ordering constraints](../04-itsg33-configuration/operators.md#ordering-constraints) |
| [ ] | Out-of-Git secrets created; input SHA-256 values recorded | [Secrets kept outside Git](../04-itsg33-configuration/platform-configuration.md#secrets-kept-outside-git) |
| [ ] | RHACS cluster registered; first vulnerability data uploaded | [RHACS](../04-itsg33-configuration/platform-configuration.md#rhacs) |
| [ ] | IdP login works; self-provisioning and `kubeadmin` removed | [Access lock-down](../04-itsg33-configuration/platform-configuration.md#access-lock-down) |
| [ ] | **All Argo CD applications `Synced` and `Healthy`; all ACM policies `Compliant`** | Commands below; [ACM governance](../04-itsg33-configuration/acm-governance.md#policies) |

```bash
oc get applications.argoproj.io -n openshift-gitops \
  -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision'
# every row: Synced  Healthy  <commit on the change ticket>
oc get policies -n local-cluster -o custom-columns='POLICY:.metadata.name,COMPLIANT:.status.compliant'
oc get clusteroperators             # all Available=True, Degraded=False
oc get mcp                          # all UPDATED=True, DEGRADED=False
oc get csv -A | grep -v Succeeded   # header only
```

A `NonCompliant` policy must be fixed or put in the POA&M (owner, date) before Gate 4.

**Gate 4 — platform lead and DSO.** Record: output above, install plan approvals, secret input
SHA-256 values in the change ticket.

### 6. Phase 5: first compliance scan and evidence bundle

| | Item | Detail |
|---|---|---|
| [ ] | First scheduled Compliance Operator scan completed | [Check the scan ran](../05-compliance-evidence/scan-review-and-remediation.md#check-the-scan-ran) |
| [ ] | Every `FAIL` and `MANUAL` [triaged](../05-compliance-evidence/scan-review-and-remediation.md#triage): remediated through Git or in the POA&M | [CA-5](../04-itsg33-configuration/controls/ca-security-assessment-and-authorization.md#ca-5-plan-of-action-and-milestones) |
| [ ] | File Integrity Operator baseline on every node | `oc get fileintegritynodestatuses -n openshift-file-integrity` |
| [ ] | First evidence bundle built with `SHA256SUMS`, stored as Protected B | [Evidence bundle structure](../05-compliance-evidence/compliance-automation-and-evidence.md#evidence-bundle-structure-proposed) |
| [ ] | SRTM updated with evidence locations | [Control traceability matrix](../05-compliance-evidence/control-traceability-matrix.md) |

**Gate 5 — DSO.** Record: evidence bundle, its SHA-256, POA&M.

### 7. Authorization hand-off

| | Item | Detail |
|---|---|---|
| [ ] | Hand-off package assembled | Platform SSP sections, SRTM, TRA, evidence bundle, POA&M, decision records, this checklist |
| [ ] | Operating procedures in place with named owners | [Content import](content-import.md), [upgrades](upgrades.md), [certificate rotation](certificate-rotation.md), [backup and restore](backup-and-restore.md), [access management](access-management.md) |
| [ ] | First import and certificate expiry dates on the operations calendar | [Monitor expiry](certificate-rotation.md#monitor-certificate-expiry) |

**Gate 6 — authorizer (authorization decision) and DSO (hand-off received).**

## Verification

- Every gate has a signature and a record location.
- The Argo CD commit (Gate 4) matches the `transfer/<ID>` tag published in Phase 2.
- `oc get clusterversion version -o jsonpath='{.status.desired.image}'` matches `release.env`.

## Rollback

A failed gate stops the deployment; fix the cause in the owning phase and repeat the gate. Rejected
transfer: [re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining). Failed
install: new installation directory, nothing to restore ([If something fails](../03-cluster-install/run-install.md#if-something-fails)).
GitOps change: revert in Git. Record failed attempts in the change ticket.

## Records

This signed checklist (deployment change record); decision records and responsibility matrix (SSP/ADR
store); transfer record and `/data/ocp/import-log.md`; install evidence directory (Protected B store);
Argo CD/ACM output and install plan approvals (change ticket); evidence bundle, POA&M, SRTM (GRC tool).
