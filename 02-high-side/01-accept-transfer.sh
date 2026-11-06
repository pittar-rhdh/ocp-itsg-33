#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 01-accept-transfer.sh: verify a transfer package on arrival and accept it into
# the high side (SI-7, SA-12, MP-5, CM-3).
#
#   1. Verify signature, checksums, and that nothing was added in transit
#      (01-mirror/08-verify-transfer.sh) on the media.
#   2. Check ordering: a content transfer must follow the last accepted one.
#   3. Copy to ${HS_TRANSFERS_DIR}/<ID>/ and verify the copy again.
#   4. Unpack tools (oc, oc-mirror) for its OpenShift version; stage RHACS data.
#   5. Record "accepted" in the import ledger.
#
# Usage: 01-accept-transfer.sh <transfer-dir-on-media> [--key <public-key>]
#                              [--allow-out-of-order "<reason>"]
#
# First transfer only: this repository isn't on the high side yet. Verify by
# hand first (see docs/02-high-side/accept-transfer.md), clone the bundle, then
# run this script from the clone to accept the same transfer properly.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd jq sha256sum tar cp

SRC="${1:-}"
[[ -n "${SRC}" && -d "${SRC}" ]] || die "usage: $(basename "$0") <transfer-dir> [--key <public-key>] [--allow-out-of-order <reason>]"
shift
OOO_REASON=""
while (($# > 0)); do
  case "$1" in
    --key) [[ -n "${2:-}" ]] || die "--key needs a file"; TRANSFER_VERIFY_KEY="$2"; shift ;;
    --allow-out-of-order) [[ -n "${2:-}" ]] || die "--allow-out-of-order needs a reason"; OOO_REASON="$2"; shift ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done
SRC="$(cd "${SRC}" && pwd)"
VERIFY="${REPO_ROOT}/01-mirror/08-verify-transfer.sh"
export REQUIRE_TRANSFER_SIGNATURE

# --- 1. Verify on the media ------------------------------------------------------
log "verifying ${SRC}"
"${VERIFY}" "${SRC}" --key "${TRANSFER_VERIFY_KEY}"

MANIFEST="${SRC}/MANIFEST.json"
ID="$(jq -r .transferId "${MANIFEST}")"
HAS_CONTENT="$(jq -r .includes.content "${MANIFEST}")"
PREV="$(jq -r '.previousContentTransferId // ""' "${MANIFEST}")"
OCP_VER="$(jq -r .versions.ocpMax "${MANIFEST}")"
DIGEST="$(sha256sum "${SRC}/SHA256SUMS" | cut -d' ' -f1)"
[[ "${ID}" == "$(basename "${SRC}")" ]] || warn "directory name $(basename "${SRC}") differs from transfer ID ${ID}"
[[ "${ID}" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid transfer ID in manifest: ${ID}"
if ledger_has "${ID}" accepted; then die "transfer ${ID} was already accepted"; fi

# --- 2. Ordering -------------------------------------------------------------------
if [[ "${HAS_CONTENT}" == "true" ]]; then
  last_content="$(awk -F'\t' 'NR > 1 && $3 == "accepted" && $6 ~ /^content/ {id = $2} END {print id}' \
    "${HS_LEDGER}" 2>/dev/null || true)"
  if [[ "${PREV}" != "${last_content}" ]]; then
    msg="transfer ${ID} follows '${PREV:-<none>}', but the last accepted content transfer is '${last_content:-<none>}'"
    [[ -n "${OOO_REASON}" ]] || die "${msg}. Import the missing transfer first, or re-baseline (see the docs) and use --allow-out-of-order"
    warn "${msg}; accepting anyway: ${OOO_REASON}"
  fi
fi

# --- 3. Copy and re-verify ------------------------------------------------------------
DEST="${HS_TRANSFERS_DIR}/${ID}"
[[ ! -e "${DEST}" ]] || die "${DEST} already exists"
mkdir -p "${HS_TRANSFERS_DIR}"
log "copying to ${DEST}"
cp -a "${SRC}" "${DEST}.partial"
"${VERIFY}" "${DEST}.partial" --key "${TRANSFER_VERIFY_KEY}" >/dev/null
mv "${DEST}.partial" "${DEST}"
chmod -R go-w "${DEST}"

# --- 4. Tools and RHACS data -------------------------------------------------------------
if [[ -d "${DEST}/tools" ]]; then
  tdir="${HS_TOOLS_DIR}/${OCP_VER}"
  mkdir -p "${tdir}/bin"
  cp -a "${DEST}/tools/." "${tdir}/"
  client="$(find "${tdir}" -maxdepth 1 -name 'openshift-client-linux-*-rhel9-*.tar.gz' -print -quit)"
  [[ -n "${client}" ]] && tar -xzf "${client}" -C "${tdir}/bin" oc kubectl
  [[ -f "${tdir}/oc-mirror.rhel9.tar.gz" ]] && tar -xzf "${tdir}/oc-mirror.rhel9.tar.gz" -C "${tdir}/bin" oc-mirror
  find "${tdir}/bin" -type f -exec chmod 0755 {} +
  log "tools for ${OCP_VER} unpacked into ${tdir}"
fi

if [[ -d "${DEST}/rhacs" ]]; then
  mkdir -p "${HS_RHACS_DIR}"
  for f in "${DEST}"/rhacs/*.zip; do
    [[ -e "${f}" ]] || continue
    cp "${f}" "${HS_RHACS_DIR}/"
    ledger_add "${ID}" rhacs-staged "${DIGEST}" "$(basename "${f}")"
  done
fi

# --- 5. Record ---------------------------------------------------------------------------
detail="nocontent"
if [[ "${HAS_CONTENT}" == "true" ]]; then detail="content;prev=${PREV:-none}"; fi
if [[ -n "${OOO_REASON}" ]]; then detail="${detail};out-of-order=${OOO_REASON//$'\t'/ }"; fi
ledger_add "${ID}" accepted "${DIGEST}" "${detail}"

log "transfer ${ID} ACCEPTED (SHA256SUMS digest ${DIGEST})"
log "complete section 4 of ${SRC}/transfer-record.md; next: 06-disk-to-mirror.sh ${ID}"
