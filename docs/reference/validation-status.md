# Validation Status and Sources

[← Back to main](../index.md)

> **Everything in this repository is an example.** The scripts, configuration files, and
> procedures show one way to build the platform. **None of them has been run end to end against a
> real Red Hat subscription, a real air-gapped environment, real bare-metal hardware, or a real
> OpenShift cluster.** Review, adapt, and test every part in a non-production environment, and
> check it against the current Red Hat documentation for your exact versions, before you rely on
> it. Nothing here replaces Red Hat documentation, Red Hat support, or your department's SA&A
> process.

## What was and wasn't tested

Testing was done in a development container (RHEL 9 userspace, no FIPS mode, no systemd, no Red
Hat pull secret), in November 2026.

| Component | What was exercised | What was **not** tested |
|---|---|---|
| `01-mirror/01-download-tools.sh` | Real downloads of `oc`, `oc-mirror` (4.22.18), mirror registry 2.0.9, and `roxctl` 4.11.7 from mirror.openshift.com, including Red Hat GPG verification of the checksum lists | Running on a FIPS-mode host |
| `01-mirror/02-check-workstation.sh` | Ran; checks reported as expected for the container | A real RHEL 9 FIPS workstation |
| `01-mirror/04-render-imageset-config.sh` | Rendering, `--check`, input validation; the generated file was accepted by the real `oc-mirror` 4.22 | Mirroring the rendered content (needs a pull secret) |
| `01-mirror/05-mirror-to-disk.sh` | Real `oc-mirror --v2` mirror-to-disk with small public UBI images, including incremental runs | Release and operator catalogs (needs a pull secret); signature verification (`MIRROR_VERIFY_SIGNATURES`) |
| `01-mirror/06-download-rhacs-db.sh` | Real download of the RHACS 4.11.7 offline vulnerability data | Import into RHACS Central |
| `01-mirror/07-package-transfer.sh`, `08-verify-transfer.sh` | Packaging, signing with a throwaway GPG key, ordering chain; verification rejected a modified archive, an added file, an edited `SHA256SUMS`, a wrong key, and a missing signature | Real removable media or a cross-domain solution |
| `02-high-side/01-accept-transfer.sh` | Acceptance, ordering refusals, ledger, tool unpacking | — |
| `02-high-side/02-check-registry-host.sh` | Certificate checks against a test CA with good and bad certificates; the host checks ran (and correctly failed in the container) | A real hardened RHEL 9 FIPS registry host |
| `02-high-side/03-install-mirror-registry.sh` | **Not run.** The mirror registry installer couldn't run in the container. Flags were checked against the Red Hat 4.22 documentation and the upstream `quay/mirror-registry` source | Everything |
| `02-high-side/04-harden-mirror-registry.sh` | Configuration editing against the upstream mirror registry `config.yaml` template; health, anonymous-access, and TLS checks against a mock HTTPS server | A real mirror registry (whether Quay accepts the settings and restarts cleanly) |
| `02-high-side/05-configure-registry-access.sh` | Against a **mock** of the Red Hat Quay API written from the Quay API documentation | A real mirror registry |
| `02-high-side/06-disk-to-mirror.sh` | Real `oc-mirror --v2` disk-to-mirror into a TLS registry (`registry:2`), two ordered imports, cluster resources captured | The mirror registry (Quay); release and operator content; signature and catalog resources |
| `02-high-side/07-extract-installer.sh` | Against a **stub** `oc` (logic and checks only) | Real extraction of `openshift-install-fips` |
| `02-high-side/08-publish-repo.sh` | Against local bare Git repositories, including the divergence refusal | A real departmental Git server |
| `03-install/01-check-provisioner.sh` | Ran in the container (host checks fail as expected there); hand-off checks (installer checksum, pinned release, pull secret contents) against stub inputs | A real RHEL 9 FIPS provisioner with libvirt and bridges |
| `03-install/02-validate-environment.sh` | DNS, PTR, registry, and release checks against stubbed `dig` and `oc`; Redfish checks against a **mock** HTTPS Redfish endpoint (good and bad credentials, untrusted certificate) | Real DNS, real BMCs, IPMI |
| `03-install/03-render-install-config.sh` | Rendering for virtual media and PXE inventories, credentials with special characters, static bootstrap and BMC CA options, and the negative checks (ed25519 key, VIP outside the machine network, wrong BMC driver, `disableCertificateVerification: true`, missing credentials, reused directory); output parsed with PyYAML | Acceptance by the real `openshift-install-fips` (the installer was a **stub**); `nmstatectl gc` (not installed in the container) |
| `03-install/04-create-manifests.sh` | Real **Butane 0.29** conversion of the chrony and TPM 2.0 disk-encryption configs (`variant: openshift`, `version: 4.22.0`) and the IPsec manifest, with a **stub** installer | Real `create manifests`; whether the cluster accepts the IPsec manifest at install time |
| `03-install/05-install-cluster.sh` | **Not run** (needs hardware) | Everything |
| `03-install/06-post-install.sh` | Verification and `--configure` logic against a **stub** `oc` with canned responses (healthy and failing cases) | A real cluster |
| `04-gitops/` manifests (bootstrap, components, overlay `ocp1`, ACM policies) | Rendered with kustomize v5.4.2 (`oc kustomize`); **kubeconform `-strict`** against the Kubernetes schemas plus JSON schemas generated from the **upstream CRDs** (openshift/api, argocd-operator, cluster-logging-operator, Loki operator, stackrox release-4.11, compliance-operator, file-integrity-operator, multiclusterhub-operator, governance-policy-propagator, oadp-operator, observability-operator, network-policy-api v0.1.7): 98 of 99 objects valid, the `Template` has no schema; yamllint; the repository rules of `07-validate.sh`, including negative tests (Secret, Automatic approval, CHACHA20, mismatched Git URL) | Applying anything to a cluster; CRD CEL rules and admission webhooks; whether the operators accept the values; Argo CD server-side apply and diff behaviour on cluster singletons; the operator channel names against a live catalog |
| `04-gitops/01-bootstrap-gitops.sh` | Checks and `--apply` path against a **mock** `oc` (install plan approval, Git CA ConfigMap patch, repository Secret, root app, change log); the Secret and ConfigMap rendering with the **real** `oc` client (`--dry-run=client`, `label --local`) | A real GitOps operator install and Argo CD sync |
| `04-gitops/02-approve-installplans.sh` | Listing, single approval, `--all-in-repo` filtering to the overlay's namespaces, error cases, change log, against a mock `oc` | Real install plans |
| `04-gitops/03-create-secrets.sh` | Dry run, `--apply`, skip logic, file-mode enforcement, newline stripping of the client secret, change log with SHA-256, against a mock `oc` | Whether OAuth, the log forwarder, Loki, and OADP accept the objects |
| `04-gitops/04-rhacs-register-cluster.sh`, `06-import-rhacs-feed.sh` | Endpoint, CA and credential discovery, idempotence, newest-file selection, age and version warnings, ledger entry, file move, against a mock `oc` and a mock `roxctl` | Real `roxctl` against Central (the `crs generate` and `upload-db` syntax is from Red Hat documentation; `--ca`, `ROX_ADMIN_PASSWORD`, and the `central-tls`/`ca.pem` and `central-htpasswd` names are not verified) |
| `04-gitops/05-lock-down-access.sh` | Refusal as `system:admin`, group and binding checks, removal and idempotence, against a mock `oc` | A real cluster |
| `04-gitops/07-validate.sh` | Run in full (shellcheck, yamllint, kubeconform, rules) | `--server` (needs a cluster) |
| Documentation | Strict MkDocs build; link and anchor check | Review by Red Hat, CCCS, or an assessor |

## Sources

Red Hat facts in this repository (commands, flags, file names, behaviour, package names) were
checked against **docs.redhat.com** through the Red Hat documentation search tool in November
2026, mainly:

| Topic | Red Hat document |
|---|---|
| oc-mirror v2 workflows, flags, `ImageSetConfiguration` parameters, operator filtering, cache and workspace, generated resources | OpenShift 4.22 *Disconnected environments*, chapter 5 |
| oc-mirror prerequisites (umask, RHEL-specific binaries, credentials) | OpenShift 4.22 *Disconnected environments*, chapters 5 and 7 |
| Mirror registry for Red Hat OpenShift: flags, local install, certificate replacement, limitations | OpenShift 4.22 *Disconnected environments*, chapter 4 |
| Digest pinning of catalogs, `oc mirror list` in v2 | OpenShift 4.22 *Release notes*, section 1.3.13 |
| FIPS-capable installer extraction | OpenShift 4.22 *Installation overview*, chapter 4 |
| Bare-metal IPI installer extraction and prerequisites | OpenShift 4.22 *Installing on bare metal*, chapter 3 |
| External Secrets Operator package, channel, and prerequisites | OpenShift 4.22 *Security and compliance*, chapter 13 |
| Logging and Loki operator channels | Red Hat OpenShift Logging 6.x *Upgrade* |
| RHACS offline mode and vulnerability definitions | Red Hat Advanced Cluster Security for Kubernetes 4.11 *Configuring*, "Enabling offline mode" |
| OpenShift GitOps: operator namespace and channel, default instance, permissions of the default instance for cluster configuration | Red Hat OpenShift GitOps documentation (installing, configuring the default instance) |
| PolicyGenerator in OpenShift GitOps (init container, `PolicyGenerator-not-fips-compliant`), GitOps cluster role | ACM 2.16 *GitOps*, chapter 1.9 |
| ACM in disconnected clusters (`mce-subscription-spec` annotation); FIPS cipher note (`spec.ingress.sslCiphers`) | ACM 2.16 *Install*; ACM 2.10 *Install* (FIPS notice) |
| cert-manager Operator install (namespace, OperatorGroup, `stable-v1`, AllNamespaces from 1.15) | OpenShift 4.22 *Security and compliance*, chapter 11 |
| Loki and Logging Operator install (namespaces, OperatorGroups, `stable-6.x`, LokiStack and S3 secret keys) | Red Hat OpenShift Logging 6.3 *Installing logging*; 6.6 and 6.7 *Upgrade* |
| RHACS Operator namespace, Central in `stackrox`, cluster registration secrets (`roxctl central crs generate`) | RHACS 4.11 *Installing*, chapter 4; RHACS 4.11 *RHACS Cloud Service*, chapter 7 |
| `allowedRegistries` must keep `registry.redhat.io`, `quay.io`, and the internal registry, also on disconnected clusters | OpenShift 4.13–4.16 *Images*, "Image configuration resources" (the 4.22 page was not returned by the search tool) |
| oc-mirror v2 catalog source naming (`cs-redhat-operator-index-v4-18` for the v4.18 index) | Red Hat OpenStack Services on OpenShift 18.0, "Mirror required Operators and images" |
| Quay TLS, `SSL_PROTOCOLS`, API (robots, teams, default permissions) | Red Hat Quay 3.x *Securing Red Hat Quay*, *Use Red Hat Quay*, *Managing access and permissions* |
| Bare-metal IPI: prerequisites, networks, ports, DNS, provisioner preparation, `install-config.yaml` parameters, BMC addressing, root device hints, no provisioning network, host network interfaces, user-managed load balancer | OpenShift 4.22 *Installing on bare metal*, chapter 3 (sections 3.2 and 3.3) |
| Boot disk encryption (TPM v2 and Tang, Tang UPI-only, LUKS2 AES-256-XTS, Butane example) | OpenShift 4.22 *Installation configuration*, chapter 1.7 |
| `install-config.yaml` common parameters (`additionalTrustBundlePolicy`, `capabilities`, `fips`, FIPS host requirement, SSH key types in FIPS mode) | OpenShift 4.22 *Installing on Nutanix*, chapters 4 and 7 (shared parameter tables; used because the bare-metal chapter was truncated by the search tool) |

Where documentation was silent, details were taken from **upstream source code** and are marked
as such where they matter: the `quay/mirror-registry` installer (flag defaults, `config.yaml`
template, systemd units), `openshift/oc` (`openshift-install-fips` and
`openshift-baremetal-install` map to the same binary), `openshift/oc-mirror` (generated file
names), `stackrox/stackrox` (`roxctl scanner download-db --version --skip-central`),
`openshift/installer` release-4.22 (`imageDigestSources` replaces the deprecated
`imageContentSources`; `bmcVerifyCA`; optional `clusterProvisioningIP`/`bootstrapProvisioningIP`),
and `openshift/api` release-4.22 (`ipsecConfig.mode` values, APIServer encryption types and audit
profiles, `disableAllDefaultSources`). Upstream
behaviour can change without notice.

Phase 4 facts taken from upstream source: `argoproj-labs/argocd-operator` (`spec.tls.initialCerts`
is read only when the instance is created; `rbac`, `resourceTrackingMethod` fields),
`openshift/cluster-logging-operator` release-6.4 (`ClusterLogForwarder` syslog, TLS, and
`lokiStack` output fields; `serviceAccount` token source), `stackrox/stackrox` release-4.11
(`Central` `egress.connectivityPolicy: Offline`, telemetry, DB storage class; `SecuredCluster`
`clusterName`, `centralEndpoint`), `stolostron/multiclusterhub-operator` (the
`mce-subscription-spec` annotation; no `spec.ingress` field in the current API, so the FIPS
cipher setting is not applied), `stolostron/multicloud-operators-subscription` (the
`PolicyGenerator-not-fips-compliant` link points at a RHEL 8 build without the strict FIPS
runtime, AD-23), and `kubernetes-sigs/network-policy-api` (ANP/BANP CRDs are gone from `main` in
favour of `ClusterNetworkPolicy`; v0.1.7 was used for schema checks).

Not confirmed by any source and to be checked on the cluster: the operator channels in
[Operators](../04-itsg33-configuration/operators.md) other than cert-manager, External Secrets,
and the Logging `stable-6.x` pattern; the Compliance Operator variable
`ocp4-var-oauth-inactivity-timeout`; the `logging-collector-logs-writer` cluster role name; the
Cluster Observability Operator `UIPlugin` fields (schema-valid only); whether a project request
template can carry the extra `data-classification` label without a parameter.

Several operator package names in `versions.env` were not found in Red Hat documentation; see
[Versions and pinned content](versions.md#operators-and-why-they-are-mirrored). Confirm them
against the live catalog.
