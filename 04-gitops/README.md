# 04-gitops — Phase 4: ITSG-33 Configuration as Code

> **Examples only — not validated.** These manifests and scripts have not been applied to a real
> cluster. They render with kustomize and pass schema validation against the upstream CRDs, and
> the scripts were run against a mock `oc`, but nothing here has run on OpenShift. Read them, adapt
> them, and test them before use. See [validation status](../docs/reference/validation-status.md).

OpenShift GitOps (Argo CD) applies everything in this directory from the departmental Git server.
ACM policies independently report whether the configuration is in place. Full guidance:
[docs/04-itsg33-configuration](../docs/04-itsg33-configuration/index.md).

```text
04-gitops/
  bootstrap/                  applied once by 01-bootstrap-gitops.sh (GitOps operator + Argo CD RBAC)
  components/
    operators/<package>/      Namespace, OperatorGroup, Subscription (manual approval)
    <capability>/             one Kustomize component per capability, annotated itsg33/controls
  overlays/<cluster>/
    root-app.yaml             the root ("app of apps") Application
    apps/                     child Applications: itsg33-gitops, -operators, -config, -policies
    gitops/ operators/ config/ policies/   the layers, with cluster-specific patches
  acm-policies/               inform-only ITSG-33 governance policies for local-cluster
```

Run the scripts on the registry host (or another high-side admin host) with `KUBECONFIG` set.
They read `settings.env`, `02-high-side/settings.env` (Git remote, tools, ledger), and
`*.local.env` overrides. Scripts that change the cluster need `CHANGE_ID` (the change ticket) and
record each action in `EVIDENCE_DIR/changes.tsv`.

| Script | When | Purpose | Controls |
|---|---|---|---|
| `07-validate.sh [--server]` | Every change, in CI and before merge | Render all layers; repository rules; yamllint, kubeconform, shellcheck | CM-3, CM-4, SA-11 |
| `01-bootstrap-gitops.sh [--apply]` | Once | GitOps operator from the mirrored catalog; Git CA and credential; root app | CM-2, CM-3, CM-5 |
| `02-approve-installplans.sh [<ns>/<plan>... \| --all-in-repo]` | Every operator install or update | List and approve install plans, recorded | CM-3, SI-2 |
| `03-create-secrets.sh [--apply]` | Once; on rotation | Secrets that Git refers to but must not hold | IA-5, SC-12, SC-28 |
| `04-rhacs-register-cluster.sh` | Once, after Central is up | Cluster registration secret for the SecuredCluster | RA-5, SI-4, IA-5 |
| `05-lock-down-access.sh [--confirm]` | Once, after IdP login works | Remove self-provisioning and `kubeadmin` | AC-2, AC-6, IA-2 |
| `06-import-rhacs-feed.sh [file]` | At least daily | Upload the staged offline vulnerability data to Central | RA-5(2), SI-5 |

Requires: `oc` (from the Phase 2 transfer), `jq`, `python3` with `python3-pyyaml` (validation),
and `roxctl` for the RHACS scripts (Phase 1 tools, `RHACS_VERSION` set). Optional for
validation: `yamllint`, `kubeconform`, `shellcheck`.
