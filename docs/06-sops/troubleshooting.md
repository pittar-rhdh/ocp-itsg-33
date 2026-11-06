# Troubleshooting

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Symptom → checks → fix for faults specific to this design (bare-metal IPI, air-gapped, GitOps).
Configuration fixes go through Git; only diagnosis and emergency actions are done by hand. General
guidance: Red Hat OpenShift 4.22 *Support*.

## Diagnose a platform fault

| | |
|---|---|
| **Purpose** | Find the cause of an install, node, image, certificate, operator, or GitOps fault and choose a fix, without weakening a security setting |
| **When** | On demand, from an incident or ticket |
| **Roles** | Performs: platform operator. Approves fix: change board (emergency change if the service is down). Informed: security officer if a security setting is involved |
| **Prerequisites** | A ticket; IdP login with cluster-admin ([break-glass](access-management.md#break-glass-use-and-review) only if the IdP or API is down) |
| **Controls** | CM-3, SI-2, MA-2, IR-4 |

### Procedure

Use the section for the symptom; save every command's output in the ticket directory.

#### Bootstrap, Ironic, and BMC failures (installation)

```bash
openshift-install-fips wait-for bootstrap-complete --dir "${INSTALL_DIR}" --log-level debug
openshift-install-fips gather bootstrap --dir "${INSTALL_DIR}"
sudo virsh list --all; sudo virsh console <bootstrap-vm>   # VM running? shows its IP; exit Ctrl+]
ssh core@<bootstrap-ip> 'journalctl -b -u bootkube.service --no-pager | tail -100; sudo podman ps'
ssh core@<bootstrap-ip> 'sudo podman logs ironic 2>&1 | tail -200'
```

| Symptom | Check | Fix |
|---|---|---|
| Host stays `registering`; credential or TLS errors in Ironic log | `curl --cacert ~/ocp-install/bmc-ca.crt -u '<user>' https://<bmc>/redfish/v1/Systems/1`; `openssl s_client -connect <bmc>:443 -CAfile ~/ocp-install/bmc-ca.crt -verify_return_error </dev/null` | Correct BMC address or system ID ([BMC checks](../03-cluster-install/prerequisites.md#bmcs)); put the issuing CA in `bmcVerifyCA`. Never disable verification |
| Powers on but never boots virtual media | BMC event log; firmware; BMC reach to provisioning HTTP ports 6180/6183 | Firmware to Red Hat's minimum; Dell: `idrac-virtualmedia://`; open the firewall path |
| `No disks satisfied root device hints` | Inspection data in Ironic log | Use a by-path or WWN hint; restart from a new install directory |
| Bootstrap pulls fail (`x509`, `manifest unknown`) | Ironic and bootkube logs | See image pull below; check `imageDigestSources` and `additionalTrustBundle` |

On a running cluster: `oc get bmh -A`, `oc describe bmh <host> -n openshift-machine-api`,
`oc logs -n openshift-machine-api deploy/metal3 --all-containers --since=1h`.

#### Image pull and mirror errors

```bash
oc get events -n <ns> --field-selector reason=Failed | grep -i -E 'pull|image'
oc get imagedigestmirrorsets,imagetagmirrorsets; oc get image.config.openshift.io cluster -o jsonpath='{.spec}{"\n"}'
oc debug --quiet node/<node> -- chroot /host cat /etc/containers/registries.conf
oc debug --quiet node/<node> -- chroot /host crictl pull <source-image>@sha256:<digest>
oc image info -a ~/.config/ocp-registry/cluster-pull-secret.json registry.example.gc.ca:8443/<repo>@sha256:<digest>
```

| Symptom | Likely cause | Fix |
|---|---|---|
| `manifest unknown` from the mirror | Not mirrored, or an earlier delta not imported | Check the import log; add to the ImageSetConfiguration; import in order ([content import](content-import.md)) |
| Pull goes to `quay.io` / `registry.redhat.io` and times out | No mirror rule, or a tag pull with only an IDMS (tags need an ITMS) | Apply the matching import's `cluster-resources` through Git |
| `unauthorized` | Pull secret rotated or wrong robot | [Registry robot token rotation](access-management.md#registry-robot-token-rotation) |
| `x509: certificate signed by unknown authority` | Registry CA not trusted | See certificate trust below |
| `image ... is not allowed` | `allowedRegistries` lacks the source registry (keep `quay.io`, `registry.redhat.io`) or the mirror | Fix `04-gitops/components/image-policy/image.yaml` by pull request |
| Many nodes fail at once | Mirror registry down or full | [Mirror registry troubleshooting](../02-high-side/mirror-registry.md#troubleshooting) |

#### Certificate trust problems

```bash
openssl s_client -connect <host>:<port> -showcerts </dev/null | openssl x509 -noout -subject -issuer -dates
oc get proxy cluster -o jsonpath='{.spec.trustedCA.name}{"\n"}'
oc get configmap user-ca-bundle -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' \
  | openssl crl2pkcs7 -nocrl -certfile /dev/stdin | openssl pkcs7 -print_certs -noout | grep subject
```

Add a new issuing CA to the cluster trust bundle **before** deploying certificates it signs (registry CAs
may instead use `additionalTrustedCA` on `image.config`). Expiry: [certificate rotation](certificate-rotation.md).

#### Degraded MachineConfigPool

```bash
oc get mcp; oc describe mcp <pool> | grep -A5 -E 'Degraded|Message'
oc get nodes -o custom-columns='NODE:.metadata.name,STATE:.metadata.annotations.machineconfiguration\.openshift\.io/state,REASON:.metadata.annotations.machineconfiguration\.openshift\.io/reason'
P=$(oc get pods -n openshift-machine-config-operator -l k8s-app=machine-config-daemon \
  --field-selector spec.nodeName=<node> -o name)
oc logs -n openshift-machine-config-operator "${P}" -c machine-config-daemon --tail=200
```

| Symptom | Fix |
|---|---|
| Drain stuck (`error when evicting pods`) | Find the PodDisruptionBudget (`oc get pdb -A`); agree with the owner to scale or move the workload |
| `RenderDegraded` or content mismatch | Revert the MachineConfig, KubeletConfig, or remediation in Git; don't edit node files or delete `rendered-*` |
| Node never returns after reboot | BMC console; LUKS/TPM unlock failure after a firmware or TPM change means reprovisioning ([node management](node-management.md)) |

#### Catalog sources and operator installs

```bash
oc get catalogsource -n openshift-marketplace \
  -o custom-columns=NAME:.metadata.name,STATE:.status.connectionState.lastObservedState
oc get pods,jobs -n openshift-marketplace; oc get packagemanifests -n openshift-marketplace | grep <package>
oc get subscription <sub> -n <ns> -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
oc get installplan -n <ns> -o yaml | grep -A3 -E 'phase|message'
```

Catalog pod `CrashLoopBackOff`/`ImagePullBackOff`: image pull problem (above). Package or channel
missing: filtered out by the ImageSetConfiguration. Install plan fails to unpack: a bundle or related
image not mirrored. Plan awaiting approval is not a fault ([Approving install plans](../04-itsg33-configuration/operators.md#approving-install-plans)).

#### Argo CD sync errors

```bash
oc get applications.argoproj.io -n openshift-gitops
oc get application <app> -n openshift-gitops -o jsonpath='{.status.operationState.message}{"\n"}'
oc get application <app> -n openshift-gitops -o json \
  | jq -r '.status.resources[] | select(.status!="Synced" or .health.status=="Degraded") | [.kind,.namespace,.name,.status,.health.message] | @tsv'
```

| Message contains | Cause | Fix |
|---|---|---|
| `conflict` with another field manager | An operator or manual `oc edit` owns the field | Remove the field from Git if the operator owns it; otherwise undo the manual change |
| `no matches for kind` | CRD not installed yet (install plan pending) | Approve the install plan; sync retries |
| `forbidden` | Binding `itsg33-gitops-cluster-admin` missing | Re-apply `04-gitops/bootstrap` |
| `not permitted in project` | Outside the AppProject | Fix the manifest or AppProject by pull request |
| `authentication required` / `x509` on the repository | Repo token expired or Git CA changed | Update the repository Secret or `argocd-tls-certs-cm` ([GitOps bootstrap](../04-itsg33-configuration/gitops-bootstrap.md)) |

Resources removed from Git stay `OutOfSync` (pruning off, AD-22): delete them by hand under the ticket.

#### Expired kubelet certificates and pending CSRs

Nodes `NotReady` with pending CSRs after a long shutdown; the machine approver normally handles them
(Red Hat: *Backup and restore*, "Recovering from expired control plane certificates"):

```bash
oc get csr -o json | jq -r '.items[] | select(.status=={}) | [.metadata.name,.spec.signerName,.spec.username] | @tsv'
oc describe csr <csr>                      # requestor: node-bootstrapper or system:node:<known node>
oc adm certificate approve <csr>           # one by one, known nodes only
```

### Verification

Symptom gone; `oc get co` shows nothing degraded; Argo CD applications `Synced`.

### Rollback

Revert the Git change or emergency change.

### Records

Ticket with outputs, cause, fix, and the pull request or emergency change number.

## Collect must-gather on the high side

| | |
|---|---|
| **Purpose** | Collect diagnostics for Red Hat support and release them only after review. Treat must-gather (config, logs, optional audit logs) as **Protected B** until reviewed |
| **When** | A support case needs it |
| **Roles** | Collects: platform operator. Reviews/redacts: second platform operator. Approves release: security officer and information owner. Transfers: transfer team (AD-15) |
| **Prerequisites** | Support case number (opened from the low side). The must-gather image is in the release payload, so already mirrored; operator-specific images (ACM, Logging, OADP, Compliance) only if mirrored via `additionalImages` |
| **Controls** | MA-4, SA-9, MP-5, AC-21, IR-6 |

### Procedure

1. Resolve the payload's must-gather image (disconnected clusters must pass `--image`) and collect
   as narrowly as support allows:

   ```bash
   MG=$(oc adm release info -a ~/.config/ocp-registry/cluster-pull-secret.json \
     registry.example.gc.ca:8443/mirror/openshift/release-images@sha256:<release-digest> --image-for=must-gather)
   C=<case-number>; umask 077
   oc adm must-gather --image="${MG}" --dest-dir="mg-${C}"
   # Only if support asks for audit logs (large; contains user names and request details):
   oc adm must-gather --image="${MG}" --dest-dir="mg-${C}-audit" -- /usr/bin/gather_audit_logs
   # Narrower: one namespace
   oc adm must-gather --image="${MG}" --dest-dir="mg-${C}-ns" -- oc adm inspect ns/<namespace>
   ```

2. The reviewer removes or masks keys, tokens, and Protected B data (tenant names, hostnames, user
   names, IPs as the department decides), then packages and checksums the result:

   ```bash
   grep -rIl -E 'BEGIN [A-Z ]*PRIVATE KEY|password|token|secret' "mg-${C}" > review-hits.txt
   # ... review every hit and redact, then:
   tar -czf "must-gather-${C}-$(date -u +%Y%m%d).tar.gz" "mg-${C}"
   sha256sum must-gather-*.tar.gz > SHA256SUMS
   ```

3. After release approval, hand over as an outbound transfer with its own record; then delete local
   copies and any leftover `openshift-must-gather-*` namespaces.

### Verification

SHA-256 matches on the low side; the support case shows the upload.

### Rollback

Not applicable. Release of unreviewed data is a security or privacy incident (IR-6).

### Records

Case number, what was collected, review notes and redactions, release approval, outbound transfer
record, deletion date.
