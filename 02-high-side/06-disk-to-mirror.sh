#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 06-disk-to-mirror.sh: upload an accepted transfer's archives into the mirror
# registry with oc-mirror v2 (disk-to-mirror), and keep the generated cluster
# resources for this import.
#
#   ${HS_WORKSPACE}/                       oc-mirror workspace (keep; incremental)
#   ${HS_CACHE_DIR}/                       oc-mirror cache (keep; back it up)
#   ${HS_CLUSTER_RESOURCES_DIR}/<ID>/      IDMS, ITMS, CatalogSource, ClusterCatalog,
#                                          UpdateService, release signatures
#   ${HS_CLUSTER_RESOURCES_DIR}/current -> <ID>
#
# Content transfers are deltas: they must be imported in the order they were
# built. The script refuses to import out of order.
#
# Usage: 06-disk-to-mirror.sh <transfer-id> [--dry-run]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd jq sha256sum

ID="${1:-}"
[[ -n "${ID}" ]] || die "usage: $(basename "$0") <transfer-id> [--dry-run]"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

T="$(accepted_transfer "${ID}")"
MANIFEST="${T}/MANIFEST.json"
[[ "$(jq -r .includes.content "${MANIFEST}")" == "true" ]] || die "transfer ${ID} has no mirror content"
if ledger_has "${ID}" imported; then die "transfer ${ID} was already imported"; fi

# --- Ordering ------------------------------------------------------------------------
PREV="$(jq -r '.previousContentTransferId // ""' "${MANIFEST}")"
LAST="$(ledger_last imported)"
accepted_detail="$(awk -F'\t' -v i="${ID}" 'NR > 1 && $2 == i && $3 == "accepted" {d = $6} END {print d}' "${HS_LEDGER}")"
if [[ "${PREV}" != "${LAST}" ]]; then
  if [[ "${accepted_detail}" == *out-of-order=* ]]; then
    warn "importing ${ID} after '${LAST:-<none>}' (built after '${PREV:-<none>}'); accepted out of order"
  else
    die "transfer ${ID} must follow '${PREV:-<none>}', but the last import was '${LAST:-<none>}'"
  fi
fi

# --- Tools, credentials, trust ------------------------------------------------------------
OCP_VER="$(jq -r .versions.ocpMax "${MANIFEST}")"
use_transfer_tools "${OCP_VER}"
[[ -r "${IMPORTER_AUTH_FILE}" ]] || die "importer credentials not found: ${IMPORTER_AUTH_FILE} (run 05-configure-registry-access.sh)"
ensure_registry_trust
ISC="${T}/config/imageset-config.yaml"
[[ -f "${ISC}" ]] || die "transfer has no config/imageset-config.yaml"

# --- Stage archives (hard links when possible; no extra space) ------------------------------
mkdir -p "${HS_WORKSPACE}" "${HS_CACHE_DIR}" "${HS_BASE}/logs"
find "${HS_WORKSPACE}" -maxdepth 1 -name 'mirror_*.tar' -delete
for f in "${T}"/content/mirror_*.tar; do
  [[ -e "${f}" ]] || die "no archives in ${T}/content"
  ln "${f}" "${HS_WORKSPACE}/" 2>/dev/null || cp "${f}" "${HS_WORKSPACE}/"
done

# Red Hat lists umask 0022 as a prerequisite on hosts that run oc-mirror.
umask 0022
DEST="docker://$(registry_endpoint)/${MIRROR_NAMESPACE}"
LOGFILE="${HS_BASE}/logs/disk-to-mirror-${ID}-$(stamp).log"
args=(--v2 --config "${ISC}" --from "file://${HS_WORKSPACE}" --cache-dir "${HS_CACHE_DIR}"
      --authfile "${IMPORTER_AUTH_FILE}")
${DRY_RUN} && args+=(--dry-run)

log "oc-mirror version: $(oc-mirror --v2 --version 2>/dev/null | head -1 || echo unknown)"
log "importing ${ID} into ${DEST} (log: ${LOGFILE})"
set +e
oc-mirror "${args[@]}" "${DEST}" 2>&1 | tee "${LOGFILE}"
rc=${PIPESTATUS[0]}
set -e
if ((rc != 0)); then
  ${DRY_RUN} || ledger_add "${ID}" import-failed - "exit=${rc};log=${LOGFILE}"
  die "oc-mirror failed (exit ${rc}); see ${LOGFILE} and ${HS_WORKSPACE}/working-dir/logs/"
fi
if ${DRY_RUN}; then log "dry run complete"; exit 0; fi

# --- Keep the cluster resources for this import -------------------------------------------------
CR_SRC="${HS_WORKSPACE}/working-dir/cluster-resources"
CR_DST="${HS_CLUSTER_RESOURCES_DIR}/${ID}"
[[ -d "${CR_SRC}" ]] || die "oc-mirror produced no cluster-resources directory"
mkdir -p "${CR_DST}"
cp -a "${CR_SRC}/." "${CR_DST}/"
# shellcheck disable=SC2094  # SHA256SUMS is excluded from the find
( cd "${CR_DST}" && find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | xargs -r -d '\n' sha256sum >SHA256SUMS )
ln -sfn "${ID}" "${HS_CLUSTER_RESOURCES_DIR}/current"
find "${HS_WORKSPACE}" -maxdepth 1 -name 'mirror_*.tar' -delete

log "cluster resources for ${ID}:"
for f in "${CR_DST}"/*; do
  [[ "${f}" == */SHA256SUMS ]] && continue
  printf '    %-40s %s\n' "$(basename "${f}")" \
    "$(grep -m1 -E '^kind:|"kind":' "${f}" 2>/dev/null | sed -E 's/.*kind"?: *"?([A-Za-z]+).*/\1/' || true)"
done

ledger_add "${ID}" imported "$(sha256sum "${T}/SHA256SUMS" | cut -d' ' -f1)" "cluster-resources=${CR_DST}"
log "transfer ${ID} IMPORTED"
log "next (first import): 07-extract-installer.sh; later imports: apply ${CR_DST} to the cluster (Phase 6 SOP)"
