# Phase 6 — Standard Operating Procedures

[← Back to main](../index.md)

> **Examples only — not validated.** The scripts and configuration in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

> **Status:** Planned. This page defines the scope of the phase and the SOP format. The
> procedures are added in the Phase 6 work.

Repeatable, auditable procedures for deploying and running the platform. Each SOP is written so
that an operator who did not build the platform can follow it, and so that the records it
produces are usable as evidence.

## SOP format

Every SOP uses the same sections:

| Section | Content |
|---|---|
| **Purpose and scope** | What the procedure does and when to use it |
| **Roles** | Who performs, who approves, who is informed |
| **Prerequisites** | Access, tools, approvals, and the state the system must be in |
| **Procedure** | Numbered steps with exact commands |
| **Verification** | How to confirm success |
| **Rollback** | How to undo or recover |
| **Records and evidence** | What to keep, and where |
| **Related controls** | The ITSG-33 controls the procedure supports |

## Planned procedures

| Area | Procedures |
|---|---|
| **Deployment** | End-to-end checklist that ties Phases 1–4 together, with sign-off points |
| **Day 2** | Monthly content import; emergency CVE import; certificate rotation; adding or replacing a `BareMetalHost`; etcd backup and restore; OADP backup and restore test; user onboarding and offboarding; break-glass use and review; compliance scan review and POA&M update; RHACS vulnerability feed update |
| **Upgrades** | Z-stream upgrade; y-stream EUS-to-EUS upgrade; operator upgrades with manual approval; registry host and mirror registry upgrades |
| **Troubleshooting** | Bootstrap and Ironic/BMC failures; image pull and mirror (IDMS/ITMS) errors; certificate trust problems; degraded `MachineConfigPool`; catalog source problems; collecting `must-gather` on the high side and releasing it for a support case |

Key controls: CM-3, CM-4, CP-4, CP-9, CP-10, IR-4, MA-2, MA-4, SI-2, AC-2, AU-6.
