# Evidence Collection

[← Phase 5 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

An evidence bundle is a dated folder of exports and records for one cluster and one period, with
an index mapping every artifact to ITSG-33 controls, a SHA-256 manifest, and a detached GPG
signature by the evidence custodian. Build one at least quarterly and before every authorization
decision ([Reporting cadence](reporting.md#reporting-cadence)). The SRTM points to its folders
([Control traceability matrix](control-traceability-matrix.md#evidence-locations-and-frequency)).

The **collector** is a member of `ocp-security-auditors` (`cluster-reader`, AC-6); only raw ARF
retrieval needs a platform administrator. The **evidence custodian**, a different person (AC-5,
AU-9), checks, signs, and stores the bundle and keeps the register of bundles.

## Departmental decisions

| Decision | Example in this guide |
|---|---|
| Evidence store | Access-controlled Protected B repository on the high side (ISSO, custodian, assessors) |
| Custodian and signing key | Named custodian with a dedicated GPG key, separate from the AD-15 transfer key; fingerprint in the SSP |
| Collection cadence | Quarterly and before authorization; monthly continuous monitoring report |
| Retention | Departmental schedule; at least the authorization period plus one cycle |
| RHACS compliance reports | Not scheduled; Compliance Operator exports are authoritative ([Reporting](reporting.md#compliance-reports-ca-2-ca-7)) |
| Evidence leaving the high side | Not allowed by default; reviewed summaries only ([below](#moving-evidence-off-the-high-side)) |

## Bundle layout

Each bundle is a folder `evidence/<cluster>/<YYYY-MM-DD>/` containing:

| Path | Contents | Controls |
|---|---|---|
| `README.md` | Bundle index, from `05-evidence/evidence-bundle-index.md` | — |
| `SHA256SUMS`, `.asc` | Manifest of every other file; custodian signature | AU-9 |
| `00-metadata/` | Cluster version, operators, nodes, content versions, repository commit | CM-8, SA-22 |
| `01-compliance-operator/` | Scan status, per-rule results with controls, remediations, tailoring; `manual-assessments/` | CA-2, CA-7, CM-6, SI-6, and every control in the rule annotations |
| `02-raw-arf/` | Raw ARF results per scan and node (bzip2) | CA-2, CA-2(1) |
| `03-acm-governance/` | Policies, per-cluster status, history | CA-7, CM-6, and each policy's control |
| `04-rhacs/` | Vulnerability report, data import record, Central/SecuredCluster (portal download) | RA-5, RA-5(2), SI-2, SI-4 |
| `05-configuration/` | `config.openshift.io` resources, ingress, network isolation, machine config | CM-2, CM-6, AC-4, AC-8, AC-12, SC-7, SC-8, SC-13, SC-28 |
| `06-access/` | Role bindings, groups, SCC use, IdP export | AC-2, AC-3, AC-5, AC-6, AC-14 |
| `07-logging/` | Log forwarding, audit profile, SIEM receipt record | AU-2, AU-4, AU-9, AU-12 |
| `08-integrity/` | FileIntegrityNodeStatus, AIDE failure logs, events | SI-7, SI-7(1) |
| `09-backup/` | OADP schedules and backups, restore test record | CP-4, CP-9, CP-10 |
| `10-change/` | Argo CD sync history, Git log, install plans, ClusterVersion history, tickets | CM-3, CM-4, CM-5, SI-2 |
| `11-poam/` | POA&M extract for the period | CA-5 |

## Collection commands

Run on a high-side admin host, logged in through the IdP as `ocp-security-auditors`, with `oc`,
`jq`, and `git`. `cluster-reader` may not cover every operator API; check first, and if any
answer is `no`, add a read-only `ClusterRole` bound to `ocp-security-auditors` in
`04-gitops/components/rbac/` by pull request. Do not collect with an administrator account.

```bash
for r in compliancecheckresults.compliance.openshift.io/openshift-compliance \
         policies.policy.open-cluster-management.io/local-cluster \
         applications.argoproj.io/openshift-gitops \
         fileintegritynodestatuses.fileintegrity.openshift.io/openshift-file-integrity \
         backups.velero.io/openshift-adp; do
  echo "${r}: $(oc auth can-i list "${r%/*}" -n "${r#*/}")"
done

umask 077
CLUSTER=ocp1; REPO=<path-to-clone-of-departmental-repository>
OUT="evidence/${CLUSTER}/$(date +%F)"
mkdir -p "${OUT}"/{00-metadata,01-compliance-operator/manual-assessments,02-raw-arf,03-acm-governance,04-rhacs,05-configuration,06-access,07-logging,08-integrity,09-backup,10-change,11-poam}
```

### 01-compliance-operator

```bash
CO="${OUT}/01-compliance-operator"
oc get compliancesuites,compliancescans -n openshift-compliance -o wide > "${CO}/scan-status.txt"
# Rule -> NIST SP 800-53 / ITSG-33 controls, keyed by the rule name used on check results
oc get rules.compliance -n openshift-compliance -o json \
  | jq 'reduce .items[] as $r ({}; .[$r.metadata.annotations["compliance.openshift.io/rule"]] =
        ($r.metadata.annotations["control.compliance.openshift.io/NIST-800-53"] // ""))' > "${CO}/rule-controls.json"
# One row per check, with its controls
oc get compliancecheckresults -n openshift-compliance -o json \
  | jq -r --slurpfile m "${CO}/rule-controls.json" '["scan","rule","status","severity","nist_800_53"],
      (.items[] | .metadata.annotations["compliance.openshift.io/rule"] as $rule
        | [.metadata.labels["compliance.openshift.io/scan-name"], $rule, .status, .severity, ($m[0][$rule] // "")])
      | @csv' > "${CO}/check-results.csv"
oc get compliancecheckresults -n openshift-compliance -o yaml > "${CO}/check-results.yaml"
oc get complianceremediations -n openshift-compliance -o json \
  | jq -S '[.items[] | {name: .metadata.name, object: .spec.current.object}]' > "${CO}/remediations-current.json"
oc get scansettings,scansettingbindings,tailoredprofiles -n openshift-compliance -o yaml > "${CO}/scan-configuration.yaml"
```

### 02-raw-arf

Raw ARF results stay on the result volumes for 90 scans (`rawResultStorage.rotation`). Fetching
them starts a pod that mounts the volumes, so a member of `ocp-platform-admins` does it under a
ticket. With the `oc-compliance` plugin (image `registry.redhat.io/compliance/oc-compliance-rhel8:stable`,
mirrored with the [additional images](../01-mirroring/imageset-configuration.md)); `fetch-raw`
pulls `ubi8/ubi` from the Internet by default, so set `--image` to a mirrored image with `cp` and `tar`:

```bash
podman run --rm -v ~/.local/bin:/mnt/out:Z \
  registry.example.gc.ca:8443/mirror/compliance/oc-compliance-rhel8:stable /bin/cp /usr/bin/oc-compliance /mnt/out/
oc compliance fetch-raw scansettingbindings itsg33-pbmm -n openshift-compliance \
  --image registry.example.gc.ca:8443/mirror/ubi9/ubi@sha256:<digest> -o "${OUT}/02-raw-arf"
```

Alternative (documented method): for each volume (`oc get compliancesuites itsg33-pbmm -n
openshift-compliance -o json | jq -r '.status.scanStatuses[].resultsStorage.name'`), run a
non-root pod (`RuntimeDefault` seccomp, all capabilities dropped) from mirrored `ubi9/ubi` with
`claimName: <scan-name>`, `oc cp` the results, then **delete the pod** — while it runs, the
`ReadWriteOnce` volume blocks the next scan. Keep the files compressed (`*.xml.bzip2`).

### Metadata and configuration (00, 04 to 09)

```bash
M="${OUT}/00-metadata"
oc get clusterversion version -o yaml > "${M}/clusterversion.yaml"
oc get nodes -o wide                  > "${M}/nodes.txt"
oc get csv -A -l '!olm.copiedFrom' -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase > "${M}/operators.txt"
oc get profilebundles -n openshift-compliance -o custom-columns=NAME:.metadata.name,IMAGE:.spec.contentImage,STATUS:.status.dataStreamStatus > "${M}/compliance-content.txt"
oc get applications.argoproj.io -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,REVISION:.status.sync.revision > "${M}/gitops-revisions.txt"
git -C "${REPO}" log -1 --date=iso-strict --format='%H %ad' > "${M}/repo-commit.txt"

# <folder> <file> <oc get arguments>
while read -r dir file args; do
  oc get ${args} -o yaml > "${OUT}/${dir}/${file}.yaml"
done <<'EOF'
05-configuration config-cluster       apiservers.config.openshift.io,oauths.config.openshift.io,images.config.openshift.io,proxies.config.openshift.io,networks.config.openshift.io,ingresses.config.openshift.io,consoles.config.openshift.io,operatorhubs.config.openshift.io
05-configuration ingresscontrollers   ingresscontrollers -n openshift-ingress-operator
05-configuration misc                 consolenotifications,kubeletconfigs,machineconfigpools
05-configuration network-isolation    adminnetworkpolicies,baselineadminnetworkpolicies,clusteruserdefinednetworks,userdefinednetworks -A
06-access        clusterrolebindings  clusterrolebindings
06-access        groups               groups
07-logging       logging              clusterlogforwarders.observability.openshift.io,lokistacks -A
08-integrity     fileintegrity        fileintegrities,fileintegritynodestatuses -n openshift-file-integrity
08-integrity     aide-failure-logs    configmaps -n openshift-file-integrity -l file-integrity.openshift.io/result-log
09-backup        schedules            schedules.velero.io -n openshift-adp
04-rhacs         rhacs-configuration  central,securedcluster -n stackrox
EOF

oc get machineconfigs -o custom-columns='NAME:.metadata.name,ROLE:.metadata.labels.machineconfiguration\.openshift\.io/role,CONTROLS:.metadata.annotations.itsg33/controls' > "${OUT}/05-configuration/machineconfigs.txt"
oc get ns -L itsg33/zone,k8s.ovn.org/primary-user-defined-network > "${OUT}/05-configuration/namespace-zones.txt"
oc get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin" or .metadata.name=="self-provisioners")
  | [.metadata.name, .roleRef.name, ([.subjects[]? | .kind + ":" + .name] | join(" "))] | @tsv' > "${OUT}/06-access/privileged-bindings.tsv"
oc get pods -A -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name, (.metadata.annotations["openshift.io/scc"] // "")]
  | select(.[2] != "restricted-v2") | @tsv' > "${OUT}/06-access/pods-not-restricted-v2.tsv"
oc get events -n openshift-file-integrity --field-selector reason=NodeIntegrityStatus > "${OUT}/08-integrity/events.txt"
oc get backups.velero.io -n openshift-adp -o json | jq -r '["backup","phase","started","completed"],
  (.items[] | [.metadata.name, .status.phase, .status.startTimestamp, .status.completionTimestamp]) | @csv' > "${OUT}/09-backup/backups.csv"
```

`repo-commit.txt` must match the Argo CD `REVISION`; if not, check out the deployed revision
before collecting the Git log. If BGP route advertisement is used (AD-09 alternative), add
`routeadvertisements`. The audit profile is in `config-cluster.yaml` (`APIServer` `.spec.audit`).

### Governance and change (03, 10)

```bash
ACM="${OUT}/03-acm-governance"; CHG="${OUT}/10-change"
oc get policies,placements,placementbindings -n itsg33-policies -o yaml > "${ACM}/policies.yaml"
oc get policies -n itsg33-policies -o json | jq -r '["policy","controls","cluster","compliant"],
  (.items[] | .metadata as $m | .status.status[]?
    | [$m.name, $m.annotations["policy.open-cluster-management.io/controls"], .clustername, .compliant]) | @csv' > "${ACM}/policy-status.csv"
oc get policies -n local-cluster -o json | jq -r '["policy","template","timestamp","message"],
  (.items[] | .metadata.name as $p | .status.details[]? | .templateMeta.name as $t | .history[]?
    | [$p, $t, .lastTimestamp, .message]) | @csv' > "${ACM}/policy-history.csv"
oc get applications.argoproj.io -n openshift-gitops -o json | jq -r '["application","id","revision","deployedAt"],
  (.items[] | .metadata.name as $a | .status.history[]? | [$a, .id, .revision, .deployedAt]) | @csv' > "${CHG}/argocd-sync-history.csv"
git -C "${REPO}" log --since="<period-start>" --until="<period-end>" --date=iso-strict \
  --format='%H%x09%ad%x09%an%x09%s' -- 04-gitops/ > "${CHG}/git-log.tsv"
oc get installplans -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,CSV:.spec.clusterServiceVersionNames,APPROVED:.spec.approved,PHASE:.status.phase > "${CHG}/installplans.txt"
oc get clusterversion version -o json | jq -r '["version","state","started","completed","verified","image"],
  (.status.history[] | [.version, .state, .startedTime, .completionTime, .verified, .image]) | @csv' > "${CHG}/clusterversion-history.csv"
```

### Records from outside the cluster

- `01-compliance-operator/manual-assessments/` — result and evidence of each `MANUAL` check assessed in the period, one file per check.
- `03-acm-governance/` — ACM history is short; add the monthly exports ([Reporting](reporting.md#acm-governance)).
- `04-rhacs/` — from the portal ([Reporting](reporting.md#rhacs)): `vulnerability-report-<date>.zip`,
  `vulnerability-data-imports.txt` (date and ticket of each `roxctl scanner upload-db`), and
  `compliance-report-<date>.zip` only if an RHACS compliance schedule exists.
- `06-access/` — IdP account list, MFA enforcement, joiner/mover/leaver records (AC-2, IA-2(1)), from the identity team.
- `07-logging/` — SIEM team record that audit and infrastructure logs were received throughout the period (for example a daily count), with the query (AU-6, AU-9, AU-12).
- `08-integrity/` — the ticket (approved change or incident) explaining each AIDE failure log.
- `09-backup/` — latest restore test record (CP-4) and etcd backup record ([Backup and restore](../06-sops/backup-and-restore.md#etcd-backup)).
- `10-change/` — pull request records (reviewer, approval, ticket) and change tickets closed in the
  period; Argo CD keeps only ~10 syncs, so Git and tickets are the complete record (CM-3).
- `11-poam/` — POA&M rows open or closed in the period (columns as in `05-evidence/poam-example.csv`).

## Bundle index

Copy `05-evidence/evidence-bundle-index.md` to `${OUT}/README.md`; fill in metadata, period,
people, and every missing artifact with the reason. The assessor reads it first.

## Integrity and signing

The collector checks that no secret was captured (review every match; Secret names are expected,
values are not) and writes the manifest. The custodian checks, signs, packs, and records the
bundle in the register (bundle, date, archive SHA-256, signer, location):

```bash
grep -rIEn 'BEGIN [A-Z ]*PRIVATE KEY|clientSecret:|password:' "${OUT}"
cd "${OUT}" && find . -type f ! -name 'SHA256SUMS*' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
# custodian
sha256sum --check --strict --quiet SHA256SUMS
gpg --local-user <custodian-key-fingerprint> --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS
cd - && tar --create --file "evidence-${CLUSTER}-<YYYY-MM-DD>.tar" -C "evidence/${CLUSTER}" <YYYY-MM-DD>
sha256sum "evidence-${CLUSTER}-<YYYY-MM-DD>.tar"
```

**Verification** (custodian public key imported, fingerprint checked against the SSP):

```bash
tar --extract --file evidence-ocp1-<YYYY-MM-DD>.tar && cd <YYYY-MM-DD>
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum --check --strict --quiet SHA256SUMS
find . -type f ! -name 'SHA256SUMS*' | sort | diff <(awk '{print $2}' SHA256SUMS | sort) -   # no output = nothing added/removed
```

## Handling as Protected B

A bundle describes the configuration and weaknesses of a Protected B system; it is **Protected B**:

- Mark the index and the archive name or label `PROTECTED B`.
- Store only in the approved high-side evidence store, encrypted at rest, access limited to the
  custodian, ISSO, platform security lead, and named assessors (AC-3, AC-6), and logged (AU-2).
- Never attach bundles to email or tickets; refer to them by name and archive SHA-256.
- Remove working copies from the admin host once the custodian has signed and stored the bundle.

## Retention

Keep bundles, signatures, and the register per the departmental information management schedule,
and at least for the authorization period plus one assessment cycle. The on-cluster raw results
and ACM/Argo CD histories are not retention; the bundles are. Dispose of expired bundles through
the Protected B disposal process and record it in the register.

## Moving evidence off the high side

Evidence stays on the high side unless departmental policy allows otherwise (for example a
summary for a low-side governance report), and then only the minimum:

1. **Approve** — ISSO (and system owner if required) approves the files and destination under a ticket.
2. **Minimize** — derived summaries (counts, POA&M IDs and states, control status) only; never raw
   ARF, configuration exports, AIDE logs, or vulnerability details unless the destination is approved for them.
3. **Sanitize** — remove host names, IPs, cluster/domain/user/group names, registry paths,
   certificates, and anything mapping a weakness to an asset; check with
   `grep -rIEn '([0-9]{1,3}\.){3}[0-9]{1,3}|example\.gc\.ca|BEGIN CERTIFICATE|ocp1' <export-dir>`.
4. **Review** — a second person compares with the original and confirms the classification.
5. **Re-sign** — new `SHA256SUMS` and custodian signature; the export is a new artifact.
6. **Transfer** through the approved process; record what, who, approval, and hashes in the register and transfer record.
