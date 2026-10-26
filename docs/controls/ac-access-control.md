# AC — Access Control

[← Back to control families](index.md) · [← Back to main](../index.md)

Access control in OpenShift has several layers:

- **authentication**, covered in the [IA family](ia-identification-and-authentication.md),
- **authorization** through Kubernetes RBAC,
- **admission control** through Security Context Constraints (SCC), Pod Security Admission, and
  admission policies, and
- **network-level information flow** through `NetworkPolicy`, `AdminNetworkPolicy`, and
  `EgressFirewall`.

---

### AC-2 Account Management

| Attribute | Value |
|---|---|
| **Responsibility** | Platform (cluster accounts), Org (IdP lifecycle) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | External IdP (OIDC/LDAP), `Group` objects, RBAC, service accounts, removal of `kubeadmin` |
| **Automated check** | Compliance Operator (`ocp4-moderate`), ACM policy |

**Control intent (summary):** Manage information system accounts: identify account types, assign
account managers, set conditions for group membership, authorize access, and monitor, disable, and
remove accounts.

**Implementation guidance:**

- **No local accounts.** All human users authenticate through the departmental IdP (see IA-2). Do
  not use the `HTPasswd` provider in production except for a documented break-glass case.
- **Remove `kubeadmin`** once an IdP and a cluster-admin group are in place.
- **Groups drive authorization.** Use IdP group claims (OIDC `groups`) or LDAP group sync. Bind
  roles to **groups**, not individual users, so the IdP's joiner/mover/leaver process covers
  OpenShift access as well.
- **Service accounts** are workload identities. Limit who can create them and bind roles to them
  (namespace `admin` and above). Review them regularly.
- **Disable self-provisioning of projects** so namespace creation goes through an authorized
  request process (for example, GitOps pull requests).
- **AC-2(3) Disable inactive accounts:** handled at the IdP. Removing a user from the IdP stops
  new logins. Existing OAuth tokens expire according to the token lifetime (see AC-12).
- **AC-2(4) Automated audit actions:** creating, changing, or deleting `User`, `Group`, `Identity`,
  `RoleBinding`, and `ClusterRoleBinding` objects is recorded in the API audit log (see AU-2).

**Configuration example — remove kubeadmin and disable self-provisioning:**

```bash
# After verifying that an IdP-backed cluster-admin group works:
oc delete secret kubeadmin -n kube-system

# Stop all authenticated users from creating projects
oc patch clusterrolebinding.rbac self-provisioners \
  -p '{"subjects": null}'
oc annotate clusterrolebinding.rbac self-provisioners \
  'rbac.authorization.kubernetes.io/autoupdate=false' --overwrite
```

**Configuration example — bind cluster roles to IdP groups (GitOps-managed):**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: itsg33-platform-admins
  annotations:
    itsg33/controls: "AC-2,AC-5,AC-6"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: ocp-platform-admins          # Group name from the IdP groups claim
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: itsg33-security-auditors
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-reader                 # Read-only access for assessors and the security team
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: ocp-security-auditors
```

**Evidence:**

```bash
oc get secret kubeadmin -n kube-system            # Expect: NotFound
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].type}'
oc get clusterrolebinding self-provisioners -o yaml
oc get groups
oc get users
oc get clusterrolebindings -o wide | grep -E 'cluster-admin|admin'
```

Also collect:

- the IdP account management procedure (joiner/mover/leaver), and
- a sample access review record.

---

### AC-3 Access Enforcement

| Attribute | Value |
|---|---|
| **Responsibility** | Platform |
| **Inheritable by tenants** | Full (platform), Partial (application) |
| **OpenShift capabilities** | Kubernetes RBAC, SCC, Pod Security Admission, `ValidatingAdmissionPolicy`, SELinux |
| **Automated check** | Compliance Operator, RHACS |

**Control intent (summary):** Enforce approved authorizations for logical access to information and
system resources.

**Implementation guidance:**

- Every API request is authorized by RBAC. Use the built-in roles (`admin`, `edit`, `view`) for
  tenants in their own namespaces. Create narrower custom roles where needed.
- **SCCs** and **Pod Security Admission** decide what pods may do on the node. Keep
  `restricted-v2` as the default. Don't grant the `privileged` or `anyuid` SCCs to tenant service
  accounts.
- **SELinux** (enforcing on RHCOS) gives mandatory access control between containers, using MCS
  labels assigned per namespace.
- Use `ValidatingAdmissionPolicy` (built into Kubernetes) for organization-specific rules (for
  example, requiring a data classification label on namespaces).

**Configuration example — require a classification label on namespaces:**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: itsg33-require-classification-label
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["namespaces"]
  validations:
    - expression: >-
        has(object.metadata.labels) &&
        'data-classification' in object.metadata.labels &&
        object.metadata.labels['data-classification'] in ['unclassified','protected-a','protected-b']
      message: "Namespaces must carry a data-classification label (unclassified, protected-a, protected-b)."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: itsg33-require-classification-label
spec:
  policyName: itsg33-require-classification-label
  validationActions: ["Deny", "Audit"]
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["default", "kube-system", "kube-public", "kube-node-lease"]
        - key: openshift.io/run-level
          operator: DoesNotExist
```

> Test this in audit-only mode (`validationActions: ["Audit"]`) first. Platform namespaces
> (`openshift-*`) are created by operators and need to be excluded or pre-labelled.

**Evidence:**

```bash
oc get scc -o custom-columns=NAME:.metadata.name,PRIV:.allowPrivilegedContainer,USERS:.users,GROUPS:.groups
oc adm policy who-can use scc privileged
oc get validatingadmissionpolicies,validatingadmissionpolicybindings
oc auth can-i --list --as=<tenant-user> -n <tenant-namespace>
```

---

### AC-4 Information Flow Enforcement

| Attribute | Value |
|---|---|
| **Responsibility** | Platform (cluster-wide guardrails), Tenant (application flows) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | `NetworkPolicy`, `AdminNetworkPolicy`, `BaselineAdminNetworkPolicy`, `EgressFirewall`, `EgressIP`, ingress sharding, `ClusterUserDefinedNetwork` (primary networks per zone) |
| **Automated check** | Compliance Operator (`ocp4-configure-network-policies*` rules), RHACS network graph |

**Control intent (summary):** Enforce approved authorizations for controlling the flow of
information within the system and between interconnected systems.

**Implementation guidance:**

- **Cluster guardrails (platform):** use `AdminNetworkPolicy` (ANP) for rules tenants cannot
  override, such as blocking access from tenant namespaces to platform namespaces or to node and
  infrastructure subnets. Use `BaselineAdminNetworkPolicy` (BANP) to set a **default-deny** that
  tenants can relax with their own `NetworkPolicy`.
- **Namespace defaults:** the project template (see CM-2) creates default-deny `NetworkPolicy`
  objects in every new namespace, plus allow rules for the ingress router and monitoring.
- **Egress:** use `EgressFirewall` per namespace to allow only approved external destinations (for
  example, a database in the RZ or an approved SaaS endpoint).
- **Zone separation:** make PAZ-facing routes go only through the `paz` IngressController (see
  [architecture](../02-reference-architecture.md#network-security-zones-itsp80022)).
- **Network-level zone isolation:** where policy alone isn't enough, put each zone on its own
  primary `ClusterUserDefinedNetwork` (see
  [below](#network-level-segmentation-with-clusteruserdefinednetwork)). With this, a wrong tenant
  `NetworkPolicy` can't open a path between zones.

**Configuration example — baseline default-deny with platform guardrails:**

```yaml
# Tenants may allow traffic with NetworkPolicy; otherwise everything between namespaces is denied.
apiVersion: policy.networking.k8s.io/v1alpha1
kind: BaselineAdminNetworkPolicy
metadata:
  name: default                         # Only one BANP named "default" is allowed
spec:
  subject:
    namespaces:
      matchLabels:
        itsg33/tenant: "true"
  ingress:
    - name: default-deny-ingress
      action: Deny
      from:
        - namespaces: {}
  egress:
    - name: default-deny-egress-to-cluster
      action: Deny
      to:
        - namespaces: {}
---
# Guardrail tenants cannot override: allow DNS, deny access to platform namespaces.
apiVersion: policy.networking.k8s.io/v1alpha1
kind: AdminNetworkPolicy
metadata:
  name: itsg33-tenant-guardrails
spec:
  priority: 10
  subject:
    namespaces:
      matchLabels:
        itsg33/tenant: "true"
  egress:
    - name: allow-dns
      action: Allow
      to:
        - namespaces:
            matchLabels:
              kubernetes.io/metadata.name: openshift-dns
      ports:
        - portNumber: { protocol: UDP, port: 5353 }
        - portNumber: { protocol: TCP, port: 5353 }
    - name: deny-platform-namespaces
      action: Deny
      to:
        - namespaces:
            matchExpressions:
              - key: kubernetes.io/metadata.name
                operator: In
                values: ["openshift-etcd", "openshift-kube-apiserver", "openshift-monitoring", "openshift-logging"]
```

> **API version note:** In OpenShift, the ANP/BANP APIs use `policy.networking.k8s.io/v1alpha1`.
> Upstream is moving to a unified `ClusterNetworkPolicy` API. Check
> `oc api-resources | grep -i networkpolicy` on your 4.22 cluster and follow the release notes for
> any migration path.

**Configuration example — namespace egress firewall:**

```yaml
apiVersion: k8s.ovn.org/v1
kind: EgressFirewall
metadata:
  name: default                         # Must be named "default"; one per namespace
  namespace: payments-prod
spec:
  egress:
    - type: Allow
      to:
        cidrSelector: 10.20.30.0/24     # RZ database subnet
    - type: Allow
      to:
        dnsName: api.payments-partner.example.gc.ca
    - type: Deny
      to:
        cidrSelector: 0.0.0.0/0
```

#### Network-level segmentation with ClusterUserDefinedNetwork

Where policy-based isolation isn't strong enough (for example, between the OZ and RZ), give each
zone its own **primary `ClusterUserDefinedNetwork`**. This is tier 2 of the
[network isolation model](../02-reference-architecture.md#network-isolation-model). OVN-Kubernetes
isolates separate primary networks by default. A tenant `NetworkPolicy` that tries to allow traffic
between namespaces on different primary networks has no effect. Traffic between zones must leave
the cluster and pass through the departmental Zone Interface Point.

**Configuration example — RZ zone network and an RZ namespace:**

```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: zone-rz                         # 15 characters or fewer if it will map to a VRF (see SC-7)
  labels:
    itsg33/advertise: "true"            # Only needed for BGP route advertisement
  annotations:
    itsg33/controls: "AC-4,SC-7,SC-4"
spec:
  namespaceSelector:
    matchLabels:
      itsg33/zone: rz                   # Never an empty selector; never default or openshift-*
  network:
    topology: Layer3
    layer3:
      role: Primary
      subnets:
        - cidr: 10.150.0.0/16
          hostSubnet: 24
---
apiVersion: v1
kind: Namespace
metadata:
  name: payments-db
  labels:
    itsg33/zone: rz
    itsg33/tenant: "true"
    data-classification: protected-b
    k8s.ovn.org/primary-user-defined-network: ""   # Must be present at creation; can't be added later
```

> Create the CUDN **before** the namespaces it selects, and create namespaces before any pods.
> OVN-Kubernetes won't move a namespace that already has pods onto a new network. Use `Layer2`
> topology instead when workloads need persistent IPs (for example, OpenShift Virtualization VMs).
> In 4.22, `Primary` is the only supported role for CUDNs.

**Configuration example — guardrail that keeps zone labels consistent:**

A namespace labelled for a zone but missing the primary network label would quietly stay on the
default network, outside the zone. This admission policy blocks that, and stops platform
namespaces from being put into a zone.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: itsg33-zone-network-consistency
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["namespaces"]
  validations:
    - expression: >-
        !(has(object.metadata.labels) && 'itsg33/zone' in object.metadata.labels &&
          object.metadata.labels['itsg33/zone'] in ['oz','rz']) ||
        'k8s.ovn.org/primary-user-defined-network' in object.metadata.labels
      message: "Namespaces in a CUDN zone (oz, rz) must be created with the k8s.ovn.org/primary-user-defined-network label."
    - expression: >-
        !(has(object.metadata.labels) && 'itsg33/zone' in object.metadata.labels) ||
        !(object.metadata.name == 'default' || object.metadata.name.startsWith('openshift-') ||
          object.metadata.name.startsWith('kube-'))
      message: "Platform namespaces must not be assigned to a CUDN zone."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: itsg33-zone-network-consistency
spec:
  policyName: itsg33-zone-network-consistency
  validationActions: ["Deny", "Audit"]
```

> Only platform administrators should be able to create `ClusterUserDefinedNetwork` objects or set
> zone labels on namespaces. Tenants can create namespace-scoped `UserDefinedNetwork` objects if RBAC
> allows it. Decide whether to allow this, and restrict the `userdefinednetworks` resource if not.

**Evidence:**

```bash
oc get clusteruserdefinednetworks
oc get clusteruserdefinednetwork zone-rz -o jsonpath='{.status.conditions}' | jq
oc get userdefinednetworks -A                                # Tenant-created UDNs (expect none, or approved)
oc get ns -L itsg33/zone,k8s.ovn.org/primary-user-defined-network
oc get validatingadmissionpolicy itsg33-zone-network-consistency

# Negative test (CA-2): an OZ pod must NOT reach an RZ pod directly.
# The UDN IP is in the pod's k8s.ovn.org/pod-networks annotation.
RZ_IP=$(oc get pod <rz-pod> -n payments-db \
  -o jsonpath='{.metadata.annotations.k8s\.ovn\.org/pod-networks}' \
  | jq -r 'to_entries[] | select(.value.role=="primary") | .value.ip_address' | cut -d/ -f1)
oc exec -n payments-web <oz-pod> -- curl -s -m 5 "http://${RZ_IP}:8080" ; echo "exit=$?"  # Expect a timeout
```

Keep the output of the negative test, with its date, in the evidence bundle.

**Evidence (all AC-4 mechanisms):**

```bash
oc get adminnetworkpolicies,baselineadminnetworkpolicies
oc get networkpolicies -A
oc get egressfirewalls -A
# Namespaces without any NetworkPolicy (should be empty, apart from approved exceptions)
comm -23 <(oc get ns -o name | sed 's|namespace/||' | sort) \
         <(oc get networkpolicy -A --no-headers | awk '{print $1}' | sort -u)
```

Also collect:

- an RHACS network graph export for in-scope namespaces, and
- OVN ACL audit logs (see AU-12).

---

### AC-5 Separation of Duties

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | RBAC roles, IdP groups, GitOps approval workflows |
| **Automated check** | ACM policy (verify bindings) |

**Control intent (summary):** Separate duties of individuals to prevent malevolent activity without
collusion.

**Implementation guidance:**

| Role | IdP group | OpenShift role(s) | Notes |
|---|---|---|---|
| Platform administrator | `ocp-platform-admins` | `cluster-admin` (break-glass only) or a scoped custom role | Day-to-day changes go through GitOps, not direct `oc` |
| Platform operator | `ocp-platform-operators` | Custom role: nodes, MCPs, operators, no RBAC or secrets | |
| Security auditor | `ocp-security-auditors` | `cluster-reader`, read-only access to logs | Must not hold any write role |
| Security administrator | `ocp-security-admins` | Manage SCC, RHACS policies, Compliance Operator | Separate from platform admins |
| Tenant administrator | `<app>-admins` | `admin` in their own namespaces | |
| Tenant developer | `<app>-developers` | `edit` in non-production, `view` in production | |
| GitOps controller | Service account | Scoped permissions for the resources it manages | Changes need PR approval from a second person |

- Make **Git pull request approval** (two-person review) the main change path. The person who
  writes a change must not approve it.
- Keep audit log management (SIEM) under a different team from platform administration (AU-9).

**Evidence:**

- the role matrix above, kept as part of the SSP,
- an export of `ClusterRoleBindings` and `RoleBindings`, and
- Git branch protection settings.

---

### AC-6 Least Privilege

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Tenant |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | RBAC, `restricted-v2` SCC, Pod Security Admission, Security Profiles Operator, bound service account tokens |
| **Automated check** | Compliance Operator (`ocp4-rbac-*`, `ocp4-scc-*` rules), RHACS policies |

**Control intent (summary):** Allow only the access users, and processes acting for users, need to
do their tasks.

**Implementation guidance:**

- **AC-6(1) Authorize access to security functions:** only `ocp-security-admins` may change SCCs,
  `APIServer`, `OAuth`, compliance configuration, and RHACS policies.
- **AC-6(2) Non-privileged access for non-security functions:** administrators use read-only roles
  for routine work. They use `oc --as` impersonation, or a separate privileged session, only when
  they need to make a change.
- **AC-6(5) Privileged accounts:** keep `cluster-admin` bindings to a minimum. Review them
  monthly.
- **AC-6(9) / AC-6(10) Auditing use of privileged functions; prohibit non-privileged users from
  running privileged functions:** use the API audit log to record privileged actions, and
  SCC/PSA to stop pods from escalating.
- **Workloads:** run containers as a non-root random UID (`restricted-v2`), drop all
  capabilities, set `allowPrivilegeEscalation: false`, use the `RuntimeDefault` seccomp profile, and
  use a read-only root filesystem where possible. Turn off service account token automounting
  where the API isn't needed.

**Configuration example — workload security context baseline (tenant guidance):**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
spec:
  template:
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: registry.example.gc.ca/app/example@sha256:<digest>
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
```

**Evidence:**

```bash
# Who holds cluster-admin
oc get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name + ": " + ([.subjects[]? | .kind+"/"+.name] | join(", "))'
# Pods running under non-default SCCs
oc get pods -A -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name, .metadata.annotations["openshift.io/scc"]] | @tsv' | grep -v restricted-v2
```

Also collect RHACS policy violations for "Privileged container", "Root user", and similar
policies.

---

### AC-7 Unsuccessful Logon Attempts

| Attribute | Value |
|---|---|
| **Responsibility** | Org (IdP) |
| **Inheritable by tenants** | Full |
| **OpenShift capabilities** | Delegated to the external IdP |
| **Automated check** | IdP configuration evidence |

**Implementation guidance:** OpenShift delegates authentication to the external IdP. Set up account
lockout (for example, lock after a set number of consecutive failures within 15 minutes) in the IdP
(Keycloak brute-force detection, Entra ID smart lockout, or AD lockout policy). Failed logins also
appear in the OAuth server logs and IdP logs. Forward both to the SIEM.

**Evidence:** IdP lockout configuration export; a SIEM query that shows failed authentication
events.

---

### AC-8 System Use Notification

| Attribute | Value |
|---|---|
| **Responsibility** | Platform |
| **Inheritable by tenants** | Full (platform UI and CLI) |
| **OpenShift capabilities** | Custom OAuth login template, `ConsoleNotification`, MOTD for node SSH |
| **Automated check** | Compliance Operator (`ocp4-classification-banner`, `ocp4-oauth-login-template-set`, `ocp4-openshift-motd-exists`) |

**Control intent (summary):** Show an approved system use notification before granting access.

**Configuration example — login page and console banner:**

```bash
# Generate the default template, add the GC system use notification, and store it
oc adm create-login-template > login.html
# Edit login.html to add the approved notice text, then:
oc create secret generic itsg33-login-template --from-file=login.html -n openshift-config
```

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  templates:
    login:
      name: itsg33-login-template
---
apiVersion: console.openshift.io/v1
kind: ConsoleNotification
metadata:
  name: itsg33-classification-banner
spec:
  text: "PROTECTED B — Authorized use only. Activity is monitored and logged."
  location: BannerTopBottom
  color: "#FFFFFF"
  backgroundColor: "#00529B"
---
# CLI users: message shown by `oc login`
apiVersion: v1
kind: ConfigMap
metadata:
  name: motd
  namespace: openshift
data:
  message: |
    PROTECTED B — Authorized use only. Use of this system constitutes consent to monitoring.
```

> If you use direct external OIDC authentication instead of the built-in OAuth server, the login
> page belongs to the IdP. Put the notice there.

**Evidence:**

- screenshots of the login page and console banner,
- `oc get consolenotification itsg33-classification-banner -o yaml`, and
- Compliance Operator results for the banner rules.

---

### AC-11 Session Lock / AC-12 Session Termination

| Attribute | Value |
|---|---|
| **Responsibility** | Platform |
| **Inheritable by tenants** | Full (platform sessions) |
| **OpenShift capabilities** | OAuth `accessTokenInactivityTimeout`, `accessTokenMaxAgeSeconds`, console session handling |
| **Automated check** | Compliance Operator (`ocp4-oauth-or-oauthclient-inactivity-timeout`, `ocp4-oauth-or-oauthclient-token-maxage`) |

**Implementation guidance:** Set the inactivity timeout and maximum token lifetime to the
departmental values (for example, 15 minutes of inactivity and an 8-hour maximum). The OS
session lock on the workstation is an endpoint control (Org).

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  tokenConfig:
    accessTokenInactivityTimeout: 15m0s
    accessTokenMaxAgeSeconds: 28800      # 8 hours
```

**Evidence:** `oc get oauth cluster -o jsonpath='{.spec.tokenConfig}'`; Compliance Operator results.

---

### AC-14 Permitted Actions Without Identification or Authentication

**Implementation guidance:** By default, unauthenticated users (`system:unauthenticated`) can reach
only discovery and health endpoints. Check that no `ClusterRoleBinding` or `RoleBinding` grants
other access to `system:unauthenticated` or `system:anonymous`. Record any public routes
deliberately exposed by tenant applications.

```bash
oc get clusterrolebindings,rolebindings -A -o json \
  | jq -r '.items[] | select(.subjects[]?.name | test("system:(unauthenticated|anonymous)")) | .metadata.name'
```

---

### AC-17 Remote Access

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org |
| **Inheritable by tenants** | Full |
| **OpenShift capabilities** | API and console over TLS only; SSH to nodes disabled in normal operation; `oc debug node` is audited |

**Implementation guidance:**

- All administrative access goes through the API (TLS, authenticated, audited). Publish the API
  only to the **MRZ** (bastion or VPN), not to the PAZ.
- **Avoid direct SSH to nodes.** Don't set up SSH keys after installation (or remove them through
  `MachineConfig`). Use `oc debug node/<node>`, which is authorized by RBAC and recorded in
  the audit log. Record any SSH access as an exception.
- **AC-17(2) Protection of confidentiality and integrity using encryption:** TLS profiles (see SC-8).

**Evidence:** API load balancer and firewall rules; audit log entries for `pods/exec` and debug pods;
`oc get machineconfig 99-worker-ssh -o yaml` (should show no keys, or only approved ones).

---

### AC-18 / AC-19 / AC-20 / AC-22

These controls (wireless access, mobile devices, external systems, and publicly accessible content)
are mostly **Org** controls. AC-22 applies to tenants that publish content through the PAZ
IngressController. They must follow departmental web publishing approval.
