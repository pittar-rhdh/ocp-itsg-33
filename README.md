# OpenShift 4.22 on Bare Metal, Air-Gapped, for ITSG-33

[Open in Dev Spaces](https://devspaces.apps.prime.pitt.ca/#https://github.com/pittar-rhdh/ocp-itsg-33)

A lightweight, prescriptive reference guide for deploying **Red Hat OpenShift Container
Platform 4.22** on **bare metal** (IPI) in an **air-gapped** environment, and configuring,
evidencing, and operating it against the Canadian **ITSG-33** controls (PBMM profile).

| Phase | Content |
|---|---|
| 0 — Architecture | Reference architecture, architecture decisions, shared responsibility |
| 1 — Content mirroring | `oc-mirror` v2 on the low side; transfer and chain of custody |
| 2 — High-side setup | Registry host, mirror registry, populating it |
| 3 — Cluster install | Bare-metal IPI (Redfish virtual media or PXE), install-time security settings |
| 4 — ITSG-33 configuration | Control guidance and configuration as code (GitOps, ACM policies) |
| 5 — Compliance and evidence | Compliance Operator, ACM, RHACS reporting, evidence bundles, SRTM |
| 6 — SOPs | Deployment, Day 2, upgrades, troubleshooting |

> **Examples only — not validated.** The example files, commands, and procedures in this
> repository are examples. They have not been run end to end against a real Red Hat subscription,
> air-gapped environment, bare-metal hardware, or OpenShift cluster. Test and adapt them before
> use. See [docs/reference/validation-status.md](docs/reference/validation-status.md).

Start at **[docs/index.md](docs/index.md)**. This is a reference, not an automation tool: there
are no scripts. The docs show the commands for each step, and these directories hold example
files that show what the configuration should look like:

| Directory | Example files |
|---|---|
| [`01-mirror/`](01-mirror/) | `ImageSetConfiguration` for oc-mirror v2, signature policy, transfer record template |
| [`03-install/`](03-install/) | `install-config.yaml` for bare-metal IPI (virtual media, PXE excerpt), Butane and network manifests |
| [`04-gitops/`](04-gitops/) | GitOps repository: bootstrap, Kustomize components, cluster overlay, ACM policies |

Versions are recorded in [docs/reference/versions.md](docs/reference/versions.md).

The documentation is published with Backstage TechDocs (`mkdocs.yaml`, `techdocs-core`).
