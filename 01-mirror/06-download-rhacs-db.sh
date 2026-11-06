#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 06-download-rhacs-db.sh: download the RHACS offline vulnerability database for
# RHACS_VERSION, for import into RHACS Central on the high side (RA-5(2), SI-5).
#
# Run it on the vulnerability-feed cadence (Red Hat's RHACS offline-mode guidance
# is at least once per day), not only with platform imports. The file goes into the next transfer package.
#
# Usage: 06-download-rhacs-db.sh
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd sha256sum

[[ -n "${RHACS_VERSION}" ]] || die "set RHACS_VERSION in versions.env first"

ROXCTL="$(command -v roxctl || true)"
if [[ -z "${ROXCTL}" ]]; then
  [[ "${OCP_ARCH}" == "amd64" ]] && name="roxctl" || name="roxctl-${OCP_ARCH}"
  ROXCTL="${MIRROR_TOOLS_DIR}/${OCP_MAX_VERSION}/${name}"
fi
[[ -x "${ROXCTL}" ]] || die "roxctl not found; run 01-download-tools.sh"

mkdir -p "${MIRROR_RHACS_DIR}"
OUT="${MIRROR_RHACS_DIR}/scanner-vuln-updates-${RHACS_VERSION}-$(date -u +%Y%m%d).zip"

log "downloading offline vulnerability data for RHACS ${RHACS_VERSION}"
"${ROXCTL}" scanner download-db \
  --version "${RHACS_VERSION}" \
  --skip-central \
  --force \
  --scanner-db-file "${OUT}"

sha256sum "${OUT}" | tee "${OUT}.sha256"
log "saved ${OUT}; it is picked up by the next 07-package-transfer.sh run"
