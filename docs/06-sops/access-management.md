# Access Management

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Human access to the platform comes from IdP group membership (`gc-sso`, AD-03). Cluster roles are
bound to groups in Git (`04-gitops/components/rbac/cluster-role-bindings.yaml`): `ocp-platform-admins`
→ `cluster-admin`, `ocp-security-auditors` → `cluster-reader`. Nobody is bound to a role as an
individual. The background is in [AC-2](../04-itsg33-configuration/controls/ac-access-control.md#ac-2-account-management)
and [AC-6](../04-itsg33-configuration/controls/ac-access-control.md#ac-6-least-privilege).

| SOP | When |
|---|---|
| [Onboarding and offboarding](#user-onboarding-and-offboarding) | Joiner, mover, leaver tickets |
| [Quarterly access review](#quarterly-access-review) | Every quarter, and after an incident |
| [Break-glass use and review](#break-glass-use-and-review) | Only when IdP login is impossible |
| [Registry robot token rotation](#registry-robot-token-rotation) | Departmental schedule, and when someone with access leaves |

## User onboarding and offboarding

### Purpose and scope

Grant, change, or remove a person's access to OpenShift, Argo CD, and RHACS. Access is changed in
the IdP; this SOP confirms the result on the cluster and removes what the IdP can't (live sessions).

### Roles

| Role | Who |
|---|---|
| Requests | The person's manager, through the access request ticket |
| Approves | System owner (platform roles); security officer for `ocp-security-auditors` |
| Performs | IdP administrator (group membership); platform operator (cluster checks, session removal) |

### Prerequisites

An approved ticket naming the user, the IdP group, and the reason. A new group (a new role) is not
part of this SOP: it is a pull request to the `rbac` component.

### Procedure

**Onboarding or change**

1. The IdP administrator adds the user to the approved group.
2. The user logs in once (`oc login --web` or the console). With the `groups` claim, the OAuth
   server records the group membership in OpenShift at login.
3. Confirm the result:

   ```bash
   U=<preferred_username>
   oc get user "${U}" -o jsonpath='{.identities}{"\n"}'          # gc-sso:<subject>
   oc get groups -o json | jq -r --arg u "${U}" '.items[] | select(.users // [] | index($u)) | .metadata.name'
   oc auth can-i get secrets -n openshift-config --as="${U}" --as-group=ocp-security-auditors   # auditors: no
   oc auth can-i '*' '*' --all-namespaces --as="${U}" --as-group=ocp-platform-admins            # admins: yes
   ```

**Offboarding (leaver, or removal from a role)**

1. The IdP administrator removes the user from the group, or disables the account. New logins stop.
2. Existing OpenShift sessions stay valid until the token expires (8 hours maximum, 15 minutes
   idle; [AC-12](../04-itsg33-configuration/controls/ac-access-control.md#ac-11-session-lock-ac-12-session-termination)),
   and the OpenShift group membership is only refreshed at the next login. Remove both now:

   ```bash
   U=<preferred_username>
   # Live OAuth access tokens of the user (token names are hashes, not the tokens)
   oc get oauthaccesstokens -o json \
     | jq -r --arg u "${U}" '.items[] | select(.userName==$u) | .metadata.name' \
     | xargs -r oc delete oauthaccesstoken
   # Group membership recorded at the last login
   for g in $(oc get groups -o json | jq -r --arg u "${U}" '.items[] | select(.users // [] | index($u)) | .metadata.name'); do
     oc adm groups remove-users "${g}" "${U}"
   done
   # Leaver only: identity and user objects
   oc delete identity "$(oc get user "${U}" -o jsonpath='{.identities[0]}')"
   oc delete user "${U}"
   ```

3. Check that no binding names the user directly (there should never be one):

   ```bash
   oc get clusterrolebindings,rolebindings -A -o json \
     | jq -r --arg u "${U}" '.items[] | select(.subjects[]? | .kind=="User" and .name==$u) | "\(.metadata.namespace // "-")/\(.metadata.name)"'
   ```

4. Leaver with Argo CD or RHACS access: their sessions are separate (see the
   [quarterly review](#quarterly-access-review)). If the person held vault, BMC, registry, or
   break-glass custody, rotate those credentials ([Registry robot token rotation](#registry-robot-token-rotation),
   [BMC credential rotation](node-management.md#bmc-credential-rotation)).

### Verification

`oc get oauthaccesstokens -o json | jq --arg u "${U}" '[.items[] | select(.userName==$u)] | length'`
returns `0`; `oc get user "${U}"` returns `NotFound` (leaver); the API audit log shows no request
by the user after the removal time.

### Rollback

Onboarding: remove the group membership in the IdP and run the offboarding steps. Offboarding:
re-approve and re-add the user in the IdP; the user and identity objects are recreated at login.

### Records and evidence

The ticket with approval, the commands' output, and the time sessions were removed. The API
audit log records the `delete` events (AC-2(4)).

### Related controls

AC-2, AC-2(3), AC-2(4), AC-6, AC-12, IA-4, PS-4, PS-5.

## Quarterly access review

### Purpose and scope

Show that every privileged path into the platform is still needed and approved: cluster roles,
SCCs, service accounts, Argo CD, RHACS, the registry, and the break-glass credential.

### Roles

Performs: platform operator (collects). Reviews and signs: system owner and security officer
(not the person who collected the data, AC-5).

### Prerequisites

`cluster-reader` or higher. The previous review's record, for comparison.

### Procedure

1. Collect cluster data into a dated directory:

   ```bash
   D=~/access-review/$(date -u +%Y%m%d); mkdir -p "${D}"; cd "${D}"
   oc get groups -o custom-columns=GROUP:.metadata.name,USERS:.users > groups.txt
   oc get users -o custom-columns=USER:.metadata.name,IDENTITIES:.identities > users.txt
   # Who holds cluster-admin
   oc get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin")
     | .metadata.name + ": " + ([.subjects[]? | .kind+"/"+(.namespace // "")+"/"+.name] | join(", "))' > cluster-admin.txt
   # Users and groups bound to any cluster role outside the platform defaults
   oc get clusterrolebindings -o json | jq -r '.items[] | .metadata.name as $b | .roleRef.name as $r
     | .subjects[]? | select(.kind=="User" or (.kind=="Group" and (.name|startswith("system:")|not)))
     | [$b,$r,.kind,.name] | @tsv' > crb-humans.tsv
   # Service accounts outside openshift-* with admin, edit, or cluster-admin
   oc get clusterrolebindings,rolebindings -A -o json | jq -r '.items[]
     | select(.roleRef.name|test("^(cluster-admin|admin|edit)$")) | . as $b | .subjects[]?
     | select(.kind=="ServiceAccount" and ((.namespace // "")|startswith("openshift")|not))
     | [$b.kind,($b.metadata.namespace // "-"),$b.metadata.name,$b.roleRef.name,.namespace,.name] | @tsv' > sa-elevated.tsv
   # Privileged SCCs: who may use them, and which pods run with a non-default SCC
   oc adm policy who-can use securitycontextconstraints privileged > scc-privileged-who-can.txt
   oc get pods -A -o json | jq -r '.items[] | [.metadata.namespace,.metadata.name,.metadata.annotations["openshift.io/scc"]]
     | @tsv' | grep -v -E 'restricted-v2$' > pods-non-default-scc.tsv
   sha256sum * > SHA256SUMS
   ```

2. Argo CD: confirm the RBAC in Git is unchanged and only the two groups have roles
   ([Argo CD access and privileges](../04-itsg33-configuration/gitops-bootstrap.md#argo-cd-access-and-privileges)):

   ```bash
   oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.rbac}{"\n"}' > argocd-rbac.json
   oc get clusterrolebinding itsg33-gitops-cluster-admin -o yaml > argocd-controller-crb.yaml
   ```

3. RHACS: in the portal, **Platform Configuration → Access Control**, export the auth providers,
   their group-to-role mappings, and the API tokens list. Revoke API tokens nobody can justify.
4. Mirror registry: in the Quay UI, list organization `mirror` members, robots, and teams. Only
   `importer`, `cluster_pull`, and the break-glass administrator should exist (AD-21).
5. Vault: list who can open the break-glass entries (installer kubeconfig, `core` SSH key, registry
   administrator, BMC credentials) and compare with the approved custodians.
6. Compare every list with the previous review and the approved access list. Raise a ticket for
   each unexplained entry; remove access through the normal process (Git pull request, IdP, or
   offboarding).

### Verification

Every entry is approved or has a removal ticket; the reviewers sign the record.

### Rollback

Not applicable (read-only collection).

### Records and evidence

The review directory with `SHA256SUMS`, the signed review record, and the tickets raised.

### Related controls

AC-2, AC-5, AC-6(5), AC-6(7), AU-6.

## Break-glass use and review

### Purpose and scope

Use the sealed installer kubeconfig (`system:admin`, client certificate) only when IdP login is not
possible, for example IdP or OAuth outage, or an etcd restore. It bypasses the IdP and MFA, so its
use is dual-controlled and always reviewed.

### Roles

| Role | Who |
|---|---|
| Authorizes | System owner or delegate (on-call manager), recorded in the incident ticket |
| Unseals | Two custodians together (dual control) |
| Uses | A platform operator, with the second custodian watching |
| Reviews | Security officer, within 2 working days |

### Prerequisites

An incident ticket stating why IdP access is not possible, and the authorization.

### Procedure

1. The two custodians open the vault entry together and copy the kubeconfig to the admin host
   (mode 0600, a session-specific path). Record the start time.
2. Use it only for the authorized task, with a command log:

   ```bash
   script -q ~/breakglass/$(date -u +%Y%m%dT%H%M%SZ)-session.log
   export KUBECONFIG=~/breakglass/kubeconfig
   oc whoami          # system:admin
   # ... authorized actions only ...
   exit
   ```

3. When done, remove the copy (`shred -u ~/breakglass/kubeconfig`), confirm the vault entry is
   resealed, and record the end time.
4. Review: export every request made with the credential during the window (also available in the
   SIEM, which is the authoritative copy):

   ```bash
   for n in $(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[*].metadata.name}'); do
     oc adm node-logs "${n}" --path=kube-apiserver/audit.log
   done | jq -rR 'fromjson? | select(.user.username=="system:admin")
         | [.requestReceivedTimestamp,.verb,.objectRef.resource,.objectRef.namespace,.objectRef.name] | @tsv' \
     > breakglass-audit.tsv
   ```

5. The reviewer compares the actions with the authorization and the session log, and signs.

**Rotating the credential.** The Red Hat 4.22 documentation reviewed for this guide gives no
procedure to revoke or regenerate the installer `system:admin` kubeconfig, and the
`oc adm ocp-certificates` commands do not list it. Until a supported procedure is confirmed with
Red Hat support, treat the credential as non-revocable: protect it by custody (dual control, vault
audit), detect its use (SIEM alert on `user.username == "system:admin"` outside approved windows,
AU-6), and if it may have been copied or exposed, open a high-severity incident and a Red Hat
support case for the supported replacement procedure before closing it.

### Verification

The vault shows the entry resealed; no `system:admin` requests after the recorded end time.

### Rollback

Not applicable.

### Records and evidence

Incident ticket, authorization, vault access log, session log, `breakglass-audit.tsv`, signed review.

### Related controls

AC-2, AC-6(9), AC-17, AU-6, AU-9, IA-2, IR-4.

## Registry robot token rotation

### Purpose and scope

Rotate the mirror registry robot tokens (`importer`, `cluster_pull`). The steps are on
[Mirror registry → Rotate robot tokens](../02-high-side/mirror-registry.md#rotate-robot-tokens);
this SOP adds the cluster side for `cluster_pull`.

### Roles

Performs: registry administrator and platform operator. Approves: change ticket.

### Prerequisites

A maintenance window with no upgrade, node scaling, or operator install in progress: regenerating
`cluster_pull` invalidates the old token at once, so new image pulls fail until the cluster pull
secret is updated. Images already on the nodes keep running.

### Procedure

1. Regenerate the token and rewrite `~/.config/ocp-registry/cluster-pull-secret.json` with
   `podman login`, as on the mirror registry page (`importer`: stop here).
2. Replace the global pull secret. The file holds only the mirror registry credentials, as at
   install time (no Red Hat credentials, AD-08):

   ```bash
   oc set data secret/pull-secret -n openshift-config \
     --from-file=.dockerconfigjson="${HOME}/.config/ocp-registry/cluster-pull-secret.json"
   oc get mcp -w                       # wait until every pool is UPDATED=True
   ```

3. Test a pull with the new credentials on one node of each pool:

   ```bash
   oc debug --quiet node/<node> -- chroot /host podman pull --authfile /var/lib/kubelet/config.json \
     registry.example.gc.ca:8443/mirror/openshift/release-images@sha256:<release-digest>
   ```

### Verification

The test pulls succeed; no new `ErrImagePull` events: `oc get events -A --field-selector reason=Failed | grep -i pull`.

### Rollback

There is no old token to return to. If pulls fail, test the credential file from the admin host
(`oc image info -a ~/.config/ocp-registry/cluster-pull-secret.json <release-image>@sha256:<digest>`),
regenerate it if needed, and repeat step 2.

### Records and evidence

Change ticket, rotation time, SHA-256 of the new credential file (never its content), test output.

### Related controls

IA-5, IA-5(1), AC-2, CM-11.
