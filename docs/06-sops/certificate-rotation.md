# Certificate Rotation

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

Certificates from the departmental PKI are rotated by people. Certificates inside the platform
rotate themselves, but someone still has to watch them. This page has one SOP per certificate
owner, plus the monthly expiry check. Commands come from the OpenShift 4.22 *Security and
compliance* guide (chapters 3 and 4), unless noted.

Two rules apply to every SOP on this page:

- **Keep the secret names.** Renew by replacing the **contents** of the existing secret. Red Hat
  documents that the router and the API server hot-reload a renewed certificate, with no rollout.
  Only the first configuration triggers a rollout.
- **Trust before you change the issuer.** If a new certificate comes from a different CA, add that
  CA to every trust store first ([Update the cluster trust bundle](#update-the-cluster-trust-bundle)),
  and remove the old CA only after nothing uses it.

## Update the cluster trust bundle

### Purpose and scope

Add or remove departmental CA certificates that the cluster trusts: for the mirror registry, the
OSUS route, and outbound TLS from platform components. The installer created this bundle from
`additionalTrustBundle` (with `additionalTrustBundlePolicy: Always`, see
[install-config.yaml](../03-cluster-install/install-config.md#settings-in-the-example)).

### Roles

The platform engineer performs it, the PKI team supplies the CA, and the change manager approves.

### Prerequisites

The new CA certificate (PEM) is checked: `openssl x509 -in new-ca.crt -noout -subject -enddate -fingerprint -sha256`,
and the fingerprint is confirmed with the PKI team through a second channel.

### Procedure

1. Find the bundle that the cluster proxy refers to, and add the new CA to it. Keep the old CA in
   the bundle:

   ```bash
   TCA=$(oc get proxy cluster -o jsonpath='{.spec.trustedCA.name}')      # expected: user-ca-bundle
   oc get configmap "$TCA" -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' > ca-bundle.old.crt
   cat ca-bundle.old.crt new-ca.crt > ca-bundle.crt
   oc create configmap "$TCA" -n openshift-config --from-file=ca-bundle.crt=ca-bundle.crt \
     --dry-run=client -o yaml | oc replace -f -
   ```

   Red Hat: the Machine Config Operator writes the bundle to every node without a reboot, but the
   kubelet and CRI-O restart, so each node is briefly `NotReady`. Do it in a maintenance window,
   and watch `oc get mcp` until every pool is `UPDATED=True`.

2. If the CA signs the **mirror registry**, also add it to the `mirror-registry-ca` ConfigMap
   (keys `updateservice-registry` and `registry.example.gc.ca..8443`) through a pull request to
   `04-gitops/components/image-policy/` (see [OSUS setup](upgrades.md#one-time-setup-openshift-update-service)).
   Also add it to `/etc/pki/ocp-registry/ca-bundle.crt` and the `certs.d` directory on the registry
   host ([Trust the registry CA](../02-high-side/mirror-registry.md#trust-the-registry-ca)), and on
   admin hosts.
3. To remove an old CA later, repeat step 1 without it, after every certificate that it issued has
   been replaced.

### Verification

`oc get mcp` shows every pool `UPDATED=True`, and
`oc get configmap "$TCA" -n openshift-config -o yaml` contains the new CA.

### Rollback

Re-apply `ca-bundle.old.crt` the same way.

### Records and evidence

The change ticket, the CA fingerprints added or removed, and the MCP output (SC-12, SC-17,
CM-3).

### Related controls

SC-12, SC-17, SC-8, CM-3.

## Ingress and API server certificates

### Purpose and scope

Serve `*.apps.ocp1.example.gc.ca` (console, OAuth, routes, OSUS) and `api.ocp1.example.gc.ca`
with departmental certificates. This SOP covers the first configuration and every renewal after
it. Never add a named certificate for `api-int`: Red Hat warns that this degrades the cluster.

### Roles

The platform engineer performs it. The PKI team issues the certificates. The second reviewer
reviews the first-time pull request. The change manager approves.

### Prerequisites

- Certificate files in PEM: the leaf first, then the intermediates, then the root. The SAN must be
  `*.apps.ocp1.example.gc.ca` or `api.ocp1.example.gc.ca`. The key must be unencrypted, and RSA
  3072+ or ECDSA P-256/P-384.
- The issuing CA is already in the [cluster trust bundle](#update-the-cluster-trust-bundle).
- The current certificate and key are saved in the departmental vault (rollback).

### Procedure

1. Check the files, as for the registry certificate
   ([Readiness checks](../02-high-side/registry-host.md#readiness-checks)):

   ```bash
   openssl x509 -in apps.crt -noout -checkhost test.apps.ocp1.example.gc.ca -enddate
   openssl x509 -in apps.crt -noout -pubkey | openssl sha256; openssl pkey -in apps.key -pubout | openssl sha256
   openssl verify -purpose sslserver -CAfile dept-ca.crt -untrusted apps.crt apps.crt
   ```

2. Create the secret the first time, or replace its contents on renewal. The names stay fixed:

   ```bash
   oc create secret tls ingress-default-cert -n openshift-ingress --cert=apps.crt --key=apps.key \
     --dry-run=client -o yaml | oc apply -f -
   oc create secret tls api-server-cert -n openshift-config --cert=api.crt --key=api.key \
     --dry-run=client -o yaml | oc apply -f -
   ```

   On renewal, that's all: Red Hat documents that the router and the API server reload the new
   certificate without a rollout. Wait for `oc get co kube-apiserver` to show `PROGRESSING False`.

3. **First time only.** Red Hat's procedure uses `oc patch ingresscontroller default` and
   `oc patch apiserver cluster`. In this design, Argo CD owns both objects, so the references go
   into the cluster overlay through a pull request. The first named certificate rolls out a new
   kube-apiserver revision. Don't make other changes until it finishes.

   ```yaml
   # 04-gitops/overlays/ocp1/config/kustomization.yaml (added under patches:)
   - target: {kind: IngressController, name: default}
     patch: |-
       - op: add
         path: /spec/defaultCertificate
         value: {name: ingress-default-cert}
   - target: {kind: APIServer, name: cluster}
     patch: |-
       - op: add
         path: /spec/servingCerts
         value:
           namedCertificates:
             - names: [api.ocp1.example.gc.ca]
               servingCertificate: {name: api-server-cert}
   ```

4. **Break-glass kubeconfig.** The installer kubeconfig only trusts the cluster's internal CAs.
   Once `api.ocp1.example.gc.ca` serves a departmental certificate, test it
   (`oc --kubeconfig <break-glass> whoami`). If it fails with an `x509` error, add the departmental
   root to the kubeconfig's `certificate-authority-data`, and seal the updated copy again. This is
   expected behaviour, not taken from a Red Hat procedure: confirm it in a lab.

5. **cert-manager (optional `cert-manager-pki` component).** The example `Certificate`
   `api-server-cert` (90 days, renewed 15 days before expiry) writes the same secret, so renewal
   is automatic, and step 2 isn't needed for it. Red Hat documents that cert-manager
   changes only the secret contents, and that the consumer hot-reloads them. Add a `Certificate`
   in `openshift-ingress` for `ingress-default-cert` to do the same for ingress. Watch it with the
   [monthly check](#monitor-certificate-expiry).

### Verification

```bash
for ep in api.ocp1.example.gc.ca:6443 console-openshift-console.apps.ocp1.example.gc.ca:443; do
  openssl s_client -connect "$ep" -servername "${ep%%:*}" -CAfile dept-ca.crt </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -issuer -enddate
done
oc get co ingress kube-apiserver authentication console     # Available, not Degraded
```

### Rollback

Renewal: replace the secret contents with the previous certificate and key from the vault.
First-time configuration: revert the pull request. The cluster goes back to its internal
certificates.

### Records and evidence

The certificate serial numbers and expiry dates (never the keys), the pull request, and the
verification output (SC-12, SC-17, SC-23, IA-5).

### Related controls

SC-8, SC-12, SC-17, SC-23, IA-5.

## Registry, BMC, and departmental service certificates

### Purpose and scope

Renew the other certificates that the platform depends on, without breaking image pulls, node
management, logins, log forwarding, or GitOps: the mirror registry certificate, the BMC
certificates, the OIDC IdP CA (`gc-sso-ca`), the SIEM mutual-TLS client certificate (`siem-tls`),
and the Git server CA (`argocd-tls-certs-cm`). BMC credentials are rotated in
[Node management](node-management.md).

### Roles

The platform engineer performs it (as `quay` on the registry host), with the PKI team and the
owner of the registry, BMC, IdP, SIEM, or Git service. The change manager approves.

### Prerequisites

- New files checked as in [Readiness checks](../02-high-side/registry-host.md#readiness-checks).
  Keys stay in `~/.config/ocp-gitops/ocp1/` (mode `0600`) or on the host they belong to.
- If the issuing CA changed, the new CA is already trusted
  ([Update the cluster trust bundle](#update-the-cluster-trust-bundle)), and every MCP is updated.
- For the registry: no import, upgrade, or node maintenance is running.

### Procedure

1. **Mirror registry.** Rotate on the registry host as
   [Certificate rotation](../02-high-side/mirror-registry.md#certificate-rotation) (Phase 2)
   describes, then repeat the [hardening checks](../02-high-side/mirror-registry.md#hardening).
   Red Hat 4.22: from mirror registry 2.0.11 on, `mirror-registry upgrade --sslCert ... --sslKey ...`
   can also rotate it. Then check that a node can still pull through CRI-O:

   ```bash
   oc debug node/<worker> --quiet -- chroot /host \
     crictl pull registry.example.gc.ca:8443/mirror/ubi9/ubi-minimal:latest
   ```

2. **BMCs.** Prefer renewing from the **same** CA. Then the cluster needs no change: renew one BMC
   at a time and check it as [BMCs](../03-cluster-install/prerequisites.md#bmcs) describes. For a
   **new** CA: the Red Hat 4.22 documentation only describes `bmcVerifyCA` at install time. In the
   upstream `cluster-baremetal-operator` (release-4.22), the metal3 pod mounts an optional
   ConfigMap `bmc-verify-ca` from `openshift-machine-api` at `/certs/ca/bmc`. Add the new CA next
   to the old one in that ConfigMap (keep its key name:
   `oc get cm bmc-verify-ca -n openshift-machine-api -o json | jq '.data | keys'`) before the BMCs
   change. This is source-derived: test it in a lab, or confirm with Red Hat support.
3. **IdP CA, SIEM client certificate.** Re-create the objects with the commands in
   [Secrets kept outside Git](../04-itsg33-configuration/platform-configuration.md#secrets-kept-outside-git).
   During a CA change, the bundle holds the old and the new CA. After the IdP CA changes, wait for
   `oc get co authentication` to show `PROGRESSING False`. If the SIEM doesn't see the new client
   certificate, restart the collector (`oc get ds -n openshift-logging`, then
   `oc rollout restart ds/<name> -n openshift-logging`).
4. **Git server CA.** Patch `argocd-tls-certs-cm` as in
   [GitOps bootstrap](../04-itsg33-configuration/gitops-bootstrap.md#steps) (step 2).

### Verification

```bash
oc get bmh -n openshift-machine-api                    # no RegistrationError
oc get co authentication                               # Available, not Degraded
oc get applications.argoproj.io -n openshift-gitops    # no ComparisonError
```

Also check that an IdP login works, and that the SIEM receives new audit events.

### Rollback

Put the previous registry certificate back from `/data/quay/config-backups/` and restart
`quay-app`. Re-apply the previous BMC certificate or ConfigMap contents, and the previous input
files from the vault.

### Records and evidence

Certificate serial numbers and expiry dates, the SHA-256 of the input files (never their
contents), the hardening log entry, and the verification output (IA-5, SC-17, AU-9, MA-4).

### Related controls

IA-5, IA-5(2), SC-8, SC-12, SC-17, AU-9, MA-4.

## Monitor certificate expiry

### Purpose and scope

Check all certificate expiry dates monthly, and start renewal at **60 days** (the same threshold
as the registry). These certificates rotate themselves (4.22 *Certificate types and descriptions*).
Watch them, but don't rotate them by hand:

| Certificate | Automatic behaviour | What to watch |
|---|---|---|
| Kubelet (node) certificates | Rotated after 30 days. The kubelet CA renews at 292 days, and the old one is removed after 365. No reboot. | A cluster powered off past the rotation date. Recovery is in [Troubleshooting](troubleshooting.md). |
| Service CA and service serving certificates | CA valid 26 months, refreshed with less than 13 months left. Serving certificates last 2 years. | Workloads that don't reload the CA need a restart after a rotation |
| Aggregated API client certificates | CA and client certificates 30 days | Degraded `kube-apiserver` |
| Monitoring and Logging certificates | From the service CA, rotated automatically | Degraded operators |
| First rotation after install | 24 hours after installation | Don't take the first etcd backup before it |

### Roles

The platform engineer or the security auditor (read-only access is enough).

### Prerequisites

Read access to secrets cluster-wide, and `openssl` and `jq` on the admin host.

### Procedure

```bash
OUT=cert-expiry-$(date +%F).tsv
# 1. Endpoints (departmental certificates); "will expire" means less than 60 days left
for ep in api.ocp1.example.gc.ca:6443 console-openshift-console.apps.ocp1.example.gc.ca:443 \
          registry.example.gc.ca:8443 git.example.gc.ca:443; do
  echo "== $ep"; openssl s_client -connect "$ep" -servername "${ep%%:*}" </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -enddate -checkend $((60*86400))
done

# 2. Every TLS secret in the cluster, soonest expiry first
oc get secrets -A --field-selector type=kubernetes.io/tls -o json \
  | jq -r '.items[] | [.metadata.namespace, .metadata.name, .data["tls.crt"]] | @tsv' \
  | while IFS=$'\t' read -r ns name crt; do
      end=$(printf '%s' "$crt" | base64 -d | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
      [ -n "$end" ] && printf '%s\t%s\t%s\n' "$(date -ud "$end" +%F)" "$ns" "$name"
    done | sort > "$OUT"
head -20 "$OUT"

# 3. Platform-managed certificates carry their expiry in an annotation
oc get secrets -A -o json | jq -r '.items[]
  | select(.metadata.annotations["auth.openshift.io/certificate-not-after"])
  | [.metadata.annotations["auth.openshift.io/certificate-not-after"], .metadata.namespace, .metadata.name] | @tsv' \
  | sort | head -10

# 4. CA bundles: subject and expiry of every certificate in the bundle
oc get configmap user-ca-bundle -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' > /tmp/b.crt
openssl crl2pkcs7 -nocrl -certfile /tmp/b.crt | openssl pkcs7 -print_certs -text -noout \
  | grep -E 'Subject:|Not After'

# 5. cert-manager certificates, if used
oc get certificates.cert-manager.io -A \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,NOT_AFTER:.status.notAfter'
```

Also check the RHACS cluster registration secret expiry
([RHACS](../04-itsg33-configuration/platform-configuration.md#rhacs)), the registry certificate
(`-checkend` in [Readiness checks](../02-high-side/registry-host.md#readiness-checks)), the BMC
certificates, and the transfer signing key's expiry
([Ongoing imports](../01-mirroring/ongoing-imports.md#keeping-the-low-side-healthy)).

### Verification

No departmental certificate has less than 60 days left without an open renewal ticket. No
platform-managed certificate is past its `certificate-not-after` date.

### Rollback

Not applicable (read-only).

### Records and evidence

The monthly expiry report (`$OUT` and the command output), kept with the evidence bundle. Renewal
tickets opened from it (SC-12, SC-17, CA-7).

### Related controls

SC-12, SC-17, CA-7, IA-5.
