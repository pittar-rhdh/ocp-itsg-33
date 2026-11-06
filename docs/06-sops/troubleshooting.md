# Troubleshooting

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Symptom → checks → fix for the faults most specific to this design (bare-metal IPI, air-gapped,
GitOps). Fixes to configuration go through Git; only diagnosis and emergency actions are done by
hand. Red Hat's general troubleshooting is in OpenShift 4.22 *Support*.

## Diagnose a platform fault

### Purpose and scope

Find the cause of an installation, node, image, certificate, operator, or GitOps fault and choose
a fix, without weakening a security setting to make the symptom go away.

### Roles

Performs: platform operator. Approves the fix: change board (emergency change if the service is
down). Informed: security officer when a security setting is involved.

### Prerequisites

A ticket. IdP login with cluster-admin (break-glass only if the IdP or API is down, see
[Break-glass](access-management.md#break-glass-use-and-review)).

### Procedure

Work through the section for the symptom. Save every command's output in the ticket directory.

#### Bootstrap, Ironic, and BMC failures (installation)

```bash
openshift-install-fips wait-for bootstrap-complete --dir "${INSTALL_DIR}" --log-level debug
openshift-install-fips gather bootstrap --dir "${INSTALL_DIR}"        # log bundle for analysis
sudo virsh list --all                                                  # <cluster>-<id>-bootstrap running?
sudo virsh console <bootstrap-vm>                                      # shows its IP; leave with Ctrl+]
ssh core@<bootstrap-ip> 'journalctl -b -u bootkube.service --no-pager | tail -100; sudo podman ps'
ssh core@<bootstrap-ip> 'sudo podman logs ironic 2>&1 | tail -200'
```

| Symptom | Check | Fix |
|---|---|---|
| Host stays in `registering`; credentials or TLS errors in the Ironic log | `curl --cacert ~/ocp-install/bmc-ca.crt -u '<user>' https://<bmc>/redfish/v1/Systems/1` from the provisioner; `openssl s_client -connect <bmc>:443 -CAfile ~/ocp-install/bmc-ca.crt -verify_return_error </dev/null` | Correct the BMC address or system ID ([BMC checks](../03-cluster-install/prerequisites.md#bmcs)); put the issuing CA in `bmcVerifyCA`. Never disable verification |
| Node powers on but never boots the virtual media | BMC event log; firmware version; can the BMC reach the provisioning HTTP ports (6180/6183) | Update firmware to Red Hat's minimum for virtual media; Dell: `idrac-virtualmedia://` and virtual media attach mode; open the firewall path |
| `No disks satisfied root device hints` | Inspection data in the Ironic log | Use a by-path or WWN hint; start again from a new installation directory |
| Bootstrap pulls fail | Ironic and bootkube logs show `x509` or `manifest unknown` | See image pull below; the install-config `imageDigestSources` and `additionalTrustBundle` |

On a running cluster, the same Ironic services run in the `metal3` pod:
`oc get bmh -A`, `oc describe bmh <host> -n openshift-machine-api`,
`oc logs -n openshift-machine-api deploy/metal3 --all-containers --since=1h`.

#### Image pull and mirror errors

```bash
oc get events -n <ns> --field-selector reason=Failed | grep -i -E 'pull|image'
oc get imagedigestmirrorsets,imagetagmirrorsets
oc get image.config.openshift.io cluster -o jsonpath='{.spec}{"\n"}'          # allowedRegistries, additionalTrustedCA
oc debug --quiet node/<node> -- chroot /host cat /etc/containers/registries.conf
oc debug --quiet node/<node> -- chroot /host crictl pull <source-image>@sha256:<digest>
oc image info -a ~/.config/ocp-registry/cluster-pull-secret.json registry.example.gc.ca:8443/<repo>@sha256:<digest>
```

| Symptom | Likely cause | Fix |
|---|---|---|
| `manifest unknown` from the mirror | Image not mirrored, or an earlier delta not imported | Check the import log; add the image to the ImageSetConfiguration and import in order ([content import](content-import.md)) |
| Pull goes to `quay.io` or `registry.redhat.io` and times out | No mirror rule for that source, or a tag pull with only an IDMS (IDMS applies to digests; tags need an ITMS) | Apply the `cluster-resources` from the matching import through Git |
| `unauthorized` | Pull secret rotated or wrong robot | [Registry robot token rotation](access-management.md#registry-robot-token-rotation) |
| `x509: certificate signed by unknown authority` | Registry CA not trusted | See certificate trust below |
| `image ... is not allowed` / blocked registry | `allowedRegistries` lacks the **source** registry (`quay.io`, `registry.redhat.io` must stay listed) or the mirror | Fix `04-gitops/components/image-policy/image.yaml` by pull request |
| Many nodes fail at once | Mirror registry down or full | [Mirror registry troubleshooting](../02-high-side/mirror-registry.md#troubleshooting) |

#### Certificate trust problems

```bash
openssl s_client -connect <host>:<port> -showcerts </dev/null | openssl x509 -noout -subject -issuer -dates
oc get proxy cluster -o jsonpath='{.spec.trustedCA.name}{"\n"}'     # cluster trust bundle ConfigMap
oc get configmap user-ca-bundle -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' \
  | openssl crl2pkcs7 -nocrl -certfile /dev/stdin | openssl pkcs7 -print_certs -noout | grep subject
```

The issuing CA must be in the cluster trust bundle **before** a certificate signed by a new CA is
deployed. For the registry, a per-registry CA can also be added with `additionalTrustedCA` on
`image.config.openshift.io/cluster`. Expiring platform certificates: see
[certificate rotation](certificate-rotation.md).

#### Degraded MachineConfigPool

```bash
oc get mcp
oc describe mcp <pool> | grep -A5 -E 'Degraded|Message'
oc get nodes -o custom-columns='NODE:.metadata.name,STATE:.metadata.annotations.machineconfiguration\.openshift\.io/state,REASON:.metadata.annotations.machineconfiguration\.openshift\.io/reason'
P=$(oc get pods -n openshift-machine-config-operator -l k8s-app=machine-config-daemon \
  --field-selector spec.nodeName=<node> -o name)
oc logs -n openshift-machine-config-operator "${P}" -c machine-config-daemon --tail=200
```

| Symptom | Fix |
|---|---|
| Drain stuck (`error when evicting pods`) | Find the blocking PodDisruptionBudget (`oc get pdb -A`); agree with the owner to scale or move the workload |
| `RenderDegraded` or content mismatch | Revert the MachineConfig, KubeletConfig, or remediation in Git; don't edit node files or delete `rendered-*` configs |
| Node never returns after reboot | BMC console; a LUKS/TPM unlock failure after a firmware or TPM change needs the node to be reprovisioned ([node management](node-management.md)) |

#### Catalog sources and operator installs

```bash
oc get catalogsource -n openshift-marketplace \
  -o custom-columns=NAME:.metadata.name,STATE:.status.connectionState.lastObservedState
oc get pods -n openshift-marketplace
oc get packagemanifests -n openshift-marketplace | grep <package>
oc get subscription <sub> -n <ns> -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
oc get installplan -n <ns> -o yaml | grep -A3 -E 'phase|message'
oc get jobs -n openshift-marketplace                                   # bundle unpack jobs
```

A catalog pod in `CrashLoopBackOff` or `ImagePullBackOff` is usually an image pull problem (above).
A missing package or channel means the ImageSetConfiguration filtered it out. An install plan that
fails to unpack usually means a bundle or related image was not mirrored. A plan waiting for
approval is not a fault ([Approving install plans](../04-itsg33-configuration/operators.md#approving-install-plans)).

#### Argo CD sync errors

```bash
oc get applications.argoproj.io -n openshift-gitops
oc get application <app> -n openshift-gitops -o jsonpath='{.status.operationState.message}{"\n"}'
oc get application <app> -n openshift-gitops -o json \
  | jq -r '.status.resources[] | select(.status!="Synced" or .health.status=="Degraded") | [.kind,.namespace,.name,.status,.health.message] | @tsv'
```

| Message contains | Cause | Fix |
|---|---|---|
| `conflict` with another field manager | Server-side apply: an operator or a manual `oc edit` owns the field | Remove the field from Git if the operator owns it; otherwise undo the manual change |
| `no matches for kind` / `could not find the requested resource` | CRD not installed yet (install plan pending) | Approve the install plan; the sync retries |
| `forbidden` | Controller binding `itsg33-gitops-cluster-admin` missing | Re-apply `04-gitops/bootstrap` |
| `not permitted in project` | Resource or destination outside the AppProject | Fix the manifest or the AppProject by pull request |
| `authentication required` / `x509` on the repository | Repository token expired or Git CA changed | Update the repository Secret or `argocd-tls-certs-cm` ([GitOps bootstrap](../04-itsg33-configuration/gitops-bootstrap.md)) |

Resources removed from Git stay `OutOfSync` because pruning is off for configuration (AD-22):
delete them by hand under the change ticket.

#### Expired kubelet certificates and pending CSRs

After a node or the cluster was off for a long time, nodes can stay `NotReady` with pending
CSRs. On IPI the machine approver normally approves them; check before approving by hand
(Red Hat: *Backup and restore*, "Recovering from expired control plane certificates"):

```bash
oc get csr -o json | jq -r '.items[] | select(.status=={}) | [.metadata.name,.spec.signerName,.spec.username] | @tsv'
oc describe csr <csr>                      # requestor is node-bootstrapper or system:node:<known node>
oc adm certificate approve <csr>           # one by one, only for known nodes
```

### Verification

The symptom is gone, `oc get co` shows no degraded operator, and the Argo CD applications are
`Synced`.

### Rollback

Revert the Git change or emergency change that was made.

### Records and evidence

Ticket with outputs, cause, fix, and the pull request or emergency change number.

### Related controls

CM-3, SI-2, MA-2, IR-4.

## Collect must-gather on the high side

### Purpose and scope

Collect diagnostic data for Red Hat support, and release it from the air-gapped environment only
after review. Must-gather contains cluster configuration, logs, and (if requested) audit logs:
treat it as **Protected B** until reviewed.

### Roles

Collects: platform operator. Reviews and redacts: a second platform operator. Approves release:
security officer and the information owner. Transfers: the cross-domain/transfer team (AD-15).

### Prerequisites

- A Red Hat support case number (opened from the low side).
- The must-gather image is part of the release payload, so it is already in the mirror. Images for
  operator-specific must-gather (for example ACM, Logging, OADP, Compliance) are only available if
  they were mirrored with `additionalImages` in the ImageSetConfiguration.

### Procedure

1. Find the payload's must-gather image. Red Hat: in a disconnected environment, pass `--image` and
   point to the payload image. Resolve it from the mirrored release (the cluster pulls it through
   the IDMS):

   ```bash
   MG=$(oc adm release info -a ~/.config/ocp-registry/cluster-pull-secret.json \
     registry.example.gc.ca:8443/mirror/openshift/release-images@sha256:<release-digest> --image-for=must-gather)
   ```

2. Collect, scoped as narrowly as support allows:

   ```bash
   C=<case-number>; umask 077
   oc adm must-gather --image="${MG}" --dest-dir="mg-${C}"
   # Only if support asks for audit logs (large; contains user names and request details):
   oc adm must-gather --image="${MG}" --dest-dir="mg-${C}-audit" -- /usr/bin/gather_audit_logs
   # Narrower alternative: one namespace or operator
   oc adm must-gather --image="${MG}" --dest-dir="mg-${C}-ns" -- oc adm inspect ns/<namespace>
   ```

3. Review and redact. The reviewer searches for keys, tokens, and Protected B data (tenant names,
   hostnames, user names, IP addresses as the department decides) and removes or masks them:

   ```bash
   grep -rIl -E 'BEGIN [A-Z ]*PRIVATE KEY|password|token|secret' "mg-${C}" > review-hits.txt
   ```

4. Package and checksum, then hand over to the transfer process as an outbound transfer with its
   own record:

   ```bash
   tar -czf "must-gather-${C}-$(date -u +%Y%m%d).tar.gz" "mg-${C}"
   sha256sum must-gather-*.tar.gz > SHA256SUMS
   ```

5. After release, delete the local copies and the `openshift-must-gather-*` namespaces if any were
   left behind (`oc get ns | grep must-gather`).

### Verification

The archive's SHA-256 on the low side matches; the support case shows the upload.

### Rollback

Not applicable. If unreviewed data was released, treat it as a privacy or security incident (IR-6).

### Records and evidence

Case number, what was collected, review notes and redactions, the release approval, the outbound
transfer record, and the deletion date.

### Related controls

MA-4, SA-9, MP-5, AC-21, IR-6.
