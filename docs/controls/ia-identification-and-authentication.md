# IA — Identification and Authentication

[← Back to control families](index.md) · [← Back to main](../index.md)

---

### Authentication model decision

OpenShift 4.22 supports two models for authenticating human users. Record which one you use as
architecture decision **AD-03**.

| Model | How it works | Considerations |
|---|---|---|
| **Built-in OAuth server + external IdP** | The OpenShift OAuth server redirects to the IdP (OIDC, LDAP, and so on). It then issues OpenShift access tokens. | Mature and widely used. Supports the custom login template (AC-8), token timeouts (AC-11/12), and `User`/`Identity` objects. |
| **Direct authentication with an external OIDC provider** | The built-in OAuth server is turned off. The API server validates IdP-issued JWTs directly. | Token lifetime, MFA, and session policy are set in the IdP. Removes the OAuth server from the attack surface. Some advanced claim mapping fields are Technology Preview in 4.22. Check compatibility with the console, the `oc` login flow, and layered products. |

---

### IA-2 Identification and Authentication (Organizational Users)

| Attribute | Value |
|---|---|
| **Responsibility** | Platform (integration), Org (IdP) |
| **Inheritable by tenants** | Full (platform access) |
| **OpenShift capabilities** | OAuth `OpenID` / `LDAP` identity providers, direct external OIDC |
| **Automated check** | Compliance Operator (`ocp4-idp-is-configured`, `ocp4-kubeadmin-removed`) |

**Control intent (summary):** Uniquely identify and authenticate organizational users.

**Implementation guidance:**

- Federate to the departmental IdP using OIDC. Use `mappingMethod: claim` (or `lookup` if accounts
  are provisioned ahead of time) so that each IdP identity maps to exactly one OpenShift user.
- **IA-2(1), IA-2(2) MFA for network access to privileged and non-privileged accounts:** enforce
  MFA in the IdP for all users of the OpenShift client. Use conditional access or a step-up policy
  for members of privileged groups.
- **IA-2(8) Replay-resistant authentication:** OIDC authorization code flow with PKCE and TLS.
  Tokens are bound to issuer and audience.
- Shared accounts are not allowed. The break-glass `kubeconfig` is held in a vault, and checking it
  out triggers an alert.

**Configuration example — OIDC identity provider (built-in OAuth model):**

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
    - name: gc-sso
      mappingMethod: claim
      type: OpenID
      openID:
        clientID: openshift-prod
        clientSecret:
          name: gc-sso-client-secret       # Secret in openshift-config
        ca:
          name: gc-sso-ca                  # ConfigMap in openshift-config with the IdP CA bundle
        issuer: https://sso.example.gc.ca/realms/ocp
        claims:
          preferredUsername: [preferred_username]
          name: [name]
          email: [email]
          groups: [groups]
        extraScopes: [email, profile, groups]
  tokenConfig:
    accessTokenInactivityTimeout: 15m0s
    accessTokenMaxAgeSeconds: 28800
  templates:
    login:
      name: itsg33-login-template
```

**Configuration example — direct external OIDC (excerpt):**

```yaml
apiVersion: config.openshift.io/v1
kind: Authentication
metadata:
  name: cluster
spec:
  type: OIDC
  oidcProviders:
    - name: gc-sso
      issuer:
        issuerURL: https://sso.example.gc.ca/realms/ocp
        audiences: [openshift-prod]
        issuerCertificateAuthority:
          name: gc-sso-ca
      claimMappings:
        username:
          claim: preferred_username
          prefixPolicy: Prefix
          prefix:
            prefixString: "gc-sso:"
        groups:
          claim: groups
      oidcClients:
        - componentName: console
          componentNamespace: openshift-console
          clientID: openshift-console
          clientSecret:
            name: console-oidc-secret
```

> Field names for direct OIDC authentication changed across releases. Validate with
> `oc explain authentication.spec.oidcProviders --api-version=config.openshift.io/v1` on 4.22. Follow
> the documented procedure, including the rollout of the kube-apiserver and a tested rollback
> path, before switching a production cluster.

**Evidence:**

- `oc get oauth cluster -o yaml` or `oc get authentication cluster -o yaml`
- IdP MFA policy configuration
- Compliance Operator results
- a sample audit event showing an individual username

---

### IA-3 Device Identification and Authentication

| Attribute | Value |
|---|---|
| **Responsibility** | Red Hat (design), Platform (CSR approval process) |
| **OpenShift capabilities** | Node client and serving certificates, CSR approval, machine-approver |

**Implementation guidance:** Nodes join the cluster with bootstrap credentials. They then
authenticate with **unique X.509 client certificates** issued by the cluster CA. The
cluster-machine-approver approves CSRs automatically only for machines it can match to a `Machine`
object. For user-provisioned infrastructure, platform staff must approve CSRs by hand after
checking them. Never auto-approve all pending CSRs.

```bash
oc get csr
oc get nodes
```

---

### IA-4 Identifier Management

**Implementation guidance:** User identifiers come from the IdP and are unique for life. Don't
reuse identifiers. OpenShift `User` and `Identity` objects (built-in OAuth model) record the
mapping. Prune stale users regularly (for example, `User` objects with no IdP identity).
Service account identifiers are namespaced (`system:serviceaccount:<ns>:<name>`).

---

### IA-5 Authenticator Management

| Attribute | Value |
|---|---|
| **Responsibility** | Platform, Org |
| **OpenShift capabilities** | Automatic platform certificate rotation, bound service account tokens, cert-manager, External Secrets Operator |
| **Automated check** | Compliance Operator (certificate and token rules) |

**Implementation guidance:**

- **Passwords:** none stored by OpenShift in the recommended model. Password policy is set in the
  IdP (IA-5(1)).
- **IA-5(2) PKI-based authentication:** platform-internal certificates (kubelet, etcd, API server)
  are issued and rotated automatically by OpenShift operators. Externally presented certificates
  (API and ingress) should come from the departmental or GC PKI through **cert-manager**.
- **Service account tokens:** OpenShift uses **bound, projected, time-limited service account
  tokens** by default. Don't create long-lived token secrets (`kubernetes.io/service-account-token`)
  unless there's a documented exception.
- **Workload identity for cloud APIs:** use short-lived tokens (AWS STS, Microsoft Entra Workload
  ID, Google Cloud Workload Identity Federation) with the Cloud Credential Operator in manual mode,
  instead of long-lived cloud keys. Where available, the **Zero Trust Workload Identity Manager**
  (SPIFFE/SPIRE) can issue workload identities.
- **IA-5(7) No embedded unencrypted static authenticators:** RHACS policies and CI secret scanning
  detect secrets in images or environment variables. Use External Secrets with a vault instead.

**Configuration example — cert-manager issuer for departmental PKI (ACME or CA issuer):**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: gc-dept-pki
spec:
  acme:
    server: https://acme.pki.example.gc.ca/directory
    privateKeySecretRef:
      name: gc-dept-pki-account-key
    solvers:
      - dns01:
          rfc2136:
            nameserver: 10.0.0.53:53
            tsigKeyName: ocp-acme
            tsigAlgorithm: HMACSHA256
            tsigSecretSecretRef:
              name: tsig-secret
              key: tsig-secret-key
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-server-cert
  namespace: openshift-config
spec:
  secretName: api-server-cert
  dnsNames: [api.prod.example.gc.ca]
  duration: 2160h       # 90 days
  renewBefore: 360h     # 15 days
  privateKey:
    algorithm: ECDSA
    size: 384
  issuerRef:
    kind: ClusterIssuer
    name: gc-dept-pki
```

**Evidence:**

```bash
# Long-lived service account token secrets (should be empty or documented exceptions)
oc get secrets -A --field-selector type=kubernetes.io/service-account-token
# Certificate expiry overview
oc get certificates.cert-manager.io -A
oc get apiserver cluster -o jsonpath='{.spec.servingCerts}'
```

---

### IA-6 Authenticator Feedback

**Implementation guidance:** The IdP login page masks passwords. The `oc` CLI uses browser-based or
device-flow login and doesn't echo credentials. Tokens are not shown in the console.

---

### IA-7 Cryptographic Module Authentication

**Implementation guidance:** With **FIPS mode** on (see SC-13), authentication-related
cryptography in the platform (TLS, token signing) uses the RHEL cryptographic modules that were
submitted for FIPS 140 validation.

---

### IA-8 Identification and Authentication (Non-Organizational Users)

**Implementation guidance:** Contractors and partners use the same IdP federation (guest accounts,
or a separate realm with MFA). Their group membership limits their access. Platform access by
the public is not allowed. Public users only reach tenant applications, which handle their own
authentication (Tenant responsibility, for example through GCKey or a sign-in partner).
