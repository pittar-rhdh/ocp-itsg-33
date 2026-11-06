# 01-mirror — Phase 1: Content Mirroring (Low Side)

> **Examples only — not validated.** These files show what the Phase 1 configuration and records
> should look like. They have not been used against a real Red Hat subscription or air-gapped
> environment. Review and adapt them before use.

The commands that use these files are in the documentation:
[Phase 1 — Content mirroring](../docs/01-mirroring/index.md).

| File | Purpose |
|---|---|
| `imageset-config.yaml` | Example `ImageSetConfiguration` for `oc-mirror` v2: the reviewed source of truth for what is mirrored. Used for mirror-to-disk (low side) and disk-to-mirror (high side). Change it only through a reviewed pull request. |
| `signature-policy.json` | Optional image signature policy for `oc-mirror --secure-policy`: requires a Red Hat signature for images from `registry.redhat.io` and `registry.access.redhat.com` |
| `transfer-record.md` | Chain-of-custody record template, one per transfer |
