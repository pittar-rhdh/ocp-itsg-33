# Platform Configuration

[← Phase 4 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

The `itsg33-config` application applies the components selected in
`04-gitops/overlays/<cluster>/config/kustomization.yaml`.

## Components

| Component | Sets | Controls |
|---|---|---|
| `identity` | `OAuth/cluster`: OIDC IdP `gc-sso` (claims, groups), token inactivity 15 min and lifetime 8 h, login template | IA-2, IA-5, IA-8, AC-2, AC-8, AC-11, AC-12 |
| `rbac` | `ocp-platform-admins` → `cluster-admin`; `ocp-security-auditors` → `cluster-reader` | AC-2, AC-5, AC-6 |
| `system-use-notification` | Console banner (`ConsoleNotification`), `oc login` message (`motd`) | AC-8 |
| `namespace-admission` | `ValidatingAdmissionPolicy`: classification label on tenant namespaces; CUDN zone consistency | AC-3, AC-4, AC-16, SC-7 |
| `project-template` | Project request template: restricted Pod Security, labels, default-deny network policies, quota, limits | CM-2, CM-6, AC-4, SC-6, SC-7 |
| `tenant-network-policy` | `BaselineAdminNetworkPolicy` default deny between tenants; `AdminNetworkPolicy` guardrails | AC-4, SC-7 |
| `api-server` | `APIServer/cluster`: audit policy, `Custom` TLS profile, etcd `aesgcm` | AU-2, AU-12, SC-8, SC-13, SC-28 |
| `ingress-tls` | Default IngressController TLS profile | SC-8, SC-13, SC-23 |
| `kubelet-tls` | Kubelet TLS profile on the control plane and worker pools (**reboots nodes**) | SC-8, SC-13 |
| `operator-hub` | Default catalog sources disabled | CM-7, CM-11 |
| `image-policy` | Allowed registries | CM-7, CM-11, SA-12 |
| `logging` | Collector service account and roles, LokiStack (30 days), ClusterLogForwarder to the SIEM and Loki, console log view | AU-2, AU-4, AU-6, AU-9, AU-11, AU-12 |
| `compliance-scans` | Daily `ScanSetting`, tailored `ocp4-moderate`, `ScanSettingBinding` | CA-2, CA-7, CM-6, RA-5 |
| `file-integrity` | `FileIntegrity` for workers and control plane | SI-7, AU-6 |
| `rhacs` | Namespace `stackrox`, `Central` (offline, telemetry off), `SecuredCluster` | RA-5, SI-3, SI-4, CM-7 |
| `acm-hub` | `MultiClusterHub` (high availability, mirrored catalog for multicluster-engine) | CA-7, CM-6 |
| `oadp` | `DataProtectionApplication` for departmental S3; nightly `Schedule` | CP-9, CP-10 |
| `cert-manager-pki` (optional) | ACME `ClusterIssuer` and API server `Certificate` | SC-12, SC-17, IA-5(2) |

Day-1 settings from Phase 3 (`06-post-install.sh --configure`: default sources off, etcd
encryption, audit profile) are now owned by Git through `operator-hub` and `api-server`. The
values are the same, so the first sync changes nothing.

Changes with impact: `api-server` encryption changes re-encrypt etcd; `kubelet-tls` and
`image-policy` roll out through the Machine Config Operator (`KubeletConfig` reboots nodes);
`identity` restarts the OAuth server. Merge them in a maintenance window.

## Secrets kept outside Git

The configuration refers to these objects, which `04-gitops/03-create-secrets.sh --apply`
creates from files outside the repository (mode 0600 for secret material). The script never
prints values; the change log records the object name and the SHA-256 of the input.

| Object | Input (`settings.env`) | Used by |
|---|---|---|
| `openshift-config/gc-sso-client-secret` (`clientSecret`) | `IDP_CLIENT_SECRET_FILE` | OAuth IdP |
| `openshift-config/gc-sso-ca` ConfigMap (`ca.crt`) | `IDP_CA_FILE` | OAuth IdP |
| `openshift-config/itsg33-login-template` (`login.html`) | `LOGIN_TEMPLATE_FILE` | OAuth login page (AC-8) |
| `openshift-logging/siem-tls` (`ca-bundle.crt`, `tls.crt`, `tls.key`) | `SIEM_CA_FILE`, `SIEM_CERT_FILE`, `SIEM_KEY_FILE` | ClusterLogForwarder |
| `openshift-logging/logging-loki-s3` | `LOKI_S3_ENV_FILE` | LokiStack |
| `openshift-adp/cloud-credentials` (`cloud`) | `OADP_CREDENTIALS_FILE` | DataProtectionApplication |

The login template must start from `oc adm create-login-template` output, with the approved
notice added: a broken template stops every login, so keep the file under review like code.
When the departmental secret store is reachable, replace these with `ExternalSecret` resources
(External Secrets Operator, [SC-12 guidance](controls/sc-system-and-communications-protection.md)).

## RHACS

1. Central is created from Git with `egress.connectivityPolicy: Offline`. Offline mode can only be
   chosen at creation, so do not create Central any other way first.
2. `04-gitops/04-rhacs-register-cluster.sh` generates a cluster registration secret
   (`roxctl central crs generate`) and applies it to `stackrox` without writing it to disk. The
   SecuredCluster then connects. Record the CRS expiry date.
3. `04-gitops/06-import-rhacs-feed.sh` uploads the newest vulnerability data file staged by
   `02-high-side/01-accept-transfer.sh` (`roxctl scanner upload-db`), records it in the import
   ledger (`rhacs-imported`), and moves it to `HS_RHACS_DIR/imported`. Red Hat asks for new data
   at least once a day in offline mode; the script warns when the file is older than
   `RHACS_FEED_MAX_AGE_DAYS` (default 2).

roxctl verifies Central's certificate with the CA in secret `central-tls` (`ca.pem`). It uses
`ROX_API_TOKEN_FILE` if set; otherwise the admin password from `central-htpasswd`. Create an API
token for routine use and set up IdP login for RHACS.

## Access lock-down

When IdP login works and your IdP account is in `ocp-platform-admins`, run
`04-gitops/05-lock-down-access.sh --confirm`. It refuses to run as `kube:admin` or
`system:admin`, checks your group membership and the `itsg33-platform-admins` binding, then
removes project self-provisioning and the `kubeadmin` secret. The installer kubeconfig
(`system:admin` client certificate) keeps working: it is the break-glass credential sealed in
Phase 3. ACM policies keep reporting on both
([ACM governance](acm-governance.md)).
