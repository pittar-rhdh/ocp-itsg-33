# Certificate Rotation

[← Phase 6](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

One SOP per certificate owner, plus the monthly expiry check. Commands are from the OpenShift 4.22 *Security and
compliance* guide unless noted. Two rules apply throughout: **keep the secret names** (renew by replacing the
secret's contents; the router and API server hot-reload them), and **trust before you change the issuer** (add a
new CA to every trust store first; remove the old CA only once nothing uses it).

## Update the cluster trust bundle

| | |
|---|---|
| **Purpose** | Add or remove departmental CAs the cluster trusts (mirror registry, OSUS route, outbound TLS). The bundle came from `additionalTrustBundle` ([install-config.yaml](../03-cluster-install/install-config.md#settings-in-the-example)) |
| **When** | Before deploying a certificate from a new CA; after an old CA is retired |
| **Roles** | Performs: platform engineer. Supplies CA: PKI team. Approves: change manager |
| **Prerequisites** | Maintenance window (kubelet and CRI-O restart; nodes briefly `NotReady`, no reboot). New CA checked (`openssl x509 -in new-ca.crt -noout -subject -enddate -fingerprint -sha256`) and fingerprint confirmed with PKI through a second channel |
| **Controls** | SC-8, SC-12, SC-17, CM-3 |

### Procedure

1. Add the new CA to the bundle the proxy refers to, keeping the old CA:

   ```bash
   TCA=$(oc get proxy cluster -o jsonpath='{.spec.trustedCA.name}')      # expected: user-ca-bundle
   oc get configmap "$TCA" -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' > ca-bundle.old.crt
   cat ca-bundle.old.crt new-ca.crt > ca-bundle.crt
   oc create configmap "$TCA" -n openshift-config --from-file=ca-bundle.crt=ca-bundle.crt \
     --dry-run=client -o yaml | oc replace -f -
   ```

2. If the CA signs the **mirror registry**, also add it to the `mirror-registry-ca` ConfigMap (keys
   `updateservice-registry`, `registry.example.gc.ca..8443`) by PR to `04-gitops/components/image-policy/`
   ([OSUS setup](upgrades.md#one-time-setup-openshift-update-service)), and on the registry and admin hosts
   ([Trust the registry CA](../02-high-side/mirror-registry.md#trust-the-registry-ca)).
3. To remove an old CA, repeat step 1 without it once everything it issued has been replaced.

### Verification

`oc get mcp` shows every pool `UPDATED=True`; the ConfigMap contains the new CA.

### Rollback

Re-apply `ca-bundle.old.crt` the same way.

### Records

Change ticket, CA fingerprints added or removed, `oc get mcp` output.

## Ingress and API server certificates

| | |
|---|---|
| **Purpose** | Serve `*.apps.ocp1.example.gc.ca` and `api.ocp1.example.gc.ca` with departmental certificates. Never add a named certificate for `api-int` (Red Hat: degrades the cluster) |
| **When** | First configuration; 60 days before expiry |
| **Roles** | Performs: platform engineer. Issues: PKI team. Reviews first-time PR: second reviewer. Approves: change manager |
| **Prerequisites** | PEM chain (leaf, intermediates, root), correct SAN, unencrypted RSA 3072+ or ECDSA P-256/P-384 key. Issuing CA in the [trust bundle](#update-the-cluster-trust-bundle). Current cert and key saved in the vault |
| **Controls** | SC-8, SC-12, SC-17, SC-23, IA-5 |

### Procedure

1. Check the files ([Readiness checks](../02-high-side/registry-host.md#readiness-checks)), then create or replace
   the secrets. On renewal that is all; wait for `oc get co kube-apiserver` to show `PROGRESSING False`.

   ```bash
   openssl x509 -in apps.crt -noout -checkhost test.apps.ocp1.example.gc.ca -enddate
   openssl x509 -in apps.crt -noout -pubkey | openssl sha256; openssl pkey -in apps.key -pubout | openssl sha256
   openssl verify -purpose sslserver -CAfile dept-ca.crt -untrusted apps.crt apps.crt
   oc create secret tls ingress-default-cert -n openshift-ingress --cert=apps.crt --key=apps.key \
     --dry-run=client -o yaml | oc apply -f -
   oc create secret tls api-server-cert -n openshift-config --cert=api.crt --key=api.key \
     --dry-run=client -o yaml | oc apply -f -
   ```

2. **First time only.** Argo CD owns the IngressController and APIServer, so add the references to the overlay by
   PR (instead of Red Hat's `oc patch`). This rolls out a kube-apiserver revision; make no other change until done.

   ```yaml
   # 04-gitops/overlays/ocp1/config/kustomization.yaml (added under patches:)
   - target: {kind: IngressController, name: default}
     patch: '[{"op":"add","path":"/spec/defaultCertificate","value":{"name":"ingress-default-cert"}}]'
   - target: {kind: APIServer, name: cluster}
     patch: '[{"op":"add","path":"/spec/servingCerts","value":{"namedCertificates":[{"names":["api.ocp1.example.gc.ca"],"servingCertificate":{"name":"api-server-cert"}}]}}]'
   ```

3. **Break-glass kubeconfig.** Test `oc --kubeconfig <break-glass> whoami`; on an `x509` error add the departmental
   root to its `certificate-authority-data` and reseal it. (Expected behaviour, not from Red Hat: confirm in a lab.)
4. **cert-manager (optional `cert-manager-pki`).** The example `Certificate` `api-server-cert` (90 days, renewed at
   15) writes the same secret, making step 1 automatic. Add one for `ingress-default-cert` to do the same for ingress.

### Verification

```bash
for ep in api.ocp1.example.gc.ca:6443 console-openshift-console.apps.ocp1.example.gc.ca:443; do
  openssl s_client -connect "$ep" -servername "${ep%%:*}" -CAfile dept-ca.crt </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -issuer -enddate
done
oc get co ingress kube-apiserver authentication console     # Available, not Degraded
```

### Rollback

Renewal: put the previous cert and key from the vault back in the secret. First time: revert the PR.

### Records

Serial numbers and expiry dates (never keys), the PR, verification output.

## Registry, BMC, and departmental service certificates

| | |
|---|---|
| **Purpose** | Renew the mirror registry, BMC, IdP CA (`gc-sso-ca`), SIEM client (`siem-tls`), and Git CA (`argocd-tls-certs-cm`) certificates without breaking pulls, node management, logins, logging, or GitOps. BMC credentials: [Node management](node-management.md) |
| **When** | 60 days before expiry, or when the issuing CA changes |
| **Roles** | Performs: platform engineer (as `quay` on the registry host) with PKI and the service owner. Approves: change manager |
| **Prerequisites** | Files checked ([Readiness checks](../02-high-side/registry-host.md#readiness-checks)); keys stay in `~/.config/ocp-gitops/ocp1/` (`0600`) or on their host. A new CA is already [trusted](#update-the-cluster-trust-bundle). Registry: no import, upgrade, or node maintenance running |
| **Controls** | IA-5, IA-5(2), SC-8, SC-12, SC-17, AU-9, MA-4 |

### Procedure

1. **Mirror registry.** Rotate as in [Certificate rotation](../02-high-side/mirror-registry.md#certificate-rotation)
   (2.0.11+ also supports `mirror-registry upgrade --sslCert ... --sslKey ...`), repeat the
   [hardening checks](../02-high-side/mirror-registry.md#hardening), and confirm a node can pull:
   `oc debug node/<worker> --quiet -- chroot /host crictl pull registry.example.gc.ca:8443/mirror/ubi9/ubi-minimal:latest`
2. **BMCs.** Prefer the **same** CA: renew one BMC at a time and check as in
   [BMCs](../03-cluster-install/prerequisites.md#bmcs). For a **new** CA, first add it beside the old one in ConfigMap
   `bmc-verify-ca` in `openshift-machine-api`, keeping its key name (`oc get cm bmc-verify-ca -n openshift-machine-api
   -o json | jq '.data | keys'`). *Source-derived (upstream `cluster-baremetal-operator`; Red Hat documents
   `bmcVerifyCA` only at install): test in a lab or confirm with support.*
3. **IdP CA, SIEM client cert.** Re-create as in
   [Secrets kept outside Git](../04-itsg33-configuration/platform-configuration.md#secrets-kept-outside-git) (old and
   new CA both in the bundle during a CA change). Wait for `oc get co authentication` `PROGRESSING False`. If the SIEM
   doesn't see the new cert, `oc rollout restart ds/<name> -n openshift-logging`.
4. **Git server CA.** Patch `argocd-tls-certs-cm` as in [GitOps bootstrap](../04-itsg33-configuration/gitops-bootstrap.md#steps) step 2.

### Verification

No `RegistrationError` in `oc get bmh -n openshift-machine-api`; `oc get co authentication` Available; no
`ComparisonError` in `oc get applications.argoproj.io -n openshift-gitops`; an IdP login works; the SIEM receives new events.

### Rollback

Restore the registry cert from `/data/quay/config-backups/` and restart `quay-app`; re-apply previous BMC, ConfigMap, and vault inputs.

### Records

Serials and expiry dates, SHA-256 of input files (never contents), hardening log entry, verification output.

## Monitor certificate expiry

| | |
|---|---|
| **Purpose** | Find certificates nearing expiry; start renewal at **60 days**. Platform-internal certificates rotate themselves (4.22 *Certificate types and descriptions*): watch, don't rotate by hand |
| **When** | Monthly |
| **Roles** | Platform engineer or security auditor (read-only is enough) |
| **Prerequisites** | Cluster-wide read on secrets; `openssl` and `jq` on the admin host |
| **Controls** | SC-12, SC-17, CA-7, IA-5 |

Watch for: a cluster powered off past kubelet rotation (30 days; see [Troubleshooting](troubleshooting.md));
workloads that don't reload the service CA after it rotates; degraded operators; no etcd backup in the first 24 hours.

### Procedure

```bash
OUT=cert-expiry-$(date +%F).tsv
# 1. Departmental endpoints; "will expire" = under 60 days
for ep in api.ocp1.example.gc.ca:6443 console-openshift-console.apps.ocp1.example.gc.ca:443 \
          registry.example.gc.ca:8443 git.example.gc.ca:443; do
  echo "== $ep"; openssl s_client -connect "$ep" -servername "${ep%%:*}" </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -enddate -checkend $((60*86400))
done
# 2. Every TLS secret, soonest expiry first
oc get secrets -A --field-selector type=kubernetes.io/tls -o json \
  | jq -r '.items[] | [.metadata.namespace, .metadata.name, .data["tls.crt"]] | @tsv' \
  | while IFS=$'\t' read -r ns name crt; do
      end=$(printf '%s' "$crt" | base64 -d | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
      [ -n "$end" ] && printf '%s\t%s\t%s\n' "$(date -ud "$end" +%F)" "$ns" "$name"
    done | sort > "$OUT"; head -20 "$OUT"
# 3. Platform-managed certificates (expiry annotation)
oc get secrets -A -o json | jq -r '.items[] | select(.metadata.annotations["auth.openshift.io/certificate-not-after"])
  | [.metadata.annotations["auth.openshift.io/certificate-not-after"], .metadata.namespace, .metadata.name] | @tsv' | sort | head
# 4. CA bundle contents
oc get configmap user-ca-bundle -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' \
  | openssl crl2pkcs7 -nocrl -certfile /dev/stdin | openssl pkcs7 -print_certs -noout -text | grep -E 'Subject:|Not After'
# 5. cert-manager, if used
oc get certificates.cert-manager.io -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,NOT_AFTER:.status.notAfter'
```

Also check the RHACS registration secret ([RHACS](../04-itsg33-configuration/platform-configuration.md#rhacs)), BMC
certificates, and the transfer signing key ([Ongoing imports](../01-mirroring/ongoing-imports.md#keeping-the-low-side-healthy)).

### Verification

No departmental certificate under 60 days without a renewal ticket; nothing past `certificate-not-after`.

### Rollback

Not applicable (read-only).

### Records

The monthly report (`$OUT` and output) in the evidence bundle; renewal tickets opened from it.
