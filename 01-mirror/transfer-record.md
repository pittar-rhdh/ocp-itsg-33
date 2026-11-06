# Content Transfer Record — `<transfer-id>`

> **Example — not validated.** Adapt this template to the departmental records format.

Keep this record with the change ticket. It is evidence for MP-2, MP-4, MP-5, SA-12, SI-7,
and CM-3. Section 1 is completed by the operator who builds the package; the rest is completed as
the package moves. Store the signed copy in the departmental records system.

## 1. Package

| Field | Value |
|---|---|
| Transfer ID | `<transfer-id>` (for example `T-20261106-01`) |
| Previous content transfer ID (ordering) | `<previous-transfer-id>` or `none` |
| Built (UTC) | |
| Built by (user@host) | |
| Repository commit (`git rev-parse HEAD`) | |
| OpenShift channel / versions | `stable-4.22` / `<min>` – `<max>` |
| `imageset-config.yaml` SHA-256 | |
| Files / total size | |
| `SHA256SUMS` SHA-256 (`sha256sum SHA256SUMS`) | |
| Signed with key (fingerprint) | |

## 2. Approval (low side)

| Field | Value |
|---|---|
| Change / ticket number | |
| Purpose (scheduled import, emergency CVE fix, RHACS feed, other) | |
| Content reviewed against approved list (name, date) | |
| Approved for transfer by (name, role, date) | |

## 3. Media and custody

| Field | Value |
|---|---|
| Transfer method (removable media, data diode, CDS) | |
| Media type and serial / asset number | |
| Media classification label | |
| Media scanned for malware (tool, result, date) | |
| Copied to media and verified by (name, date) — signature and checksum result | |

| Hand-off | From (name) | To (name) | Date/time | Signature |
|---|---|---|---|---|
| Low side → courier | | | | |
| Courier → high side | | | | |

## 4. Receipt (high side)

| Field | Value |
|---|---|
| Received by (name, date) | |
| Malware scan on receipt (tool, result) | |
| Signature and checksum verification result | |
| `SHA256SUMS` SHA-256 matches section 1 (yes/no) | |
| Imported into the mirror registry (name, date) | |

## 5. Media disposition

| Field | Value |
|---|---|
| Media wiped / returned / destroyed (method per ITSP.40.006) | |
| Done by (name, date) | |
