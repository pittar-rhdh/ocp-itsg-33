# Evidence Collection

[← Phase 5 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

An evidence bundle is a dated folder of exports, reports, and records for one cluster and one
period, with an index that maps every artifact to ITSG-33 controls, a SHA-256 manifest, and a
detached GPG signature by the evidence custodian. Build one at least quarterly and before every
authorization decision ([Reporting cadence](reporting.md#reporting-cadence)). The SRTM points to
the folders in it ([Control traceability matrix](control-traceability-matrix.md#evidence-locations-and-frequency)).

Roles:

- **Collector** — runs the commands below as a member of `ocp-security-auditors`
  (`cluster-reader`, AC-6). Raw ARF retrieval is the only step that needs a platform
  administrator.
- **Evidence custodian** — a different person (AC-5, AU-9). Checks the bundle, signs the
  manifest with the custodian key, stores the bundle, and keeps the register of bundles.

## Departmental decisions

| Decision | Example in this guide |
|---|---|
| Evidence store | An access-controlled Protected B repository on the high side, readable by the ISSO, custodian, and assessors |
| Evidence custodian and signing key | A named custodian with a dedicated GPG key, separate from the transfer key of AD-15; fingerprint recorded in the SSP |
| Collection cadence | Quarterly and before authorization; monthly continuous monitoring report |
| Retention | Departmental information management schedule; at least the authorization period plus one cycle |
| RHACS compliance reports | Not scheduled; Compliance Operator exports are authoritative ([Reporting](reporting.md#compliance-reports-ca-2-ca-7)) |
| Evidence leaving the high side | Not allowed by default; summaries only, after review ([below](#moving-evidence-off-the-high-side)) |

## Bundle layout

```text
evidence/<cluster>/<YYYY-MM-DD>/
  README.md                   bundle index, from 05-evidence/evidence-bundle-index.md
  SHA256SUMS                  SHA-256 of every other file
  SHA256SUMS.asc              detached signature of SHA256SUMS by the evidence custodian
  00-metadata/                cluster version, operators, nodes, content versions, repository commit
  01-compliance-operator/     scan status, per-rule results with controls, remediations, tailoring,
    manual-assessments/       results and evidence for MANUAL checks
  02-raw-arf/                 raw ARF results per scan and node (bzip2)
  03-acm-governance/          policies, per-cluster status, history
  04-rhacs/                   vulnerability report, data import record, Central and SecuredCluster
  05-configuration/           config.openshift.io resources, ingress, network isolation, machine config
  06-access/                  role bindings, groups, SCC use
  07-logging/                 log forwarding and audit configuration, SIEM receipt record
  08-integrity/               FileIntegrityNodeStatus, AIDE failure logs, events
  09-backup/                  OADP schedules and backups, restore test record
  10-change/                  Argo CD sync history, Git log, install plans, ClusterVersion history, tickets
  11-poam/                    POA&M extract for the period
```

| Folder | Controls | Source |
|---|---|---|
| `00-metadata/` | CM-8, SA-22 | `oc` (ClusterVersion, CSVs, nodes, ProfileBundles), Git |
| `01-compliance-operator/` | CA-2, CA-7, CM-6, SI-6, and every control in the rule annotations | Compliance Operator |
| `02-raw-arf/` | CA-2, CA-2(1) | Compliance Operator result volumes |
| `03-acm-governance/` | CA-7, CM-6, and the control of each policy | ACM |
| `04-rhacs/` | RA-5, RA-5(2), SI-2, SI-4 | RHACS portal (manual download) |
| `05-configuration/` | CM-2, CM-6, AC-4, AC-8, AC-12, SC-7, SC-8, SC-13, SC-28 | `oc` |
| `06-access/` | AC-2, AC-3, AC-5, AC-6, AC-14 | `oc` |
| `07-logging/` | AU-2, AU-4, AU-9, AU-12 | `oc`, SIEM team |
| `08-integrity/` | SI-7, SI-7(1) | File Integrity Operator |
| `09-backup/` | CP-9, CP-10, CP-4 | OADP, restore test record |
| `10-change/` | CM-3, CM-4, CM-5, SI-2 | Argo CD, Git, OLM, ClusterVersion, ticketing |
| `11-poam/` | CA-5 | POA&M |

## Collection commands

Run from an admin host on the high side, logged in through the IdP as a member of
`ocp-security-auditors`, with `oc`, `jq`, and `git`.

### Before you start

`cluster-reader` does not necessarily include every operator API. Check first:

```bash
oc whoami
oc auth can-i list compliancecheckresults.compliance.openshift.io -n openshift-compliance
oc auth can-i list rules.compliance.openshift.io -n openshift-compliance
oc auth can-i list policies.policy.open-cluster-management.io -n local-cluster
oc auth can-i list applications.argoproj.io -n openshift-gitops
oc auth can-i list fileintegritynodestatuses.fileintegrity.openshift.io -n openshift-file-integrity
oc auth can-i list backups.velero.io -n openshift-adp
```

If any answer is `no`, add a read-only `ClusterRole` for those APIs, bound to
`ocp-security-auditors`, in `04-gitops/components/rbac/` through a pull request. Do not collect
with an administrator account.

```bash
umask 077
CLUSTER=ocp1
REPO=<path-to-clone-of-departmental-repository>
OUT="evidence/${CLUSTER}/$(date +%F)"
mkdir -p "${OUT}"/{00-metadata,01-compliance-operator/manual-assessments,02-raw-arf,03-acm-governance,04-rhacs,05-configuration,06-access,07-logging,08-integrity,09-backup,10-change,11-poam}
```

### 00-metadata

```bash
oc get clusterversion version -o yaml                 > "${OUT}/00-metadata/clusterversion.yaml"
oc get csv -A -l '!olm.copiedFrom' \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase \
                                                      > "${OUT}/00-metadata/operators.txt"
oc get nodes -o wide                                  > "${OUT}/00-metadata/nodes.txt"
oc get profilebundles -n openshift-compliance \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.contentImage,STATUS:.status.dataStreamStatus \
                                                      > "${OUT}/00-metadata/compliance-content.txt"
oc get applications.argoproj.io -n openshift-gitops \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision \
                                                      > "${OUT}/00-metadata/gitops-revisions.txt"
git -C "${REPO}" log -1 --date=iso-strict --format='%H %ad' > "${OUT}/00-metadata/repo-commit.txt"
```

The commit in `repo-commit.txt` must match the `REVISION` that Argo CD reports; if not, check out
the deployed revision before collecting `10-change/git-log.tsv`.

### 01-compliance-operator

```bash
CO="${OUT}/01-compliance-operator"
oc get compliancesuites,compliancescans -n openshift-compliance -o wide > "${CO}/scan-status.txt"

# Rule -> NIST SP 800-53 / ITSG-33 controls, keyed by the rule name used on check results
oc get rules.compliance -n openshift-compliance -o json \
  | jq 'reduce .items[] as $r ({};
        .[$r.metadata.annotations["compliance.openshift.io/rule"]] =
          ($r.metadata.annotations["control.compliance.openshift.io/NIST-800-53"] // ""))' \
  > "${CO}/rule-controls.json"

# One row per check, with its controls
oc get compliancecheckresults -n openshift-compliance -o json \
  | jq -r --slurpfile m "${CO}/rule-controls.json" '
      ["scan","rule","status","severity","nist_800_53"],
      (.items[] | .metadata.annotations["compliance.openshift.io/rule"] as $rule
        | [.metadata.labels["compliance.openshift.io/scan-name"], $rule, .status, .severity,
           ($m[0][$rule] // "")])
      | @csv' > "${CO}/check-results.csv"

# Full results (descriptions, instructions), remediation payloads, and tailoring with rationale
oc get compliancecheckresults -n openshift-compliance -o yaml > "${CO}/check-results.yaml"
oc get complianceremediations -n openshift-compliance -o json \
  | jq -S '[.items[] | {name: .metadata.name, object: .spec.current.object}]' \
  > "${CO}/remediations-current.json"
oc get scansettings,scansettingbindings,tailoredprofiles -n openshift-compliance -o yaml \
  > "${CO}/scan-configuration.yaml"
```

Put the result and evidence of every `MANUAL` check assessed in the period in
`manual-assessments/` (one file per check, named after the check).

### 02-raw-arf

The raw ARF results stay on the result volumes for 90 scans (`rawResultStorage.rotation`). Fetching
them starts a pod that mounts the volumes, so a member of `ocp-platform-admins` does it, under a
ticket. Two ways:

**oc-compliance plugin.** The plugin ships as the image
`registry.redhat.io/compliance/oc-compliance-rhel8:stable`; mirror it with the other additional
images ([ImageSetConfiguration](../01-mirroring/imageset-configuration.md)), then extract the
binary on the admin host. `fetch-raw` starts its extractor pod from `ubi8/ubi` on the Internet
by default, so point `--image` at a mirrored image that contains `cp` and `tar`:

```bash
podman run --rm -v ~/.local/bin:/mnt/out:Z \
  registry.example.gc.ca:8443/mirror/compliance/oc-compliance-rhel8:stable \
  /bin/cp /usr/bin/oc-compliance /mnt/out/

oc compliance fetch-raw scansettingbindings itsg33-pbmm -n openshift-compliance \
  --image registry.example.gc.ca:8443/mirror/ubi9/ubi@sha256:<digest> \
  -o "${OUT}/02-raw-arf"
```

**A pod that mounts the volume** (the documented method, one volume at a time). The volume of
each scan has the scan's name:

```bash
oc get compliancesuites itsg33-pbmm -n openshift-compliance -o json \
  | jq -r '.status.scanStatuses[].resultsStorage.name'
```

Create a pod in `openshift-compliance` (non-root, `RuntimeDefault` seccomp, all capabilities
dropped) from the mirrored `ubi9/ubi` image with `claimName: <scan-name>`, copy the results with
`oc cp`, and **delete the pod**: while it runs, a `ReadWriteOnce` volume cannot be used by the
next scan.

```bash
oc cp openshift-compliance/<pod>:<mount-path> "${OUT}/02-raw-arf/<scan-name>"
oc delete pod <pod> -n openshift-compliance
```

Keep the ARF files compressed (`*.xml.bzip2`); assessors can open them with SCAP tools.

### 03-acm-governance

```bash
ACM="${OUT}/03-acm-governance"
oc get policies,placements,placementbindings -n itsg33-policies -o yaml > "${ACM}/policies.yaml"

oc get policies -n itsg33-policies -o json \
  | jq -r '["policy","controls","cluster","compliant"],
      (.items[] | .metadata as $m | .status.status[]?
        | [$m.name, $m.annotations["policy.open-cluster-management.io/controls"], .clustername, .compliant])
      | @csv' > "${ACM}/policy-status.csv"

oc get policies -n local-cluster -o json \
  | jq -r '["policy","template","timestamp","message"],
      (.items[] | .metadata.name as $p | .status.details[]? | .templateMeta.name as $t | .history[]?
        | [$p, $t, .lastTimestamp, .message])
      | @csv' > "${ACM}/policy-history.csv"
```

The history keeps only recent messages; the monthly exports ([Reporting](reporting.md#acm-governance))
fill the rest of the period. Copy them into this folder.

### 04-rhacs

Download from the RHACS portal ([Reporting](reporting.md#rhacs)) and save as:

| File | Content |
|---|---|
| `vulnerability-report-<date>.zip` | Vulnerability report for the cluster (platform, nodes, workloads), as downloaded |
| `vulnerability-data-imports.txt` | Date and change ticket of each `roxctl scanner upload-db` in the period |
| `compliance-report-<date>.zip` | Only if an RHACS compliance schedule exists (departmental decision) |

```bash
oc get central,securedcluster -n stackrox -o yaml > "${OUT}/04-rhacs/rhacs-configuration.yaml"
```

### 05-configuration

```bash
CFG="${OUT}/05-configuration"
for r in apiservers oauths images proxies networks ingresses consoles; do
  oc get "${r}.config.openshift.io" cluster -o yaml > "${CFG}/${r}.yaml"
done
oc get ingresscontrollers -n openshift-ingress-operator -o yaml > "${CFG}/ingresscontrollers.yaml"
oc get consolenotifications -o yaml                          > "${CFG}/consolenotifications.yaml"
oc get operatorhub cluster -o yaml                           > "${CFG}/operatorhub.yaml"
oc get kubeletconfigs -o yaml                                > "${CFG}/kubeletconfigs.yaml"
oc get machineconfigs \
  -o custom-columns='NAME:.metadata.name,ROLE:.metadata.labels.machineconfiguration\.openshift\.io/role,CONTROLS:.metadata.annotations.itsg33/controls' \
                                                             > "${CFG}/machineconfigs.txt"
oc get machineconfigpools                                    > "${CFG}/machineconfigpools.txt"

# Network isolation (AC-4, SC-4, SC-7)
oc get adminnetworkpolicies,baselineadminnetworkpolicies -o yaml > "${CFG}/admin-network-policies.yaml"
oc get clusteruserdefinednetworks,userdefinednetworks -A -o yaml > "${CFG}/user-defined-networks.yaml"
oc get ns -L itsg33/zone,k8s.ovn.org/primary-user-defined-network > "${CFG}/namespace-zones.txt"
```

If BGP route advertisement is used (AD-09 alternative), add `oc get routeadvertisements -o yaml`.

### 06-access

```bash
ACC="${OUT}/06-access"
oc get clusterrolebindings -o json \
  | jq -r '.items[] | select(.roleRef.name=="cluster-admin")
      | [.metadata.name, ([.subjects[]? | .kind + ":" + .name] | join(" "))] | @tsv' \
  > "${ACC}/cluster-admin-bindings.tsv"
oc get clusterrolebindings -o yaml                     > "${ACC}/clusterrolebindings.yaml"
oc get clusterrolebinding self-provisioners -o yaml    > "${ACC}/self-provisioners.yaml"
oc get groups -o yaml                                  > "${ACC}/groups.yaml"
oc get pods -A -o json \
  | jq -r '.items[] | [.metadata.namespace, .metadata.name, (.metadata.annotations["openshift.io/scc"] // "")]
      | select(.[2] != "restricted-v2") | @tsv' > "${ACC}/pods-not-restricted-v2.tsv"
```

The IdP account list, MFA enforcement, and joiner/mover/leaver records (AC-2, IA-2(1)) come from
the identity team; save their export here.

### 07-logging

```bash
oc get clusterlogforwarders.observability.openshift.io -A -o yaml > "${OUT}/07-logging/clusterlogforwarders.yaml"
oc get lokistacks -A -o yaml                                     > "${OUT}/07-logging/lokistacks.yaml"
oc get apiserver cluster -o jsonpath='{.spec.audit}{"\n"}'       > "${OUT}/07-logging/audit-profile.json"
```

Add a record from the SIEM team that audit and infrastructure logs from `ocp1` were received
throughout the period (for example a daily event count), with their query (AU-6, AU-9, AU-12).

### 08-integrity

```bash
FIO="${OUT}/08-integrity"
oc get fileintegrities -n openshift-file-integrity -o yaml           > "${FIO}/fileintegrities.yaml"
oc get fileintegritynodestatuses -n openshift-file-integrity -o yaml > "${FIO}/nodestatuses.yaml"
oc get configmaps -n openshift-file-integrity -l file-integrity.openshift.io/result-log -o yaml \
                                                                     > "${FIO}/aide-failure-logs.yaml"
oc get events -n openshift-file-integrity --field-selector reason=NodeIntegrityStatus \
                                                                     > "${FIO}/events.txt"
```

For each failure log, add the ticket that explains it (approved change or incident).

### 09-backup

```bash
oc get schedules.velero.io -n openshift-adp -o yaml > "${OUT}/09-backup/schedules.yaml"
oc get backups.velero.io -n openshift-adp -o json \
  | jq -r '["backup","phase","started","completed"],
      (.items[] | [.metadata.name, .status.phase, .status.startTimestamp, .status.completionTimestamp])
      | @csv' > "${OUT}/09-backup/backups.csv"
```

Add the latest restore test record (CP-4) and the etcd backup record ([Backup and restore](../06-sops/backup-and-restore.md#etcd-backup)).

### 10-change

```bash
CHG="${OUT}/10-change"
# Argo CD applications and sync history (the last 10 syncs per application by default)
oc get applications.argoproj.io -n openshift-gitops -o yaml > "${CHG}/argocd-applications.yaml"
oc get applications.argoproj.io -n openshift-gitops -o json \
  | jq -r '["application","id","revision","deployedAt"],
      (.items[] | .metadata.name as $a | .status.history[]? | [$a, .id, .revision, .deployedAt])
      | @csv' > "${CHG}/argocd-sync-history.csv"

# Git history of the configuration for the period
git -C "${REPO}" log --since="<period-start>" --until="<period-end>" --date=iso-strict \
  --format='%H%x09%ad%x09%an%x09%s' -- 04-gitops/ > "${CHG}/git-log.tsv"

# Operator install and update approvals
oc get installplans -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,CSV:.spec.clusterServiceVersionNames,APPROVED:.spec.approved,PHASE:.status.phase \
  > "${CHG}/installplans.txt"

# Platform updates
oc get clusterversion version -o json \
  | jq -r '["version","state","started","completed","verified","image"],
      (.status.history[] | [.version, .state, .startedTime, .completionTime, .verified, .image])
      | @csv' > "${CHG}/clusterversion-history.csv"
```

Add the pull request records (reviewer, approval, linked ticket) exported from the departmental
Git server and the list of change tickets closed in the period. Argo CD keeps a short history;
the Git log and the tickets are the complete record (CM-3).

### 11-poam

Export the POA&M rows open or closed in the period (columns as in `05-evidence/poam-example.csv`).

## Bundle index

Copy `05-evidence/evidence-bundle-index.md` to `${OUT}/README.md` and fill in the metadata, the
period, the people, and any artifact that is missing with the reason. The assessor reads this
file first.

## Integrity and signing

Before signing, check that no secret was captured. The read-only account cannot read Secrets,
but check anyway and review every match (references to Secrets by name are expected; values are
not):

```bash
grep -rIEn 'BEGIN [A-Z ]*PRIVATE KEY|clientSecret:|password:' "${OUT}"
```

The collector writes the manifest:

```bash
cd "${OUT}"
find . -type f ! -name 'SHA256SUMS*' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
```

The evidence custodian checks it and signs it with the custodian key:

```bash
sha256sum --check --strict --quiet SHA256SUMS
gpg --local-user <custodian-key-fingerprint> --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS
```

Then the custodian packs the bundle and records it in the register (bundle, date, archive
SHA-256, signer, storage location):

```bash
tar --create --file "evidence-${CLUSTER}-<YYYY-MM-DD>.tar" -C "evidence/${CLUSTER}" <YYYY-MM-DD>
sha256sum "evidence-${CLUSTER}-<YYYY-MM-DD>.tar"
```

**Verification** (assessor or custodian, with the custodian public key imported and its
fingerprint checked against the SSP):

```bash
tar --extract --file evidence-ocp1-<YYYY-MM-DD>.tar
cd <YYYY-MM-DD>
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum --check --strict --quiet SHA256SUMS
# No file added or removed after signing: prints nothing
find . -type f ! -name 'SHA256SUMS*' | sort | diff <(awk '{print $2}' SHA256SUMS | sort) -
```

## Handling as Protected B

A bundle describes the security configuration of a Protected B system (host names, addresses,
group names, settings, weaknesses). Treat every bundle as **Protected B**:

- Mark the bundle index and the archive name or label `PROTECTED B`.
- Store bundles only in the approved evidence store on the high side, encrypted at rest, with
  access limited to the custodian, the ISSO, the platform security lead, and named assessors
  (AC-3, AC-6); access is logged (AU-2).
- Do not attach bundles to email or tickets; refer to the bundle by name and archive SHA-256.
- Working copies on the admin host are removed after the custodian has signed and stored the
  bundle.

## Retention

Keep bundles, their signatures, and the register for the retention period of the departmental
information management schedule, and at least for the authorization period plus one assessment
cycle, so that the assessor can compare periods. The 90 raw result sets on the cluster and the
short histories in ACM and Argo CD are not retention; the bundles are. Dispose of expired
bundles through the departmental process for Protected B information and record it in the
register.

## Moving evidence off the high side

By default, evidence stays on the high side. Move something only where departmental policy
allows it, for example a summary for a low-side governance report, and then only the minimum:

1. **Approval.** The ISSO (and the system owner, if the policy requires) approves the request,
   naming the files and the destination, under a ticket.
2. **Minimize.** Prefer derived summaries (counts per status, POA&M IDs and states, control
   status) over raw exports. Never move raw ARF results, configuration exports, AIDE logs, or
   vulnerability details unless the destination is approved for them.
3. **Sanitize.** Remove or replace host names, IP addresses, cluster and domain names, user and
   group names, registry paths, certificate contents, and anything that maps a weakness to an
   asset. Search for leftovers:

   ```bash
   grep -rIEn '([0-9]{1,3}\.){3}[0-9]{1,3}|example\.gc\.ca|BEGIN CERTIFICATE|ocp1' <export-dir>
   ```

4. **Review.** A second person reviews the sanitized files against the original and confirms the
   classification of the result.
5. **Re-sign.** Create a new `SHA256SUMS` and custodian signature for the export; it is a new
   artifact, not the bundle.
6. **Transfer** through the approved process for that direction, and record it (what, who,
   approval, hashes) in the register and the transfer record.
