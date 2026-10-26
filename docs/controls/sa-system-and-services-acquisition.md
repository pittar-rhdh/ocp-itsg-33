# SA — System and Services Acquisition

[← Back to control families](index.md) · [← Back to main](../index.md)

ITSG-33 is based on NIST SP 800-53 Rev 3, so **supply chain protection is covered by SA-12**. There is
no separate `SR` family.

---

### SA-4 Acquisition Process / SA-5 Information System Documentation

**Implementation guidance:**

- Red Hat publishes product documentation, security guides, a product lifecycle policy, and
  security advisories (Red Hat Security Data API, CSAF/VEX).
- Keep a copy of the 4.22 documentation set that matches your deployed version with the SSP.
- Contracts for managed offerings should spell out CCCS assessment status, data residency in
  Canada, and support access terms.

---

### SA-8 Security Engineering Principles

**Implementation guidance:** OpenShift follows several security engineering principles:

| Principle | How OpenShift applies it |
|---|---|
| Least privilege | `restricted-v2` SCC by default |
| Mandatory access control | SELinux enforcing |
| Immutable infrastructure | RHCOS image-based OS |
| Operator-managed reconciliation | Operators restore the declared configuration |
| Defence in depth | Admission control, network policy, encryption |

The reference architecture adds:

- zoning (ITSP.80.022),
- GitOps, and
- continuous compliance.

---

### SA-9 External Information System Services

| Attribute | Value |
|---|---|
| **Responsibility** | Org, Platform |

**Implementation guidance:** Identify every external service the platform uses, and decide
whether each is acceptable for Protected B:

| Service | Data sent | Recommendation |
|---|---|---|
| **Telemetry** (remote health monitoring) | Cluster health metrics and configuration metadata (no application data) | Review against departmental data residency policy. Opt out if needed by removing `cloud.openshift.com` from the global pull secret. |
| **Insights Operator** | Anonymized configuration and health data | Same review. Can be disabled. Insights also gives useful Advisor recommendations. |
| **Red Hat registries / update service** | Pull requests only | Use the departmental proxy, or go disconnected with `oc-mirror` v2 |
| **RHACS vulnerability feeds** | Download only | Use the offline bundle in disconnected mode |
| **Red Hat support (`must-gather`)** | Diagnostic data that may contain sensitive configuration | Clean the data before uploading. Follow departmental policy. |

**Configuration example — opt out of remote health reporting:**

```bash
oc extract secret/pull-secret -n openshift-config --to=.
# Edit .dockerconfigjson to remove the "cloud.openshift.com" entry, then:
oc set data secret/pull-secret -n openshift-config \
  --from-file=.dockerconfigjson=.dockerconfigjson
```

---

### SA-10 Developer Configuration Management / SA-11 Developer Security Testing

| Attribute | Value |
|---|---|
| **Responsibility** | Tenant (applications), Platform (pipeline service), Red Hat (product SDLC) |
| **OpenShift capabilities** | OpenShift Pipelines (Tekton) and Tekton Chains, Red Hat Trusted Artifact Signer, Red Hat Trusted Profile Analyzer, Red Hat Advanced Developer Suite, RHACS `roxctl` |

**Implementation guidance:**

- Offer a **secure pipeline template** that includes:
  - source and dependency scanning,
  - image builds from approved base images (UBI),
  - `roxctl image check`,
  - SBOM generation,
  - image signing, and
  - signed provenance attestations (Tekton Chains / SLSA).
- Red Hat develops OpenShift under its secure development lifecycle. Red Hat product SBOMs and
  VEX data are published. Use these as SA-11 evidence for the platform layer.

---

### SA-12 Supply Chain Protection

| Attribute | Value |
|---|---|
| **Responsibility** | Red Hat (signed content), Platform (verification), Tenant (application images) |
| **Inheritable by tenants** | Partial |
| **OpenShift capabilities** | Release image signature verification, sigstore `ClusterImagePolicy` / `ImagePolicy`, OLM sigstore validation, approved registries, mirroring, SBOMs |
| **Automated check** | ACM policy, RHACS "image signature verification" policies |

**Implementation guidance:**

- **Platform content:** OpenShift checks the signatures of release images during upgrades. In
  4.22, the **default sigstore `openshift` cluster image policy** (General Availability since 4.21)
  checks the signatures of OpenShift release payload images. In 4.22, **OLM v1 can check operator
  images against sigstore signatures** (General Availability).
- **Departmental content:** sign application images in the pipeline (Red Hat Trusted Artifact
  Signer or cosign with a key held in a KMS or HSM). Enforce signatures for production registries
  with `ClusterImagePolicy` (cluster-wide) or `ImagePolicy` (per namespace).
- **Mirroring:** in disconnected environments, `oc-mirror` v2 brings in only approved content.
  Content is kept by digest. `ImageDigestMirrorSet` replaces the deprecated
  `ImageContentSourcePolicy`.
- **SBOM:** keep SBOMs for all production images in Red Hat Trusted Profile Analyzer or an equivalent
  tool. This also helps with RA-5 (finding which images a new CVE affects).

**Configuration example — require signatures from the departmental key:**

```yaml
apiVersion: config.openshift.io/v1
kind: ClusterImagePolicy
metadata:
  name: itsg33-dept-signed
spec:
  scopes:
    - registry.example.gc.ca/prod          # Every image under this scope must be signed
  policy:
    rootOfTrust:
      policyType: PublicKey
      publicKey:
        keyData: <base64-encoded-PEM-public-key>
    signedIdentity:
      matchPolicy: MatchRepoDigestOrExact
```

> Signature verification is enforced by CRI-O on each node when the image is pulled. The
> Machine Config Operator rolls the policy out to the nodes. Test it in a non-production cluster,
> because pulls of unsigned images in scope **will fail**. Check the API version with
> `oc explain clusterimagepolicy`.

**Evidence:**

```bash
oc get clusterimagepolicies,imagepolicies -A
oc get imagedigestmirrorsets,imagetagmirrorsets
oc get image.config.openshift.io cluster -o yaml
```

Also collect pipeline attestation records and the SBOM inventory export.

---

### SA-22 Unsupported System Components

**Implementation guidance:**

- Keep every cluster on a **supported** OpenShift release. 4.22 is an even-numbered (EUS)
  release, with a 24-month Extended Update Support phase and an optional add-on that extends
  support further. Check the current Red Hat OpenShift Life Cycle Policy.
- Plan EUS-to-EUS upgrades (4.22 → 4.24) before support ends.
- Track layered operator lifecycles separately (for example, Logging, ACM, RHACS, and the
  Compliance Operator each have their own support windows).
- RHACS can flag images built on base OS releases that are no longer supported.

```bash
oc get clusterversion version -o jsonpath='{.spec.channel}{"\n"}{.status.desired.version}{"\n"}'
```
