# 05-evidence — Phase 5: Compliance Reporting and Evidence

> **Examples only — not validated.** These files show what the Phase 5 records should look like.
> They have not been used with a real cluster or SA&A process. Review and adapt them to the
> departmental templates before use. The CSV files have no header note so that they stay valid
> CSV; this README is their note.

The commands that produce and use these files are in the documentation:
[Phase 5 — Compliance and evidence](../docs/05-compliance-evidence/index.md).

| File | Purpose |
|---|---|
| `evidence-bundle-index.md` | Template for the `README.md` at the top of every evidence bundle: metadata, the artifact-to-control table, integrity and signature details. Copy it into each bundle and fill it in. |
| `srtm-example.csv` | Example rows of the Security Requirements Traceability Matrix for `ocp1`: responsibility, inheritance, implementation, configuration in Git, automated check, evidence location in the bundle, frequency, owner, status. Representative controls only; build the full SRTM from the departmental template. |
| `poam-example.csv` | Example Plan of Action and Milestones rows (CA-5) for findings from the Compliance Operator, ACM, RHACS, and the File Integrity Operator. |

Completed bundles, SRTMs, and POA&Ms are **Protected B** and are never committed to this
repository. They live in the departmental evidence store.
