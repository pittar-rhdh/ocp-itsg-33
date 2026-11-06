# Content Transfer Record — {{TRANSFER_ID}}

Keep this record with the change ticket. It is evidence for MP-2, MP-4, MP-5, SA-12, SI-7,
and CM-3. Fields in **bold** were filled in automatically when the package was built;
everything else is completed by hand. Store the signed copy in the departmental records system.

## 1. Package (filled in automatically)

| Field | Value |
|---|---|
| Transfer ID | **{{TRANSFER_ID}}** |
| Built (UTC) | **{{CREATED}}** |
| Built by (user@host) | **{{CREATED_BY}}** |
| Repository commit | **{{GIT_COMMIT}}** |
| OpenShift channel / versions | **{{OCP_CHANNEL}} / {{OCP_MIN_VERSION}} – {{OCP_MAX_VERSION}}** |
| `imageset-config.yaml` SHA-256 | **{{IMAGESET_SHA256}}** |
| Files / total size | **{{FILE_COUNT}} files / {{TOTAL_SIZE}}** |
| `SHA256SUMS` SHA-256 | **{{SUMS_SHA256}}** |
| Signed with key | **{{SIGNING_KEY}}** |

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
| Copied to media and verified by (name, date) — `08-verify-transfer.sh` result | |

| Hand-off | From (name) | To (name) | Date/time | Signature |
|---|---|---|---|---|
| Low side → courier | | | | |
| Courier → high side | | | | |

## 4. Receipt (high side)

| Field | Value |
|---|---|
| Received by (name, date) | |
| Malware scan on receipt (tool, result) | |
| Signature and checksum verification result (`08-verify-transfer.sh`) | |
| `SHA256SUMS` SHA-256 matches section 1 (yes/no) | |
| Imported into the mirror registry (name, date) | |

## 5. Media disposition

| Field | Value |
|---|---|
| Media wiped / returned / destroyed (method per ITSP.40.006) | |
| Done by (name, date) | |
