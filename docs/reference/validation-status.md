# Validation Status and Sources

[← Back to main](../index.md)

> **Everything in this repository is an example.** The example files, commands, and
> procedures show one way to build the platform. **None of them has been run end to end against a
> real Red Hat subscription, a real air-gapped environment, real bare-metal hardware, or a real
> OpenShift cluster.** Review, adapt, and test every part in a non-production environment, and
> check it against the current Red Hat documentation for your exact versions, before you rely on
> it. Nothing here replaces Red Hat documentation, Red Hat support, or your department's SA&A
> process.

## What was and wasn't tested

This repository contains **no scripts**. It contains example configuration files and, in the
docs, example commands. Checks were done in a development container (RHEL 9 userspace, no FIPS
mode, no systemd, no Red Hat pull secret), in November 2026.

| Item | What was checked | What was **not** checked |
|---|---|---|
| `01-mirror/imageset-config.yaml` | The same content (before comments were added) was accepted by the real `oc-mirror` 4.22 | Mirroring the release and operator catalogs (needs a pull secret) |
| Phase 1 commands | An earlier, script-based version ran: real downloads of `oc`, `oc-mirror` 4.22.18, mirror registry 2.0.9, and `roxctl` 4.11.7 with Red Hat GPG verification of the checksum lists; real `oc-mirror --v2` mirror-to-disk of small public images, including incremental runs; real `roxctl scanner download-db` for 4.11.7; packaging and signature checks rejecting modified, added, and unsigned files | The command sequences as now written in the docs; a FIPS-mode workstation; real transfer media |
| Phase 2 commands | Flags, Quay `config.yaml` keys, and Quay API calls are carried over from the earlier script-based version, which was tested against the upstream `config.yaml` template, a mock Quay API, a mock HTTPS server, and a `registry:2` disk-to-mirror import | Everything as now written: a real mirror registry, `podman login --authfile` credential files, installer extraction, a departmental Git server |
| `03-install/install-config.yaml`, `install-config-pxe-excerpt.yaml` | YAML parses; VIPs and provisioning addresses are in the machine network; three control plane hosts; unique boot MAC addresses | Acceptance by `openshift-install-fips`; `nmstatectl gc` of the host network configuration |
| `03-install/manifests/*.bu`, `cluster-network-03-config.yml` | `butane --strict` 0.29.0 converts all four Butane files (TPM 2.0 LUKS root with `fips: true`; chrony); YAML parses | Whether the cluster accepts them at install time |
| Phase 3 commands | — | Not run (needs hardware): installation, Redfish and IPMI calls, Day-1 `oc` commands |
| `04-gitops/` (bootstrap, components, overlay `ocp1`, ACM policies) | All six layers render with kustomize v5.4.2 (`oc kustomize`); **kubeconform `-strict`** against the Kubernetes schemas, the datreeio CRD catalog, and JSON schemas generated from the **upstream CRDs** (openshift/api, argocd-operator, cluster-logging-operator, Loki operator, stackrox release-4.11, compliance-operator, file-integrity-operator, multiclusterhub-operator, governance-policy-propagator, oadp-operator, observability-operator, network-policy-api v0.1.7): 98 of 99 objects valid, the `Template` has no schema; yamllint; the review rules (every object annotated, no Secrets, manual approval and one catalog source on every Subscription, one Git URL, no CHACHA20, no `insecureSkipVerify`) | Applying anything to a cluster; CRD CEL rules and admission webhooks; whether the operators accept the values; Argo CD server-side apply on cluster singletons; operator channel names against a live catalog |
| Phase 4 commands (bootstrap, install plans, secrets, RHACS, lock-down) | The `oc create ... --dry-run=client` and `oc label --local` rendering of the repository Secret and Git CA ConfigMap was run with a real `oc` client | Everything against a cluster; `roxctl` against Central (`crs generate` and `upload-db` syntax is from Red Hat documentation; `--ca`, the `central-tls`/`ca.pem` key, and the CRS expiry annotation are not verified) |
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

Several operator package names in `01-mirror/imageset-config.yaml` were not found in Red Hat
documentation; see
[Versions and pinned content](versions.md#operators-and-why-they-are-mirrored). Confirm them
against the live catalog.
