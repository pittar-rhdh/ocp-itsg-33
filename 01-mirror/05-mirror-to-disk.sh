#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 05-mirror-to-disk.sh: mirror the content in imageset-config.yaml to local disk
# with oc-mirror v2 (mirror-to-disk workflow).
#
#   Output: ${MIRROR_ARCHIVE_DIR}/mirror_*.tar   (to be packaged and transferred)
#           ${MIRROR_ARCHIVE_DIR}/working-dir/   (history; keep for incremental runs)
#           ${MIRROR_CACHE_DIR}/                 (blob cache; back it up after each run)
#
# The first run mirrors everything. Later runs only add content that is new
# since the previous successful run (or since --since <yyyy-mm-dd>).
#
# Usage: 05-mirror-to-disk.sh [--dry-run] [--since yyyy-mm-dd]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd oc-mirror sha256sum

DRY_RUN=false
EXTRA_ARGS=()
while (($# > 0)); do
  case "$1" in
    --dry-run) DRY_RUN=true; EXTRA_ARGS+=(--dry-run) ;;
    --since)   [[ -n "${2:-}" ]] || die "--since needs a date"; EXTRA_ARGS+=(--since "$2"); shift ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

# The committed config must match versions.env.
"${MIRROR_DIR}/04-render-imageset-config.sh" --check

# Don't mix a new run with archives that haven't been packaged yet.
shopt -s nullglob
pending=("${MIRROR_ARCHIVE_DIR}"/mirror_*.tar)
shopt -u nullglob
if ((${#pending[@]} > 0)) && ! ${DRY_RUN}; then
  die "${#pending[@]} archive(s) from a previous run are still in ${MIRROR_ARCHIVE_DIR}; run 07-package-transfer.sh first"
fi

[[ -r "${REGISTRY_AUTH_FILE}" ]] || die "registry auth file not readable: ${REGISTRY_AUTH_FILE}"
mkdir -p "${MIRROR_ARCHIVE_DIR}/logs" "${MIRROR_CACHE_DIR}"

if [[ "${MIRROR_VERIFY_SIGNATURES}" == "true" ]]; then
  policy="${MIRROR_SIGNATURE_POLICY:-${MIRROR_DIR}/signature-policy.json}"
  [[ -r "${policy}" ]] || die "signature policy not readable: ${policy}"
  EXTRA_ARGS+=(--secure-policy=true --policy "${policy}" --registries.d /etc/containers/registries.d)
  log "image signature verification is ON (${policy})"
fi

if [[ -n "${MIRROR_ARCHIVE_SIZE_GB}" ]]; then
  EXTRA_ARGS+=(--strict-archive)
fi

# Red Hat lists umask 0022 as a prerequisite on hosts that run oc-mirror.
umask 0022
RUN_ID="$(stamp)"
LOGFILE="${MIRROR_ARCHIVE_DIR}/logs/mirror-to-disk-${RUN_ID}.log"
log "oc-mirror version: $(oc-mirror --v2 --version 2>/dev/null | head -1 || echo unknown)"
log "mirroring to file://${MIRROR_ARCHIVE_DIR} (log: ${LOGFILE})"

set +e
oc-mirror --v2 \
  --config "${IMAGESET_CONFIG}" \
  --cache-dir "${MIRROR_CACHE_DIR}" \
  --authfile "${REGISTRY_AUTH_FILE}" \
  "${EXTRA_ARGS[@]}" \
  "file://${MIRROR_ARCHIVE_DIR}" 2>&1 | tee "${LOGFILE}"
rc=${PIPESTATUS[0]}
set -e
((rc == 0)) || die "oc-mirror failed (exit ${rc}); see ${LOGFILE}"

if ${DRY_RUN}; then
  log "dry run complete; image lists are under ${MIRROR_ARCHIVE_DIR}/working-dir/dry-run/"
  exit 0
fi

# Record the run for the transfer manifest.
cat >"${MIRROR_ARCHIVE_DIR}/last-run.env" <<EOF
MIRROR_RUN_ID=${RUN_ID}
MIRROR_RUN_FINISHED=$(date -u +%FT%TZ)
MIRROR_RUN_GIT_STATE=$(git_state)
MIRROR_RUN_IMAGESET_SHA256=$(sha256sum "${IMAGESET_CONFIG}" | cut -d' ' -f1)
MIRROR_RUN_LOG=${LOGFILE}
EOF

ls -lh "${MIRROR_ARCHIVE_DIR}"/mirror_*.tar 2>/dev/null || warn "no archives produced (nothing new to mirror?)"
log "done; back up ${MIRROR_CACHE_DIR}, then run 07-package-transfer.sh"
