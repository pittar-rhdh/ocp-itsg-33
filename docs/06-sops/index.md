# Phase 6 — Standard Operating Procedures

[← Back to main](../index.md)

> **Examples only — not validated.** The commands and procedures in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

Repeatable, auditable procedures for deploying and running the platform. Each SOP is written so
that an operator who did not build the platform can follow it, and so that the records it
produces are usable as evidence.

## SOP format

Every SOP starts with a summary table, followed by the steps:

```markdown
## <SOP name>

| | |
|---|---|
| **Purpose** | What the procedure does |
| **When** | Trigger or frequency |
| **Roles** | Who performs, who approves |
| **Prerequisites** | Access, approvals, and the state the system must be in |
| **Controls** | The ITSG-33 controls the procedure supports |

### Procedure        numbered steps with exact commands
### Verification     how to confirm success
### Rollback         how to undo or recover
### Records          what to keep as evidence, and where
```

| | |
|---|---|
| **Where** | Both sides: mirror workstation (low side); registry host, admin hosts, and cluster (high side) |
| **Inputs** | The platform built in Phases 1–4 and the evidence process from [Phase 5](../05-compliance-evidence/index.md) |
| **Outputs** | Repeatable operations with records usable as evidence: change tickets, import log, approvals, review sign-offs, test results |
| **Decisions** | AD-02, AD-12, AD-15, AD-19, AD-21, AD-22 ([Architecture decisions](../00-architecture/architecture-decisions.md)) |
| **Key controls** | CM-3, CM-4, CP-4, CP-9, CP-10, IR-4, MA-2, MA-4, SI-2, AC-2, AU-6 |

## Procedures

| Page | Procedures | Frequency |
|---|---|---|
| [Deployment checklist](deployment-checklist.md) | End-to-end checklist from Phase 0 to authorization hand-off, with sign-off gates | Once per cluster |
| [Content import](content-import.md) | Monthly content import; emergency CVE import; daily RHACS vulnerability data | Monthly; on demand; daily |
| [Upgrades](upgrades.md) | OpenShift Update Service setup; z-stream upgrade; Control Plane Only (EUS-to-EUS) upgrade; operator upgrades with manual install plans; mirror registry and registry host patching | Monthly; per EUS release; on demand |
| [Certificate rotation](certificate-rotation.md) | Cluster trust bundle; ingress and API certificates; registry, BMC, IdP, SIEM, and Git certificates; expiry monitoring | Before expiry; monthly check |
| [Backup and restore](backup-and-restore.md) | etcd backup and restore; OADP backup check and quarterly restore test; registry host and oc-mirror state; Git and Argo CD | Daily; quarterly |
| [Access management](access-management.md) | Onboarding and offboarding; quarterly access review; break-glass use and review; registry robot token rotation | On demand; quarterly |
| [Security operations](security-operations.md) | Daily security review; RHACS data import; scan review and POA&M; file integrity alerts; audit log review; incident response platform actions | Daily; weekly; on demand |
| [Node management](node-management.md) | Add, replace, drain, and decommission nodes; BMC credential rotation | On demand |
| [Troubleshooting](troubleshooting.md) | Symptom-based diagnosis of platform faults; collecting must-gather on the high side for a support case | On demand |

Every procedure that changes the cluster or the registry starts from an approved change ticket,
and configuration changes go through a pull request to `04-gitops/`, never through direct edits
(Argo CD reverts them).
