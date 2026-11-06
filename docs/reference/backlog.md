# Backlog and Future Scope

[← Back to main](../index.md)

Work that is planned but not part of the current phases. Each item lists what it would touch,
so the existing phases can be extended without restructuring.

## AI workloads (GPU-accelerated nodes, OpenShift AI)

**Status:** Deferred. Revisit once Phases 1–6 are complete.

Goal: add the configuration needed to run AI workloads on GPU-equipped bare-metal workers in the
air-gapped cluster, with the same ITSG-33 treatment as the rest of the platform.

| Phase | Expected additions |
|---|---|
| 0 — Architecture | GPU worker pool design (labels, taints, `MachineConfigPool`); decision records for GPU sharing (time-slicing, MIG) and whether OpenShift AI is in scope; TRA notes on model provenance and data handling |
| 1 — Mirroring | Add **Node Feature Discovery** (`nfd`, Red Hat catalog), **NVIDIA GPU Operator** (`gpu-operator-certified`, *certified* catalog), and optionally **Red Hat OpenShift AI** (`rhods-operator`) and its dependencies (for example, Serverless, Service Mesh, Authorino, depending on the OpenShift AI version) to the `ImageSetConfiguration`. NVIDIA driver images must match the RHCOS kernel of each mirrored release, so mirror driver images per OpenShift z-stream. Model images and runtime images need their own transfer path. |
| 2 — High side | Registry capacity for GPU driver and model-serving images (they are large); possibly a separate registry organization for models |
| 3 — Install | BMC and firmware prerequisites for GPU servers; adding GPU workers as `BareMetalHost`s on Day 2 rather than at install |
| 4 — Configuration | GitOps components for `NodeFeatureDiscovery`, `ClusterPolicy` (GPU Operator), and `DataScienceCluster`; FIPS compatibility review of the GPU stack and of OpenShift AI components; SCC and privilege review (the GPU driver daemonset runs privileged — record as an AC-6/CM-7 exception) |
| 5 — Evidence | Compliance Operator and RHACS coverage of GPU nodes; evidence that only approved models and images run (CM-11, SA-12) |
| 6 — SOPs | Driver and operator upgrades tied to OpenShift z-streams; GPU node troubleshooting (`nvidia-smi` through `oc debug`, DCGM metrics) |

When this work starts, add the packages (`nfd`, `gpu-operator-certified` from the certified
catalog, `rhods-operator`) to `01-mirror/imageset-config.yaml` and record them in
[Versions and pinned content](versions.md).

## Other deferred items

| Item | Notes |
|---|---|
| OpenShift Virtualization | Out of scope for now |
| Service mesh specifics | Out of scope for now |
| Second site / disaster recovery cluster | Single-site rebuild is covered; active/standby across sites is not |
| Hub-and-spoke (multiple clusters) | See [Scaling out](../00-architecture/reference-architecture.md#scaling-out) |
