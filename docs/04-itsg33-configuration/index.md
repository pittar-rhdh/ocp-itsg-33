# Phase 4 — ITSG-33 Configuration as Code

[← Back to main](../index.md)

> **Examples only — not validated.** The scripts and configuration in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

Bring the cluster to the ITSG-33 PBMM baseline from the departmental Git server. OpenShift GitOps
(Argo CD) applies the configuration in `04-gitops/`, and ACM governance policies independently
report whether it is in place. The Git history, pull request reviews, Argo CD sync history, and
the change log written by the scripts are the configuration management evidence.

| | |
|---|---|
| **Where** | High side: registry host (or another admin host) with cluster access; departmental Git |
| **Inputs** | Cluster from [Phase 3](../03-cluster-install/index.md) with the mirrored catalogs; this repository on departmental Git ([Phase 2](../02-high-side/populate-registry.md)); IdP client, SIEM certificate, S3 credentials, Git deploy token |
| **Outputs** | GitOps managing operators and platform configuration; IdP login with `kubeadmin` removed; logs forwarded to the SIEM; Compliance Operator, File Integrity, RHACS (offline) and ACM governance running; change log in the evidence directory |
| **Hands off to** | [Phase 5 — Compliance and evidence](../05-compliance-evidence/index.md) |
| **Decisions** | AD-03, AD-04, AD-07, AD-09, AD-12, AD-13, AD-14, AD-22, AD-23 ([Architecture decisions](../00-architecture/architecture-decisions.md)) |
| **Key controls** | CM-2, CM-3, CM-5, CM-6, AC-2, AC-6, IA-2, AU-2, AU-9, CA-7, RA-5, SC-8, SI-7 |

## Workflow

```text
 07-validate (CI, every change)
        │
 01-bootstrap-gitops ──> Argo CD (openshift-gitops) ──> root app ──> itsg33-gitops     (Argo CD settings, RBAC)
  (GitOps operator,                                               ├─> itsg33-operators  (Subscriptions, Manual)
   Git CA + token,                                                ├─> itsg33-config     (platform configuration)
   root app)                                                      └─> itsg33-policies   (ACM, inform only)
        │
 02-approve-installplans  (each operator install/update, under a change ticket)
 03-create-secrets        (IdP client, IdP CA, login page, SIEM TLS, Loki S3, OADP)
 04-rhacs-register-cluster (after Central is up)
 05-lock-down-access       (after IdP login works: self-provisioning and kubeadmin removed)
 06-import-rhacs-feed      (at least daily)
```

## Quick start

```bash
# On the registry host, in the clone published by 02-high-side/08-publish-repo.sh,
# with KUBECONFIG set to the installer kubeconfig (until the IdP works)
vi 04-gitops/settings.local.env                     # cluster name, Git CA/token, secret inputs
04-gitops/07-validate.sh                            # also runs in CI for every change

export CHANGE_ID=CHG0012345                         # the approved change ticket
04-gitops/01-bootstrap-gitops.sh                    # checks only
04-gitops/01-bootstrap-gitops.sh --apply
04-gitops/02-approve-installplans.sh                # review the pending CSVs
04-gitops/02-approve-installplans.sh --all-in-repo  # initial install only
04-gitops/03-create-secrets.sh --apply

# Log in through the IdP as a member of ocp-platform-admins, then:
04-gitops/04-rhacs-register-cluster.sh
04-gitops/05-lock-down-access.sh --confirm
04-gitops/06-import-rhacs-feed.sh
```

## Pages

| Page | Content |
|---|---|
| [GitOps bootstrap](gitops-bootstrap.md) | Installing OpenShift GitOps from the mirrored catalog, Argo CD RBAC and trust of the departmental Git server, the root application, sync policy |
| [Repository layout](repository-layout.md) | Components, overlays, `itsg33/controls` annotations, cluster-specific values, validation and CI, making a change |
| [Operators](operators.md) | Every Subscription, its channel and install mode, manual install plan approval, ordering constraints |
| [Platform configuration](platform-configuration.md) | What each configuration component sets and for which controls; secrets kept outside Git; RHACS; access lock-down |
| [ACM governance](acm-governance.md) | The inform-only ITSG-33 policies, placement on `local-cluster`, and why `PolicyGenerator` is not used |
| [Control families](controls/index.md) | For each ITSG-33 control: responsibility, how OpenShift meets it, the configuration in Git, and evidence |

## Repository files

| File | Purpose |
|---|---|
| `04-gitops/settings.env` | Cluster name, catalog source, Git trust, change and evidence settings, secret input paths, RHACS, validation |
| `04-gitops/bootstrap/` | Applied once: GitOps operator Subscription and the Argo CD controller binding |
| `04-gitops/components/operators/<package>/` | One Namespace, OperatorGroup, and Subscription per operator |
| `04-gitops/components/<capability>/` | One Kustomize component per capability |
| `04-gitops/overlays/<cluster>/` | Root application, child applications, and the layers with cluster-specific patches |
| `04-gitops/acm-policies/` | ITSG-33 governance policies, placement, and binding |
| `04-gitops/01-bootstrap-gitops.sh` … `07-validate.sh` | The workflow above |

## How this phase supports ITSG-33

| Control | How |
|---|---|
| CM-2, CM-6 Baseline and settings | The whole platform configuration is in Git; Argo CD `selfHeal` reverts drift; the Compliance Operator checks the result daily |
| CM-3, CM-4 Change control and impact analysis | Pull requests with review, `07-validate.sh` in CI, `CHANGE_ID` on every script action, manual install plan approval |
| CM-5 Access restrictions for change | Only the reviewed repository is a permitted source (AppProject); only `ocp-platform-admins` can sync or change Argo CD |
| AC-2, AC-6, IA-2 Accounts and least privilege | IdP groups bound to cluster roles; `kubeadmin` and self-provisioning removed; Argo CD default policy denies |
| AU-2, AU-9, AU-12 Audit | API audit policy in Git; audit and infrastructure logs forwarded to the SIEM over mutual TLS |
| CA-7 Continuous monitoring | ACM policies report on the configuration independently of Argo CD; daily Compliance Operator scans |
| RA-5, SI-5 Vulnerability scanning | RHACS Central in offline mode, with vulnerability data imported at least daily |
| SI-7 Integrity | File Integrity Operator on every node |
| IA-5, SC-28 Authenticators and data at rest | No secrets in Git (enforced by `07-validate.sh`); inputs mode 0600; only SHA-256 of inputs recorded |
