# Versions and Pinned Content

[← Back to main](../index.md)

All version choices live in one file at the root of the repository: **`versions.env`**. Scripts
in every phase source it, so the release that is mirrored on the low side is the release that
is installed and upgraded on the high side.

`versions.env` says **what** is mirrored and installed. **Where** data is stored on each host is
in per-phase settings files (`01-mirror/settings.env`, `02-high-side/settings.env`), which are not
version pins.

## Rules

1. Change versions **only** in `versions.env`, through a reviewed pull request. The Git history is
   CM-3 (change control) evidence.
2. After any change, regenerate `01-mirror/imageset-config.yaml` with
   `01-mirror/04-render-imageset-config.sh` and commit both files together. Mirroring refuses to
   run if they don't match.
3. Every transfer records the commit it was built from in its `MANIFEST.json`.
4. Local experiments use `versions.local.env`, which is git-ignored and loaded last. Exported
   environment variables do **not** override `versions.env`.
5. Operators start at the head of their default channel. Pin channels and minimum versions
   deliberately, using the report from `01-mirror/03-list-operator-channels.sh`. See
   [ImageSetConfiguration](../01-mirroring/imageset-configuration.md#operator-entries).

## What is pinned

| Variable | Meaning |
|---|---|
| `OCP_MINOR`, `OCP_CHANNEL` | OpenShift minor release and update channel (`stable-4.22`, or `eus-4.22`) |
| `OCP_MIN_VERSION`, `OCP_MAX_VERSION` | Range of z-stream releases to mirror; `OCP_MAX_VERSION` is the install target |
| `OCP_MIRROR_GRAPH` | Whether to mirror update graph data for OpenShift Update Service |
| `OC_MIRROR_API_VERSION` | `ImageSetConfiguration` API version for `oc-mirror` v2 |
| `MIRROR_ARCHIVE_SIZE_GB` | Maximum archive file size, to fit the transfer media |
| `MIRROR_REGISTRY_VERSION` | mirror registry for Red Hat OpenShift release used on the high side |
| `BUTANE_VERSION` | Butane release used to generate install-time MachineConfigs (Phase 3) |
| `RHACS_VERSION` | `roxctl` and offline vulnerability data; must match the installed RHACS |
| `OCP_OPERATOR_CATALOG`, `CERTIFIED_OPERATOR_CATALOG` | Source operator catalogs |
| `OPERATORS` | Red Hat operator packages to mirror: pipe-separated package, channels, minimum version, and default channel |
| `CSI_OPERATORS` | Vendor CSI driver operator for the enterprise storage (AD-13), same format |
| `ADDITIONAL_IMAGES` | Extra images (support tools, base images) |
| `AI_OPERATORS` (commented out) | Placeholder for the [AI workloads backlog item](backlog.md#ai-workloads-gpu-accelerated-nodes-openshift-ai) |

## Operators and why they are mirrored

The package names are **examples**. Confirm every one against the live catalog with
`01-mirror/03-list-operator-channels.sh` before the first import. The **Source** column shows
where each name was checked against Red Hat documentation (OpenShift 4.22 and layered-product
documentation on docs.redhat.com, November 2026).

| Package | Purpose | Phase | Source |
|---|---|---|---|
| `cincinnati-operator` | OpenShift Update Service (offline update graph) | 6 (upgrades) | Not confirmed in Red Hat documentation; check the catalog |
| `kubernetes-nmstate-operator` | Day 2 host networking | 4 | Not confirmed; check the catalog |
| `metallb-operator` | `LoadBalancer` services on bare metal | 4 | 4.22 Hosted control planes, "Deploying hosted control planes in a disconnected environment" (`ImageSetConfiguration` example) |
| `openshift-gitops-operator` | GitOps (Argo CD) | 4 | Not confirmed; check the catalog |
| `advanced-cluster-management`, `multicluster-engine` | Governance policies and compliance reporting. ACM depends on MCE, and oc-mirror doesn't add dependencies, so both are listed. | 4, 5 | 4.22 Edge computing, "Pre-caching images" (`ImageSetConfiguration` example) |
| `rhacs-operator` | Vulnerability management, admission control, runtime detection | 4, 5 | Not confirmed; check the catalog |
| `compliance-operator` | OpenSCAP scans (NIST 800-53 Moderate → ITSG-33 PBMM) | 4, 5 | 4.22 Disconnected environments, "How filtering works in the operator catalog" |
| `file-integrity-operator` | AIDE file integrity monitoring | 4, 5 | Not confirmed; check the catalog |
| `security-profiles-operator` | seccomp and SELinux profiles | 4 | Not confirmed; check the catalog |
| `openshift-cert-manager-operator` | Certificates from the departmental PKI | 4 | Not confirmed; check the catalog |
| `openshift-external-secrets-operator` | Secrets from the departmental vault. Red Hat requires cert-manager to be installed and working **before** it. | 4 | 4.22 Security and compliance, chapter 13 (`Subscription` example, channel `stable-v1`) |
| `cluster-logging`, `loki-operator` | Log collection, forwarding, short-term storage. Red Hat requires both to be on the **same** channel and updated together. | 4 | OpenShift Logging 6.x upgrade documentation (subscription examples) |
| `cluster-observability-operator` | Logging UI plugin and observability extras | 4 | Not confirmed; check the catalog |
| `redhat-oadp-operator` | Backup and restore | 4, 6 | Not confirmed; check the catalog |
