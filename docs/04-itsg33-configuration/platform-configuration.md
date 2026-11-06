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

Day-1 settings from [Phase 3](../03-cluster-install/run-install.md) (default sources off, etcd
encryption, audit profile) are now owned by Git through `operator-hub` and `api-server`. The
values are the same, so the first sync changes nothing.

Changes with impact: `api-server` encryption changes re-encrypt etcd; `kubelet-tls` and
`image-policy` roll out through the Machine Config Operator (`KubeletConfig` reboots nodes);
`identity` restarts the OAuth server. Merge them in a maintenance window.

## Secrets kept outside Git

The configuration refers to these objects, which are created by hand, under a change ticket, from
files kept outside the repository. Create each one after its namespace exists (the operators
create `openshift-logging` and `openshift-adp`).

| Object | Input file (example) | Used by |
|---|---|---|
| `openshift-config/gc-sso-client-secret` (`clientSecret`) | OIDC client secret, one line | OAuth IdP |
| `openshift-config/gc-sso-ca` ConfigMap (`ca.crt`) | IdP CA bundle (PEM, not secret) | OAuth IdP |
| `openshift-config/itsg33-login-template` (`login.html`) | Reviewed login page | OAuth login page (AC-8) |
| `openshift-logging/siem-tls` (`ca-bundle.crt`, `tls.crt`, `tls.key`) | SIEM CA, client certificate and key | ClusterLogForwarder |
| `openshift-logging/logging-loki-s3` | Env file: `access_key_id`, `access_key_secret`, `bucketnames`, `endpoint`, `region` | LokiStack |
| `openshift-adp/cloud-credentials` (`cloud`) | AWS credentials-file format | DataProtectionApplication |

```bash
# Inputs: files outside Git, mode 0600 for secret material; values never on the command line.
cd ~/.config/ocp-gitops/ocp1

# IdP client secret (strip the trailing newline; it would become part of the secret) and CA
tr -d '\r\n' < gc-sso-client-secret > /tmp/clientSecret
oc create secret generic gc-sso-client-secret -n openshift-config \
  --from-file=clientSecret=/tmp/clientSecret --dry-run=client -o yaml | oc apply -f -
rm -f /tmp/clientSecret
oc create configmap gc-sso-ca -n openshift-config \
  --from-file=ca.crt=gc-sso-ca.crt --dry-run=client -o yaml | oc apply -f -

# Login page: start from the default template and add the approved notice
oc adm create-login-template > login.html          # once; then edit and review
oc create secret generic itsg33-login-template -n openshift-config \
  --from-file=login.html=login.html --dry-run=client -o yaml | oc apply -f -

# SIEM mutual TLS
oc create secret generic siem-tls -n openshift-logging \
  --from-file=ca-bundle.crt=siem-ca.crt \
  --from-file=tls.crt=siem-client.crt \
  --from-file=tls.key=siem-client.key --dry-run=client -o yaml | oc apply -f -

# Loki object storage
oc create secret generic logging-loki-s3 -n openshift-logging \
  --from-env-file=loki-s3.env --dry-run=client -o yaml | oc apply -f -

# OADP object storage
oc create secret generic cloud-credentials -n openshift-adp \
  --from-file=cloud=oadp-cloud-credentials --dry-run=client -o yaml | oc apply -f -

# For the change record: object names and the SHA-256 of the inputs, never the values
sha256sum gc-sso-client-secret gc-sso-ca.crt login.html siem-*.crt siem-client.key \
  loki-s3.env oadp-cloud-credentials
```

`--dry-run=client -o yaml | oc apply -f -` makes the same command work for creation and for
rotation. The login template must start from `oc adm create-login-template` output, with the
approved notice added: a broken template stops every login, so keep the file under review like
code. When the departmental secret store is reachable, replace these with `ExternalSecret`
resources (External Secrets Operator,
[SC-12 guidance](controls/sc-system-and-communications-protection.md)).

## RHACS

1. Central is created from Git with `egress.connectivityPolicy: Offline`. Offline mode can only be
   chosen at creation, so do not create Central any other way first.
2. Once Central is available, generate a cluster registration secret (CRS) and apply it to
   `stackrox` without writing it to disk (it contains credentials, IA-5). The SecuredCluster then
   connects. Record the CRS expiry date.
3. Upload the offline vulnerability data that came in with a transfer
   ([Accept a transfer](../02-high-side/accept-transfer.md)) with `roxctl scanner upload-db`.
   Red Hat asks for new data at least once a day in offline mode; an older file means scans miss
   recent CVEs. Record the file name and its SHA-256 with the import.

roxctl verifies Central's certificate with the CA in secret `central-tls` (`ca.pem`); never skip
TLS verification. It authenticates with an API token (Admin role) read from a file with
`--token-file` (or from `ROX_API_TOKEN`), so the token is not on the command line. For the initial
setup only, the admin password from secret `central-htpasswd` (`ROX_ADMIN_PASSWORD`) works
instead; create an API token for routine use and set up IdP login for RHACS.

```bash
ROX_ENDPOINT="$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443"
umask 077
oc get secret central-tls -n stackrox -o jsonpath='{.data.ca\.pem}' | base64 -d > central-ca.pem
TOKEN=~/.config/ocp-gitops/rhacs-api-token         # mode 0600

# Once: cluster registration secret, straight into the cluster
roxctl -e "${ROX_ENDPOINT}" --ca central-ca.pem --token-file "${TOKEN}" \
  central crs generate ocp1-crs --output - | oc apply -n stackrox -f -
oc get secret cluster-registration-secret -n stackrox \
  -o jsonpath='{.metadata.annotations.crs\.platform\.stackrox\.io/expires-at}{"\n"}'

# At least daily: offline vulnerability data
sha256sum scanner-vuln-updates-<version>-<date>.zip
roxctl -e "${ROX_ENDPOINT}" --ca central-ca.pem --token-file "${TOKEN}" scanner upload-db \
  --scanner-db-file=scanner-vuln-updates-<version>-<date>.zip
```

A CRS is valid for 24 hours unless `--valid-for` or `--valid-until` is given (roxctl
reference, RHACS 4.10). The expiry annotation name is taken from upstream sources, and none of
these commands has been run against a Central; confirm them for the RHACS version you mirror.

## Access lock-down

When IdP login works, log in through the IdP (not `kube:admin`, not the installer kubeconfig)
with an account in `ocp-platform-admins`, and check that the group binding from Git gives you
cluster-admin:

```bash
oc whoami                                          # an IdP user, not kube:admin or system:admin
oc get groups                                      # you are in ocp-platform-admins
oc get clusterrolebinding itsg33-platform-admins
oc auth can-i '*' '*' --all-namespaces             # yes
```

Then, under the change ticket, remove project self-provisioning (projects come through Git or a
ticket), stop the API server from restoring it, and delete the `kubeadmin` secret:

```bash
oc patch clusterrolebinding.rbac self-provisioners -p '{"subjects": null}'
oc annotate clusterrolebinding.rbac self-provisioners \
  'rbac.authorization.kubernetes.io/autoupdate=false' --overwrite
oc delete secret kubeadmin -n kube-system
```

The installer kubeconfig (`system:admin` client certificate) keeps working: it is the
break-glass credential sealed in Phase 3. ACM policies keep reporting on both
([ACM governance](acm-governance.md)).
