# Phase 4 — ITSG-33 Configuration as Code

[← Back to main](../index.md)

> **Examples only — not validated.** The scripts and configuration in this phase are examples.
> They have not been run against a real Red Hat subscription, air-gapped environment, or
> cluster. Test and adapt them before use. See [Validation status](../reference/validation-status.md).

> **Status:** The control-by-control guidance is available now in
> [Control families](controls/index.md). The GitOps repository layout and deployable
> manifests are added in the Phase 4 work.

Converge the cluster to the ITSG-33 PBMM baseline, declaratively, from the departmental Git
server, so that the Git history and Argo CD sync history are configuration-management evidence.

| | |
|---|---|
| **Where** | High side (cluster and departmental Git) |
| **Inputs** | Running cluster from Phase 3; mirrored operator catalogs; this repository on departmental Git |
| **Outputs** | OpenShift GitOps managing all platform configuration; ACM governance policies annotated with ITSG-33 controls |
| **Hands off to** | [Phase 5 — Compliance and evidence](../05-compliance-evidence/index.md) |
| **Decisions** | AD-03, AD-05, AD-07, AD-09, AD-12, AD-13, AD-14 ([Architecture decisions](../00-architecture/architecture-decisions.md)) |
| **Key controls** | CM-2, CM-3, CM-5, CM-6, and the technical controls in each family guide |

## Available now

- [Control family guidance](controls/index.md): for each ITSG-33 control, who is responsible,
  how OpenShift meets it, configuration examples, and evidence.

## Planned content

| Page | Content |
|---|---|
| GitOps bootstrap | Installing OpenShift GitOps from the mirrored catalog, repository credentials and CA trust for departmental Git, app-of-apps |
| Repository layout | `components/` (one per control or capability), `overlays/<cluster>/`, and how controls are annotated on each manifest |
| Operators | Subscriptions for every operator in [`versions.env`](../reference/versions.md), with manual install plan approval |
| ACM governance | `PolicyGenerator` policies with ITSG-33 `standards`, `categories`, and `controls` annotations, targeting `local-cluster` |
| Validation | CI on the low side: `kustomize build`, schema validation, linting |

Notes gathered so far for this phase:

- RHACS **offline mode can only be enabled at installation**, not during an upgrade (RHACS
  documentation, "Enabling offline mode"). With the Operator, set
  `spec.egress.connectivityPolicy: Offline` on the `Central` resource when it is first created.
- The External Secrets Operator requires the cert-manager Operator to be installed and working
  first (OpenShift 4.22 Security and compliance, chapter 13).
- The Logging and Loki operators must be on the same channel and updated together (OpenShift
  Logging 6.x upgrade documentation).

The YAML examples in the control family guides move into `04-gitops/components/`, and the
guides link to those files, so there is one source of truth.

## Planned repository files

```text
04-gitops/
  bootstrap/
  components/<capability>/
  overlays/<cluster>/
  acm-policies/
```
