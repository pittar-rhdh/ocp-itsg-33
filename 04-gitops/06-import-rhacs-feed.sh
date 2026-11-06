#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 06-import-rhacs-feed.sh: upload the offline vulnerability data staged by
# 02-high-side/01-accept-transfer.sh (HS_RHACS_DIR) to RHACS Central
# (RA-5, RA-5(2), SI-5).
#
# Red Hat asks for new definitions at least once a day in offline mode. The
# newest staged file is uploaded; a file older than RHACS_FEED_MAX_AGE_DAYS
# is uploaded with a warning, because scans are then missing recent CVEs.
# Each upload is recorded in the Phase 2 import ledger (event rhacs-imported)
# and the uploaded file is moved to HS_RHACS_DIR/imported.
#
# Usage: 06-import-rhacs-feed.sh [file.zip]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=SCRIPTDIR/lib/rhacs.sh
source "${GITOPS_DIR}/lib/rhacs.sh"

: "${RHACS_FEED_MAX_AGE_DAYS:=2}"

feed="${1:-}"
if [[ -z "${feed}" ]]; then
  feed="$(find "${HS_RHACS_DIR}" -maxdepth 1 -name '*.zip' -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -1 | cut -d' ' -f2-)"
fi
[[ -n "${feed}" && -r "${feed}" ]] || die "no vulnerability data file in ${HS_RHACS_DIR} (import a transfer first)"

# The file name carries the RHACS version (Phase 1: scanner-vuln-updates-<ver>-<date>.zip).
if [[ -n "${RHACS_VERSION}" && "$(basename "${feed}")" != *"-${RHACS_VERSION}-"* ]]; then
  warn "$(basename "${feed}") does not match RHACS_VERSION ${RHACS_VERSION}"
fi
age_days=$(( ( $(date +%s) - $(stat -c %Y "${feed}") ) / 86400 ))
((age_days <= RHACS_FEED_MAX_AGE_DAYS)) \
  || warn "$(basename "${feed}") is ${age_days} days old (target: ${RHACS_FEED_MAX_AGE_DAYS})"

use_cluster_oc
require_cluster_admin
rhacs_init

digest="$(sha256sum "${feed}" | awk '{print $1}')"
log "uploading $(basename "${feed}") (sha256 ${digest}) to ${ROX_ENDPOINT}"
roxctl_central scanner upload-db --scanner-db-file="${feed}"

ledger_add "rhacs-$(date -u +%Y%m%d)" rhacs-imported "${digest}" "$(basename "${feed}")"
mkdir -p "${HS_RHACS_DIR}/imported"
mv "${feed}" "${HS_RHACS_DIR}/imported/"
log "vulnerability data imported; recorded in ${HS_LEDGER}"
