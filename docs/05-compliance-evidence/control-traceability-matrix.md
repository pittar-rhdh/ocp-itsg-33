# Control Traceability Matrix

[← Phase 5 overview](index.md)

> **Examples only — not validated.** See [Validation status](../reference/validation-status.md).

This matrix summarizes, for each control, how the reference architecture meets it. Use it as the
starting point for the platform **Security Requirements Traceability Matrix (SRTM)**. Check control
selection against your departmental PBMM / Medium Cloud profile.

## Evidence locations and frequency

Where the evidence for each control is in the [evidence bundle](evidence-collection.md#bundle-layout),
and how often it is produced. Use it to fill the evidence columns of the SRTM.

| Bundle folder / source | Controls | Produced | Collected into the bundle |
|---|---|---|---|
| `00-metadata/` — ClusterVersion, CSVs, content versions, repository commit | CM-8, SA-22 | On change | Quarterly |
| `01-compliance-operator/` — per-rule results with controls, tailoring, remediations | CA-2, CA-7, CM-6, SI-6; every control in the rule annotations (for example AC-2, AC-8, AC-12, AU-2, AU-9, IA-5, SC-8, SC-13, SC-28) | Daily, 01:00 | Quarterly; monthly summary |
| `01-compliance-operator/manual-assessments/` — `MANUAL` checks | Controls of each manual rule | When assessed | Quarterly |
| `02-raw-arf/` — raw ARF results | CA-2, CA-2(1) | Daily (90 kept on the cluster) | Quarterly; before authorization |
| `03-acm-governance/` — policy status and history | CA-7, CM-6; AC-6, AC-8, IA-2, AU-2, AU-4, SC-28, CM-7, SI-7, RA-5 (one policy each) | Continuous | Monthly export; quarterly |
| `04-rhacs/` — vulnerability report, data import record | RA-5, RA-5(2), SI-2, SI-4, SI-5 | Continuous; data import at least daily | Monthly report; quarterly |
| `05-configuration/` — platform configuration exports | CM-2, CM-6, AC-4, AC-8, AC-12, SC-7, SC-8, SC-13, SC-28 | On change | Quarterly |
| `06-access/` — bindings, groups, SCC use | AC-2, AC-3, AC-5, AC-6, AC-14 | On change | Quarterly |
| `07-logging/` — forwarding, audit profile, SIEM receipt | AU-2, AU-4, AU-9, AU-12 | Continuous | Quarterly |
| `08-integrity/` — AIDE results and failure logs | SI-7, SI-7(1) | Every 15 minutes (`gracePeriod: 900`) | Quarterly; failures weekly |
| `09-backup/` — OADP schedules and backups, restore test | CP-9, CP-10, CP-4 | Daily backups; restore test per CP plan | Quarterly |
| `10-change/` — Argo CD history, Git log, install plans, ClusterVersion history, tickets | CM-3, CM-4, CM-5, SI-2 | On change | Quarterly |
| `11-poam/` — POA&M extract | CA-5 | Weekly review | Monthly; quarterly |
| Documents outside the bundle — SSP, IR plan, CP plan, TRA, assessment report | PL-2, IR-8, CP-2, RA-3, CA-2 | Per departmental process | Referenced by name and version in the bundle index |

### Building the departmental SRTM

`05-evidence/srtm-example.csv` shows the target format with representative rows. To build the
SRTM for `ocp1`:

1. Start from the departmental SRTM template and the control list of your PBMM / Medium Cloud
   profile. Keep its control IDs and wording.
2. For each control, copy responsibility, inheritance, and implementation from the family tables
   below and the [control family guides](../04-itsg33-configuration/controls/index.md).
3. **Configuration:** the `04-gitops/` path of the component that implements it (the
   `itsg33/controls` annotation on each object lists its controls).
4. **Automated check:** the ACM policy name, and the Compliance Operator rules that carry the
   control, from the rule-to-control map
   ([Map rules to ITSG-33 controls](compliance-automation-and-evidence.md#map-rules-to-itsg-33-controls)).
5. **Evidence artifact and frequency:** the bundle path and frequency from the table above.
6. **Owner and status:** a named role, and the status from the latest bundle (`Implemented`,
   `Partially implemented`, `Planned`, `Inherited`), with the POA&M ID when not fully implemented.
7. Review the SRTM with every bundle; the assessor checks each row against the bundle it names.

**Legend**

- **Resp.** — main responsible party: `RH` Red Hat, `Inf` Infrastructure, `Plat` Platform,
  `Ten` Tenant, `Org` Organization
- **Inherit** — whether tenants can inherit the control: `Full`, `Part` (partial), `No`
- **Auto** — automated evidence: `CO` Compliance Operator, `ACM` ACM governance, `ACS` RHACS,
  `FIO` File Integrity Operator, `—` manual

## Access Control (AC)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| AC-2 | Account Management | Plat/Org | Part | External IdP, group-based RBAC, kubeadmin removed, self-provisioning disabled | CO, ACM | [AC-2](../04-itsg33-configuration/controls/ac-access-control.md#ac-2-account-management) |
| AC-2(4) | Automated Audit Actions | Plat | Full | API audit of User/Group/RoleBinding changes | CO | [AC-2](../04-itsg33-configuration/controls/ac-access-control.md#ac-2-account-management) |
| AC-3 | Access Enforcement | Plat | Full | RBAC, SCC, PSA, SELinux, ValidatingAdmissionPolicy | CO, ACS | [AC-3](../04-itsg33-configuration/controls/ac-access-control.md#ac-3-access-enforcement) |
| AC-4 | Information Flow Enforcement | Plat/Ten | Part | NetworkPolicy, ANP/BANP, EgressFirewall, ingress sharding, primary CUDN per zone | CO, ACS | [AC-4](../04-itsg33-configuration/controls/ac-access-control.md#ac-4-information-flow-enforcement) |
| AC-5 | Separation of Duties | Plat/Org | Part | Role matrix mapped to IdP groups, GitOps two-person review | ACM | [AC-5](../04-itsg33-configuration/controls/ac-access-control.md#ac-5-separation-of-duties) |
| AC-6 | Least Privilege | Plat/Ten | Part | restricted-v2 SCC, minimal cluster-admin, workload securityContext | CO, ACS | [AC-6](../04-itsg33-configuration/controls/ac-access-control.md#ac-6-least-privilege) |
| AC-7 | Unsuccessful Logon Attempts | Org | Full | IdP lockout | — | [AC-7](../04-itsg33-configuration/controls/ac-access-control.md#ac-7-unsuccessful-logon-attempts) |
| AC-8 | System Use Notification | Plat | Full | OAuth login template, ConsoleNotification, motd | CO | [AC-8](../04-itsg33-configuration/controls/ac-access-control.md#ac-8-system-use-notification) |
| AC-11 | Session Lock | Plat/Org | Full | OAuth inactivity timeout; workstation lock (Org) | CO | [AC-11](../04-itsg33-configuration/controls/ac-access-control.md#ac-11-session-lock-ac-12-session-termination) |
| AC-12 | Session Termination | Plat | Full | OAuth token max age | CO | [AC-12](../04-itsg33-configuration/controls/ac-access-control.md#ac-11-session-lock-ac-12-session-termination) |
| AC-14 | Permitted Actions w/o Identification | Plat | Full | No bindings to unauthenticated/anonymous | ACM | [AC-14](../04-itsg33-configuration/controls/ac-access-control.md#ac-14-permitted-actions-without-identification-or-authentication) |
| AC-17 | Remote Access | Plat/Org | Full | API from MRZ only, no SSH, audited `oc debug` | CO | [AC-17](../04-itsg33-configuration/controls/ac-access-control.md#ac-17-remote-access) |

## Audit and Accountability (AU)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| AU-2 | Auditable Events | Plat/Ten | Part | WriteRequestBodies audit profile, auditd rules, OVN ACL logging | CO | [AU-2](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-2-auditable-events-au-12-audit-generation) |
| AU-3 | Content of Audit Records | Plat | Full | Structured Kubernetes audit events, auditd format | — | [AU-3](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-3-content-of-audit-records) |
| AU-4 | Audit Storage Capacity | Plat/Org | Full | Off-cluster SIEM, node log rotation | — | [AU-4](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-4-audit-storage-capacity-au-5-response-to-audit-processing-failures) |
| AU-5 | Response to Audit Processing Failures | Plat | Full | Collector and forwarder alerts | — | [AU-5](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-4-audit-storage-capacity-au-5-response-to-audit-processing-failures) |
| AU-6 | Audit Review, Analysis, Reporting | Org | Full | SIEM use cases, RHACS alerts | ACS | [AU-6](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-6-audit-review-analysis-and-reporting) |
| AU-7 | Audit Reduction and Report Generation | Org | Full | SIEM, LokiStack | — | [AU-7](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-7-audit-reduction-and-report-generation) |
| AU-8 | Time Stamps | Plat | Full | chrony via MachineConfig | CO | [AU-8](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-8-time-stamps) |
| AU-9 | Protection of Audit Information | Plat/Org | Full | ClusterLogForwarder over TLS, separate SIEM team, WORM storage | CO | [AU-9](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-9-protection-of-audit-information) |
| AU-11 | Audit Record Retention | Org | Full | SIEM and archive retention; LokiStack short-term | — | [AU-11](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-11-audit-record-retention) |
| AU-12 | Audit Generation | Plat | Part | API, OAuth, node, and network audit sources | CO | [AU-12](../04-itsg33-configuration/controls/au-audit-and-accountability.md#au-2-auditable-events-au-12-audit-generation) |

## Security Assessment and Authorization (CA)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| CA-2 | Security Assessments | Org/Plat | Part | Compliance Operator, RHACS compliance, evidence bundle | CO, ACS | [CA-2](../04-itsg33-configuration/controls/ca-security-assessment-and-authorization.md#ca-2-security-assessments) |
| CA-3 | Information System Connections | Plat/Org | No | Proxy, EgressFirewall, ANP, documented connections | — | [CA-3](../04-itsg33-configuration/controls/ca-security-assessment-and-authorization.md#ca-3-information-system-connections) |
| CA-5 | Plan of Action and Milestones | Org | No | FAIL/MANUAL check results feed the POA&M | CO | [CA-5](../04-itsg33-configuration/controls/ca-security-assessment-and-authorization.md#ca-5-plan-of-action-and-milestones) |
| CA-6 | Security Authorization | Org | No | Platform authorized as a common control provider | — | [CA-6](../04-itsg33-configuration/controls/ca-security-assessment-and-authorization.md#ca-6-security-authorization) |
| CA-7 | Continuous Monitoring | Plat/Org | Part | Daily scans, ACM governance, RHACS, FIO | CO, ACM, ACS, FIO | [CA-7](../04-itsg33-configuration/controls/ca-security-assessment-and-authorization.md#ca-7-continuous-monitoring) |

## Configuration Management (CM)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| CM-2 | Baseline Configuration | Plat | Part | Release image + install-config + GitOps repo + tailored profile; project template | ACM | [CM-2](../04-itsg33-configuration/controls/cm-configuration-management.md#cm-2-baseline-configuration) |
| CM-3 | Configuration Change Control | Plat/Org | Part | PR approvals, Argo CD sync windows, MCP pause | — | [CM-3](../04-itsg33-configuration/controls/cm-configuration-management.md#cm-3-configuration-change-control) |
| CM-4 | Security Impact Analysis | Plat | No | Release note review, pre-production scans, CODEOWNERS | — | [CM-4](../04-itsg33-configuration/controls/cm-configuration-management.md#cm-4-security-impact-analysis) |
| CM-5 | Access Restrictions for Change | Plat | Full | GitOps-only writes, branch protection | ACM | [CM-5](../04-itsg33-configuration/controls/cm-configuration-management.md#cm-5-access-restrictions-for-change) |
| CM-6 | Configuration Settings | Plat | Part | Tailored ocp4/rhcos4-moderate profile, remediations via Git | CO | [CM-6](../04-itsg33-configuration/controls/cm-configuration-management.md#cm-6-configuration-settings) |
| CM-7 | Least Functionality | Plat | Part | Cluster capabilities, curated OperatorHub, SCC/PSA | CO, ACS | [CM-7](../04-itsg33-configuration/controls/cm-configuration-management.md#cm-7-least-functionality) |
| CM-8 | Component Inventory | Plat | Full | ClusterVersion, CSVs, ACM Search, RHACS, SBOMs | ACM, ACS | [CM-8](../04-itsg33-configuration/controls/cm-configuration-management.md#cm-8-information-system-component-inventory) |
| CM-11 | User-Installed Software | Plat | Full | allowedRegistries, curated catalog | CO, ACS | [CM-11](../04-itsg33-configuration/controls/cm-configuration-management.md#cm-11-user-installed-software) |

## Contingency Planning (CP)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| CP-2 | Contingency Plan | Org/Plat | Part | Platform recovery scenarios | — | [CP-2](../04-itsg33-configuration/controls/cp-contingency-planning.md#cp-2-contingency-plan) |
| CP-4 | Contingency Plan Testing | Org/Plat | No | Restore and rebuild exercises | — | [CP-4](../04-itsg33-configuration/controls/cp-contingency-planning.md#cp-4-contingency-plan-testing) |
| CP-6 | Alternate Storage Site | Plat/Inf | Part | OADP to alternate-site object storage | ACM | [CP-6](../04-itsg33-configuration/controls/cp-contingency-planning.md#cp-6-alternate-storage-site-cp-9-information-system-backup) |
| CP-7 | Alternate Processing Site | Plat/Inf | Part | Second cluster, ACM, ODF DR | — | [CP-7](../04-itsg33-configuration/controls/cp-contingency-planning.md#cp-7-alternate-processing-site-cp-10-information-system-recovery-and-reconstitution) |
| CP-9 | Information System Backup | Plat/Ten | Part | etcd snapshots, OADP schedules, Git | ACM | [CP-9](../04-itsg33-configuration/controls/cp-contingency-planning.md#cp-6-alternate-storage-site-cp-9-information-system-backup) |
| CP-10 | Recovery and Reconstitution | Plat | Part | GitOps rebuild, post-recovery compliance scan | CO | [CP-10](../04-itsg33-configuration/controls/cp-contingency-planning.md#cp-7-alternate-processing-site-cp-10-information-system-recovery-and-reconstitution) |

## Identification and Authentication (IA)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| IA-2 | Identification and Authentication (Org Users) | Plat/Org | Full | OIDC IdP or direct external OIDC | CO | [IA-2](../04-itsg33-configuration/controls/ia-identification-and-authentication.md#ia-2-identification-and-authentication-organizational-users) |
| IA-2(1)(2) | MFA | Org | Full | Enforced by the IdP | — | [IA-2](../04-itsg33-configuration/controls/ia-identification-and-authentication.md#ia-2-identification-and-authentication-organizational-users) |
| IA-3 | Device Identification and Authentication | RH/Plat | Full | Node X.509 certificates, CSR approval | — | [IA-3](../04-itsg33-configuration/controls/ia-identification-and-authentication.md#ia-3-device-identification-and-authentication) |
| IA-4 | Identifier Management | Org/Plat | Full | IdP-unique identifiers, namespaced SAs | — | [IA-4](../04-itsg33-configuration/controls/ia-identification-and-authentication.md#ia-4-identifier-management) |
| IA-5 | Authenticator Management | Plat | Part | Auto cert rotation, bound SA tokens, cert-manager, External Secrets | CO | [IA-5](../04-itsg33-configuration/controls/ia-identification-and-authentication.md#ia-5-authenticator-management) |
| IA-7 | Cryptographic Module Authentication | RH/Plat | Full | FIPS mode | CO | [IA-7](../04-itsg33-configuration/controls/ia-identification-and-authentication.md#ia-7-cryptographic-module-authentication) |
| IA-8 | Non-Organizational Users | Org/Ten | Part | IdP federation; app-level auth for public users | — | [IA-8](../04-itsg33-configuration/controls/ia-identification-and-authentication.md#ia-8-identification-and-authentication-non-organizational-users) |

## Incident Response (IR)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| IR-4 | Incident Handling | Org/Plat | Part | RHACS detection, quarantine NetworkPolicy, cordon, must-gather | ACS | [IR-4](../04-itsg33-configuration/controls/ir-incident-response.md#ir-4-incident-handling) |
| IR-5 | Incident Monitoring | Org | Full | Alerts routed to the SOC | ACS | [IR-5](../04-itsg33-configuration/controls/ir-incident-response.md#ir-5-incident-monitoring-ir-6-incident-reporting) |
| IR-6 | Incident Reporting | Org | Full | GC CSEMP, CCCS reporting | — | [IR-6](../04-itsg33-configuration/controls/ir-incident-response.md#ir-5-incident-monitoring-ir-6-incident-reporting) |
| IR-8 | Incident Response Plan | Org | Part | Container platform annex | — | [IR-8](../04-itsg33-configuration/controls/ir-incident-response.md#ir-8-incident-response-plan) |

## Risk Assessment (RA)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| RA-2 | Security Categorization | Org | No | Namespace classification labels | ACM | [RA-2](../04-itsg33-configuration/controls/ra-risk-assessment.md#ra-2-security-categorization) |
| RA-3 | Risk Assessment | Org/Plat | No | Platform TRA with container threat model | — | [RA-3](../04-itsg33-configuration/controls/ra-risk-assessment.md#ra-3-risk-assessment) |
| RA-5 | Vulnerability Scanning | Plat/Ten | Part | RHACS (offline feeds), roxctl in CI | ACS | [RA-5](../04-itsg33-configuration/controls/ra-risk-assessment.md#ra-5-vulnerability-scanning) |

## System and Services Acquisition (SA)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| SA-4/SA-5 | Acquisition / Documentation | Org/RH | No | Product documentation, lifecycle, CCCS assessment (managed) | — | [SA-4](../04-itsg33-configuration/controls/sa-system-and-services-acquisition.md#sa-4-acquisition-process-sa-5-information-system-documentation) |
| SA-8 | Security Engineering Principles | RH/Plat | Full | Secure defaults + zoning + GitOps | — | [SA-8](../04-itsg33-configuration/controls/sa-system-and-services-acquisition.md#sa-8-security-engineering-principles) |
| SA-9 | External Information System Services | Org/Plat | No | Telemetry/Insights review, disconnected option | — | [SA-9](../04-itsg33-configuration/controls/sa-system-and-services-acquisition.md#sa-9-external-information-system-services) |
| SA-10/SA-11 | Developer CM / Security Testing | Ten/Plat | Part | Secure pipeline template, Tekton Chains, roxctl | ACS | [SA-10](../04-itsg33-configuration/controls/sa-system-and-services-acquisition.md#sa-10-developer-configuration-management-sa-11-developer-security-testing) |
| SA-12 | Supply Chain Protection | RH/Plat/Ten | Part | Signed release payloads, ClusterImagePolicy, oc-mirror, SBOMs | ACM, ACS | [SA-12](../04-itsg33-configuration/controls/sa-system-and-services-acquisition.md#sa-12-supply-chain-protection) |
| SA-22 | Unsupported System Components | Plat | Full | EUS lifecycle, operator lifecycles | ACM | [SA-22](../04-itsg33-configuration/controls/sa-system-and-services-acquisition.md#sa-22-unsupported-system-components) |

## System and Communications Protection (SC)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| SC-2/SC-3 | Application Partitioning / Security Function Isolation | Plat | Full | Control plane, infra, and worker separation; tenant zones on CUDNs apart from the platform network | — | [SC-2](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-2-application-partitioning-sc-3-security-function-isolation) |
| SC-4 | Information in Shared Resources | Plat | Full | SELinux MCS, per-PVC volumes, CUDN network separation, dedicated pools | CO | [SC-4](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-4-information-in-shared-resources) |
| SC-5 | Denial of Service Protection | Plat/Inf | Part | Quotas, APF, router rate limits | CO | [SC-5](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-5-denial-of-service-protection) |
| SC-7 | Boundary Protection | Plat/Inf | Part | Zoned IngressControllers, CUDN per zone with ZIP between zones, BGP VRF-lite/EVPN (optional), proxy, EgressIP, ANP/BANP | CO, ACM | [SC-7](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-7-boundary-protection) |
| SC-8 | Transmission Confidentiality and Integrity | Plat/Ten | Part | TLS profiles, IPsec, re-encrypt routes | CO | [SC-8](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-8-transmission-confidentiality-and-integrity) |
| SC-10 | Network Disconnect | Plat | Full | Token and router timeouts | CO | [SC-10](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-10-network-disconnect) |
| SC-12 | Cryptographic Key Management | Plat/Org | Part | Platform PKI rotation, cert-manager, External Secrets | — | [SC-12](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-12-cryptographic-key-establishment-and-management-sc-17-pki-certificates) |
| SC-13 | Use of Cryptography | RH/Plat | Part | FIPS mode, ITSP.40.111 algorithms | CO | [SC-13](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-13-use-of-cryptography) |
| SC-17 | PKI Certificates | Plat/Org | Full | Departmental PKI certificates for API and ingress | — | [SC-17](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-12-cryptographic-key-establishment-and-management-sc-17-pki-certificates) |
| SC-23 | Session Authenticity | Plat | Part | TLS-only tokens, secure cookies | — | [SC-23](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-23-session-authenticity) |
| SC-28 | Protection of Information at Rest | Plat/Inf | Part | etcd encryption, LUKS (TPM 2.0), encrypted storage classes | CO | [SC-28](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-28-protection-of-information-at-rest) |
| SC-39 | Process Isolation | RH/Plat | Full | Namespaces, SELinux, seccomp, user namespaces | CO | [SC-39](../04-itsg33-configuration/controls/sc-system-and-communications-protection.md#sc-39-process-isolation) |

## System and Information Integrity (SI)

| Control | Name | Resp. | Inherit | OpenShift implementation | Auto | Guide |
|---|---|---|---|---|---|---|
| SI-2 | Flaw Remediation | RH/Plat/Ten | Part | CVO updates, EUS, manual operator approvals, RHACS | ACS, ACM | [SI-2](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-2-flaw-remediation) |
| SI-3 | Malicious Code Protection | Plat/Ten | Part | RHACS runtime, immutable RHCOS, optional anti-malware | ACS | [SI-3](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-3-malicious-code-protection) |
| SI-4 | Information System Monitoring | Plat/Org | Full | RHACS, Network Observability, audit, alerts | ACS | [SI-4](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-4-information-system-monitoring) |
| SI-5 | Security Alerts and Advisories | Plat/Org | Full | RHSA, CCCS advisories, RHACS CVE correlation | ACS | [SI-5](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-5-security-alerts-advisories-and-directives) |
| SI-6 | Security Function Verification | Plat | Full | Daily Compliance Operator scans | CO | [SI-6](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-6-security-function-verification) |
| SI-7 | Software and Information Integrity | RH/Plat | Part | File Integrity Operator, MCO drift detection, image signatures, Secure Boot | FIO, CO | [SI-7](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-7-software-firmware-and-information-integrity) |
| SI-10 | Information Input Validation | Plat/Ten | Part | API schema validation, admission policies, WAF | — | [SI-10](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-10-information-input-validation) |
| SI-11 | Error Handling | Ten | Part | Custom router error pages | — | [SI-11](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-11-error-handling) |
| SI-16 | Memory Protection | RH | Full | NX, ASLR, kernel hardening | CO | [SI-16](../04-itsg33-configuration/controls/si-system-and-information-integrity.md#si-16-memory-protection) |

## Operational and management families

See [operational and management families](../04-itsg33-configuration/controls/operational-and-management-families.md) for
AT, MA, MP, PE, PL, PM, and PS.
