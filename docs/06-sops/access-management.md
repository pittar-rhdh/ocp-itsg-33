# Access Management

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Human access comes from IdP group membership (`gc-sso`, AD-03), bound to roles in Git
(`04-gitops/components/rbac/cluster-role-bindings.yaml`): `ocp-platform-admins` → `cluster-admin`,
`ocp-security-auditors` → `cluster-reader`. No individual bindings. Background:
[AC-2](../04-itsg33-configuration/controls/ac-access-control.md#ac-2-account-management),
[AC-6](../04-itsg33-configuration/controls/ac-access-control.md#ac-6-least-privilege).

## User onboarding and offboarding

| | |
|---|---|
| **Purpose** | Grant, change, or remove access to OpenShift, Argo CD, and RHACS; confirm on the cluster and remove live sessions |
| **When** | Joiner, mover, leaver tickets |
| **Roles** | Manager requests; system owner approves (security officer for `ocp-security-auditors`); IdP administrator changes groups; platform operator checks and removes sessions |
| **Prerequisites** | Approved ticket naming user, IdP group, reason. A new group is a pull request to the `rbac` component, not this SOP |
| **Controls** | AC-2, AC-2(3), AC-2(4), AC-6, AC-12, IA-4, PS-4, PS-5 |

### Procedure

**Onboarding or change**

1. The IdP administrator adds the user to the approved group; the user logs in once (`oc login --web`
   or console), which records the groups in OpenShift. Confirm:

   ```bash
   U=<preferred_username>
   oc get user "${U}" -o jsonpath='{.identities}{"\n"}'          # gc-sso:<subject>
   oc get groups -o json | jq -r --arg u "${U}" '.items[] | select(.users // [] | index($u)) | .metadata.name'
   oc auth can-i get secrets -n openshift-config --as="${U}" --as-group=ocp-security-auditors   # auditors: no
   oc auth can-i '*' '*' --all-namespaces --as="${U}" --as-group=ocp-platform-admins            # admins: yes
   ```

**Offboarding**

1. The IdP administrator removes the user from the group or disables the account.
2. Sessions stay valid until token expiry (8 h max, 15 min idle; [AC-12](../04-itsg33-configuration/controls/ac-access-control.md#ac-11-session-lock-ac-12-session-termination))
   and group membership refreshes only at login. Remove both now:

   ```bash
   U=<preferred_username>
   oc get oauthaccesstokens -o json \
     | jq -r --arg u "${U}" '.items[] | select(.userName==$u) | .metadata.name' \
     | xargs -r oc delete oauthaccesstoken
   for g in $(oc get groups -o json | jq -r --arg u "${U}" '.items[] | select(.users // [] | index($u)) | .metadata.name'); do
     oc adm groups remove-users "${g}" "${U}"
   done
   # Leaver only
   oc delete identity "$(oc get user "${U}" -o jsonpath='{.identities[0]}')"
   oc delete user "${U}"
   # No binding may name the user directly (expect nothing)
   oc get clusterrolebindings,rolebindings -A -o json \
     | jq -r --arg u "${U}" '.items[] | select(.subjects[]? | .kind=="User" and .name==$u) | "\(.metadata.namespace // "-")/\(.metadata.name)"'
   ```

3. Argo CD and RHACS sessions are separate (see the [quarterly review](#quarterly-access-review)).
   If the person held vault, BMC, registry, or break-glass custody, rotate those credentials
   ([Registry robot token rotation](#registry-robot-token-rotation), [BMC credential rotation](node-management.md#bmc-credential-rotation)).

### Verification

The token count for `${U}` is `0` (`oc get oauthaccesstokens -o json | jq --arg u "${U}" '[.items[] | select(.userName==$u)] | length'`);
leaver: `oc get user "${U}"` is `NotFound`; no audit log requests by the user after removal.

### Rollback

Onboarding: remove from the IdP group and offboard. Offboarding: re-approve and re-add in the IdP
(user and identity are recreated at login).

### Records

Ticket with approval, command output, session removal time; the audit log records the `delete` events (AC-2(4)).

## Quarterly access review

| | |
|---|---|
| **Purpose** | Show every privileged path (cluster roles, SCCs, service accounts, Argo CD, RHACS, registry, break-glass) is still needed and approved |
| **When** | Quarterly, and after an incident |
| **Roles** | Platform operator collects; system owner and security officer review and sign (not the collector, AC-5) |
| **Prerequisites** | `cluster-reader` or higher; the previous review record |
| **Controls** | AC-2, AC-5, AC-6(5), AC-6(7), AU-6 |

### Procedure

1. Collect cluster data ([Argo CD access and privileges](../04-itsg33-configuration/gitops-bootstrap.md#argo-cd-access-and-privileges)):

   ```bash
   D=~/access-review/$(date -u +%Y%m%d); mkdir -p "${D}"; cd "${D}"
   oc get groups -o custom-columns=GROUP:.metadata.name,USERS:.users > groups.txt
   oc get users -o custom-columns=USER:.metadata.name,IDENTITIES:.identities > users.txt
   # Who holds cluster-admin
   oc get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin")
     | .metadata.name + ": " + ([.subjects[]? | .kind+"/"+(.namespace // "")+"/"+.name] | join(", "))' > cluster-admin.txt
   # Users and non-system groups bound to cluster roles
   oc get clusterrolebindings -o json | jq -r '.items[] | .metadata.name as $b | .roleRef.name as $r
     | .subjects[]? | select(.kind=="User" or (.kind=="Group" and (.name|startswith("system:")|not)))
     | [$b,$r,.kind,.name] | @tsv' > crb-humans.tsv
   # Non-openshift service accounts with admin, edit, or cluster-admin
   oc get clusterrolebindings,rolebindings -A -o json | jq -r '.items[]
     | select(.roleRef.name|test("^(cluster-admin|admin|edit)$")) | . as $b | .subjects[]?
     | select(.kind=="ServiceAccount" and ((.namespace // "")|startswith("openshift")|not))
     | [$b.kind,($b.metadata.namespace // "-"),$b.metadata.name,$b.roleRef.name,.namespace,.name] | @tsv' > sa-elevated.tsv
   # Privileged SCC users, and pods with a non-default SCC
   oc adm policy who-can use securitycontextconstraints privileged > scc-privileged-who-can.txt
   oc get pods -A -o json | jq -r '.items[] | [.metadata.namespace,.metadata.name,.metadata.annotations["openshift.io/scc"]]
     | @tsv' | grep -v -E 'restricted-v2$' > pods-non-default-scc.tsv
   # Argo CD RBAC: only the two groups have roles
   oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.rbac}{"\n"}' > argocd-rbac.json
   oc get clusterrolebinding itsg33-gitops-cluster-admin -o yaml > argocd-controller-crb.yaml
   sha256sum * > SHA256SUMS
   ```

2. RHACS (**Platform Configuration → Access Control**): export auth providers, group-to-role
   mappings, and API tokens; revoke tokens nobody can justify.
3. Mirror registry (Quay UI, organization `mirror`): only `importer`, `cluster_pull`, and the
   break-glass administrator should exist (AD-21).
4. Vault: compare who can open the break-glass entries (installer kubeconfig, `core` SSH key,
   registry administrator, BMC credentials) with the approved custodians.
5. Compare all lists with the previous review and the approved access list; ticket each
   unexplained entry and remove it through the normal process (Git PR, IdP, or offboarding).

### Verification

Every entry is approved or has a removal ticket; reviewers sign the record.

### Rollback

Not applicable (read-only).

### Records

Review directory with `SHA256SUMS`, signed review record, tickets raised.

## Break-glass use and review

| | |
|---|---|
| **Purpose** | Use the sealed installer kubeconfig (`system:admin`, client certificate) when IdP login is impossible (IdP/OAuth outage, etcd restore). It bypasses IdP and MFA |
| **When** | Only when IdP login is impossible |
| **Roles** | System owner or delegate authorizes (in the ticket); two custodians unseal (dual control); a platform operator uses it, second custodian watching; security officer reviews within 2 working days |
| **Prerequisites** | Incident ticket stating why IdP access is impossible, with the authorization |
| **Controls** | AC-2, AC-6(9), AC-17, AU-6, AU-9, IA-2, IR-4 |

### Procedure

1. Both custodians open the vault entry and copy the kubeconfig to the admin host (mode 0600,
   session-specific path). Record the start time.
2. Use it only for the authorized task, with a command log:

   ```bash
   script -q ~/breakglass/$(date -u +%Y%m%dT%H%M%SZ)-session.log
   export KUBECONFIG=~/breakglass/kubeconfig
   oc whoami          # system:admin
   # ... authorized actions only ...
   exit
   ```

3. `shred -u ~/breakglass/kubeconfig`, confirm the vault entry is resealed, record the end time.
4. Export the credential's requests for the window (the SIEM holds the authoritative copy):

   ```bash
   for n in $(oc get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[*].metadata.name}'); do
     oc adm node-logs "${n}" --path=kube-apiserver/audit.log
   done | jq -rR 'fromjson? | select(.user.username=="system:admin")
         | [.requestReceivedTimestamp,.verb,.objectRef.resource,.objectRef.namespace,.objectRef.name] | @tsv' \
     > breakglass-audit.tsv
   ```

5. The reviewer compares actions with the authorization and session log, and signs.

> **Non-revocable (unverified).** The Red Hat 4.22 docs reviewed give no procedure to revoke or
> regenerate the installer `system:admin` kubeconfig (`oc adm ocp-certificates` doesn't cover it).
> Until Red Hat support confirms one: protect it by custody (dual control, vault audit), alert on
> `user.username == "system:admin"` outside approved windows (AU-6), and if it may be exposed, open
> a high-severity incident and a Red Hat support case before closing.

### Verification

Vault entry resealed; no `system:admin` requests after the recorded end time.

### Rollback

Not applicable.

### Records

Incident ticket, authorization, vault access log, session log, `breakglass-audit.tsv`, signed review.

## Registry robot token rotation

| | |
|---|---|
| **Purpose** | Rotate the mirror registry robot tokens (`importer`, `cluster_pull`) and update the cluster pull secret |
| **When** | Departmental schedule, and when someone with access leaves |
| **Roles** | Registry administrator and platform operator perform; change ticket approves |
| **Prerequisites** | Window with no upgrade, node scaling, or operator install: the old `cluster_pull` token dies at once, so new pulls fail until the pull secret is updated (running images are unaffected) |
| **Controls** | IA-5, IA-5(1), AC-2, CM-11 |

### Procedure

1. Regenerate the token and rewrite `~/.config/ocp-registry/cluster-pull-secret.json` as in
   [Mirror registry → Rotate robot tokens](../02-high-side/mirror-registry.md#rotate-robot-tokens)
   (`importer`: stop here).
2. Replace the global pull secret (mirror registry credentials only, AD-08) and test:

   ```bash
   oc set data secret/pull-secret -n openshift-config \
     --from-file=.dockerconfigjson="${HOME}/.config/ocp-registry/cluster-pull-secret.json"
   oc get mcp -w                       # wait until every pool is UPDATED=True
   # Then test a pull on one node per pool
   oc debug --quiet node/<node> -- chroot /host podman pull --authfile /var/lib/kubelet/config.json \
     registry.example.gc.ca:8443/mirror/openshift/release-images@sha256:<release-digest>
   ```

### Verification

Test pulls succeed; no new pull failures: `oc get events -A --field-selector reason=Failed | grep -i pull`.

### Rollback

No old token to return to: test the file with `oc image info -a ~/.config/ocp-registry/cluster-pull-secret.json <release-image>@sha256:<digest>`,
regenerate if needed, repeat step 2.

### Records

Change ticket, rotation time, SHA-256 of the new credential file (never its content), test output.
