# Deployment Checklist

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

One checklist for the first deployment, from architecture decisions to authorization hand-off.
It doesn't repeat the procedures. Each line links to the page that has the commands, and names
who signs and what record they keep. Copy this page into the change record for the deployment.
Tick each line only when its record exists.

## Purpose and scope

Use this checklist to track a first deployment of cluster `ocp1.example.gc.ca` through Phases 0
to 5. It also works for a rebuild after a disaster. It is the record that each phase handed off
cleanly to the next one, and that the platform reached the PBMM baseline before the authorization
decision (CA-6). It doesn't replace the SA&A package.

## Roles

| Role | Responsibility in this checklist |
|---|---|
| **Platform engineer** | Performs the steps and collects the records |
| **Second reviewer** | Reviews pull requests, manifests, and install inputs (CM-5, AC-5). Must not be the author. |
| **Platform lead** | Signs technical gates (end of each phase) |
| **Content-transfer officer** | Custody of media and the transfer record (MP-5) |
| **Departmental security officer (DSO) / ISSO** | Signs decision, transfer, and evidence gates; owns the POA&M (CA-5) |
| **Change manager (CAB)** | Approves the change tickets for each install window |
| **Authorizer** | Receives the hand-off package and makes the authorization decision (CA-6) |

## Prerequisites

- An approved change ticket (or one ticket per phase) for the deployment.
- The departmental services in [Supporting services](../00-architecture/reference-architecture.md#supporting-services-assumed-to-exist-on-the-high-side)
  exist: DNS, NTP, PKI, Git, IdP, SIEM, enterprise storage, S3, RHEL content.
- An evidence location for the deployment, with access control. The records are Protected B once
  they're populated.
- This repository at a reviewed commit, with the versions in
  [Versions and pinned content](../reference/versions.md).

## Procedure

Work through the gates in order. A gate is passed when all its lines are ticked and the signer has
signed the record named in the gate row.

### 1. Phase 0: decisions and responsibilities

| | Item | Detail |
|---|---|---|
| [ ] | Every **Department** decision recorded | AD-03, AD-07, AD-09, AD-14, AD-15, AD-20 in the [decision log](../00-architecture/architecture-decisions.md#decision-log), each with the [decision record](../00-architecture/architecture-decisions.md#recording-a-decision) |
| [ ] | **Default** decisions confirmed or changed | AD-05, AD-11, AD-16, AD-17, AD-18, AD-19, AD-21, AD-22, AD-23; record the reason for each change |
| [ ] | Shared responsibilities agreed | [Shared responsibility model](../00-architecture/shared-responsibility.md), with the infrastructure, shared-services, and content-transfer teams |
| [ ] | Residual risks in the TRA | For example AD-04 (management plane on the same cluster) and AD-06 (TPM-only binding) |
| [ ] | Import cadence agreed | [Recommended cadence](../01-mirroring/ongoing-imports.md#recommended-cadence), recorded in the SSP (SI-2, RA-5(2)) |

**Gate 0. Signed by the DSO and the platform lead.** Record: decision records (ADRs) and the
signed responsibility matrix.

### 2. Phase 1: content on the low side

| | Item | Detail |
|---|---|---|
| [ ] | Workstation ready, tools verified against the Red Hat key | [Mirror workstation](../01-mirroring/workstation.md#readiness-check) |
| [ ] | Transfer signing key created; fingerprint sent to the high side out of band | [Transfer signing key](../01-mirroring/workstation.md#transfer-signing-key) |
| [ ] | `01-mirror/imageset-config.yaml` reviewed and merged with the catalog report | [Review checklist](../01-mirroring/imageset-configuration.md#review-checklist-for-the-pull-request) |
| [ ] | Mirror-to-disk ran cleanly from a clean checkout; cache backed up | [Mirror to disk](../01-mirroring/mirror-to-disk.md#run) |
| [ ] | RHACS data downloaded for the mirrored RHACS version | [RHACS vulnerability data](../01-mirroring/mirror-to-disk.md#rhacs-vulnerability-data) |
| [ ] | Package built, signed, and verified on the media | [Build the package](../01-mirroring/packaging-and-transfer.md#build-the-package), [Verify the package](../01-mirroring/packaging-and-transfer.md#verify-the-package) |

**Gate 1. Signed by the content-transfer officer (section 2 of the transfer record).** Record:
`MANIFEST.json`, `SHA256SUMS`, `SHA256SUMS.asc`, and the low-side verification result on the
transfer record.

### 3. Phase 2: transfer acceptance and registry readiness

| | Item | Detail |
|---|---|---|
| [ ] | Transfer public key installed; fingerprint confirmed through a second channel | [Supporting services checklist](../02-high-side/registry-host.md#supporting-services-checklist) |
| [ ] | Transfer verified on the media, copied, verified again; `accepted` row in the import log | [Accept a transfer](../02-high-side/accept-transfer.md#verify-on-the-media), [The import log](../02-high-side/accept-transfer.md#the-import-log) |
| [ ] | Registry host readiness checks pass (FIPS, SELinux, auditd, NTP, DNS, storage, certificate) | [Readiness checks](../02-high-side/registry-host.md#readiness-checks) |
| [ ] | Mirror registry installed and hardened; anonymous access refused; TLS 1.2/1.3 only | [Hardening](../02-high-side/mirror-registry.md#hardening) |
| [ ] | Robot accounts and default permission set; temporary OAuth token deleted | [Access model](../02-high-side/mirror-registry.md#access-model) |
| [ ] | Disk-to-mirror succeeded; `cluster-resources/<ID>` kept with checksums; `imported` row | [Disk to mirror](../02-high-side/populate-registry.md#disk-to-mirror) |
| [ ] | Installer extracted and pinned to the release digest; `release.env` written | [Extract the installer](../02-high-side/populate-registry.md#extract-the-installer) |
| [ ] | Repository published to departmental Git by fast-forward; `published` row | [Publish the repository](../02-high-side/populate-registry.md#publish-the-repository) |

**Gate 2. Signed by the DSO (transfer receipt, section 4 of the transfer record) and the platform
lead (registry readiness).** Record: import log rows, readiness check output,
`/data/quay/hardening.log`, and `release.env`.

### 4. Phase 3: pre-install validation and install

| | Item | Detail |
|---|---|---|
| [ ] | Provisioner, DNS, NTP, registry, and BMC checks pass; output in the evidence directory | [Checks](../03-cluster-install/prerequisites.md#checks) |
| [ ] | `install-config.yaml` prepared, checked, and redacted copy kept | [Prepare the file](../03-cluster-install/install-config.md#prepare-the-file) |
| [ ] | Manifests (LUKS/TPM 2.0, chrony, IPsec) generated and reviewed by a second person | [Add the manifests](../03-cluster-install/install-time-security.md#add-the-manifests) |
| [ ] | Install-window change approved; nodes powered off; vault entry ready | [Before you start](../03-cluster-install/run-install.md#before-you-start) |
| [ ] | Install completed; logs kept; break-glass credentials sealed right away | [Install](../03-cluster-install/run-install.md#install), [Credentials](../03-cluster-install/run-install.md#credentials) |
| [ ] | Day-1 settings applied (default sources off, mirrored catalogs, etcd encryption, audit profile) | [Day-1 settings](../03-cluster-install/run-install.md#day-1-settings) |
| [ ] | Post-install verification recorded: FIPS, LUKS, IPsec, chrony, release digest, operators | [Verify](../03-cluster-install/run-install.md#verify) |
| [ ] | BMC passwords rotated; `kni` sudo rule removed; install-config working copy deleted | [Credentials](../03-cluster-install/run-install.md#credentials) |

**Gate 3. Signed by the platform lead, and by the second reviewer for the install inputs.**
Record: the evidence directory with its `SHA256SUMS`, and the vault entry reference (never the
secret).

### 5. Phase 4: Day-1 configuration and GitOps convergence

| | Item | Detail |
|---|---|---|
| [ ] | `04-gitops/` validation passes (render, kubeconform, yamllint, review rules) | [Validation and CI](../04-itsg33-configuration/repository-layout.md#validation-and-ci) |
| [ ] | GitOps bootstrapped; root app applied; commit recorded | [GitOps bootstrap](../04-itsg33-configuration/gitops-bootstrap.md#steps) |
| [ ] | Install plans approved in the documented order | [Approving install plans](../04-itsg33-configuration/operators.md#approving-install-plans), [Ordering constraints](../04-itsg33-configuration/operators.md#ordering-constraints) |
| [ ] | Secrets kept outside Git created; input SHA-256 values recorded | [Secrets kept outside Git](../04-itsg33-configuration/platform-configuration.md#secrets-kept-outside-git) |
| [ ] | RHACS cluster registered; first vulnerability data uploaded | [RHACS](../04-itsg33-configuration/platform-configuration.md#rhacs) |
| [ ] | IdP login works; self-provisioning and `kubeadmin` removed | [Access lock-down](../04-itsg33-configuration/platform-configuration.md#access-lock-down) |
| [ ] | **All Argo CD applications `Synced` and `Healthy`** | Command below |
| [ ] | **All ACM policies `Compliant`** | Command below; [ACM governance](../04-itsg33-configuration/acm-governance.md#policies) |

```bash
oc get applications.argoproj.io -n openshift-gitops \
  -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision'
# every row: Synced  Healthy  <the commit on the change ticket>

oc get policies -n local-cluster \
  -o custom-columns='POLICY:.metadata.name,COMPLIANT:.status.compliant'
# every row: Compliant

oc get clusteroperators          # all Available=True, Degraded=False
oc get mcp                       # all UPDATED=True, DEGRADED=False
oc get csv -A | grep -v Succeeded   # header only
```

A policy that stays `NonCompliant` must be fixed, or recorded in the POA&M with an owner and a
date, before Gate 4 is signed.

**Gate 4. Signed by the platform lead and the DSO.** Record: the command output above, the
install plan approvals, and the secret inputs' SHA-256 values in the change ticket.

### 6. Phase 5: first compliance scan and evidence bundle

| | Item | Detail |
|---|---|---|
| [ ] | First scheduled Compliance Operator scan completed | [Check the scan ran](../05-compliance-evidence/scan-review-and-remediation.md#check-the-scan-ran) |
| [ ] | Every `FAIL` and `MANUAL` result triaged ([Triage](../05-compliance-evidence/scan-review-and-remediation.md#triage)): remediated through Git, or added to the POA&M | [CA-5](../04-itsg33-configuration/controls/ca-security-assessment-and-authorization.md#ca-5-plan-of-action-and-milestones) |
| [ ] | File Integrity Operator baseline taken on every node | `oc get fileintegritynodestatuses -n openshift-file-integrity` |
| [ ] | First evidence bundle built, with `SHA256SUMS`, and stored as Protected B | [Evidence bundle structure](../05-compliance-evidence/compliance-automation-and-evidence.md#evidence-bundle-structure-proposed) |
| [ ] | SRTM updated with evidence locations | [Control traceability matrix](../05-compliance-evidence/control-traceability-matrix.md) |

**Gate 5. Signed by the DSO.** Record: the evidence bundle, its SHA-256, and the POA&M.

### 7. Authorization hand-off

| | Item | Detail |
|---|---|---|
| [ ] | Hand-off package assembled | SSP sections for the platform, SRTM, TRA, evidence bundle, POA&M, decision records, this checklist |
| [ ] | Operating procedures in place and owners named | Phase 6 SOPs: [content import](content-import.md), [upgrades](upgrades.md), [certificate rotation](certificate-rotation.md), [backup and restore](backup-and-restore.md), [access management](access-management.md) |
| [ ] | First scheduled import and certificate expiry dates on the operations calendar | [Monitor expiry](certificate-rotation.md#monitor-certificate-expiry) |

**Gate 6. Signed by the authorizer (authorization decision) and the DSO (hand-off received).**

## Verification

- Every gate row has a signature and a record location.
- The commit in the Argo CD output (Gate 4) matches the `transfer/<ID>` tag published in Phase 2.
- The release digest in `oc get clusterversion version -o jsonpath='{.status.desired.image}'`
  matches `release.env`.

## Rollback

A gate that fails stops the deployment. Fix the cause in the phase that owns it, and repeat the
gate. Use these phase-specific paths:

- **Rejected transfer:** [Ordering and re-baselining](../02-high-side/accept-transfer.md#ordering-and-re-baselining).
- **Failed install:** start again from a new installation directory. Disks were wiped, so there
  is nothing to restore (see [If something fails](../03-cluster-install/run-install.md#if-something-fails)).
- **GitOps change:** revert the commit in Git.

Record each failed attempt in the change ticket. Failed attempts are evidence too.

## Records and evidence

| Record | Where | Controls |
|---|---|---|
| This checklist with signatures | Deployment change record | CM-3, CA-6 |
| Decision records, responsibility matrix | SSP / ADR store | PL-2, SA-9 |
| Transfer record, import log | Records system, `/data/ocp/import-log.md` | MP-5, SI-7, SA-12 |
| Install evidence directory | Protected B evidence store | CM-2, CM-6 |
| Argo CD and ACM status output, install plan approvals | Change ticket | CM-3, CA-7 |
| First evidence bundle, POA&M, SRTM | Evidence store, GRC tool | CA-2, CA-5, CA-7 |

## Related controls

CA-2, CA-5, CA-6, CA-7, CM-2, CM-3, CM-5, MP-5, PL-2, SA-12, SI-7.
