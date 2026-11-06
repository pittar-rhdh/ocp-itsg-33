#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 07-package-transfer.sh: assemble everything for one low-to-high transfer into
# a single directory, with a SHA-256 manifest, a detached GPG signature, and a
# pre-filled transfer record.
#
#   ${MIRROR_TRANSFERS_DIR}/<ID>/
#     content/          mirror_*.tar from the last mirror-to-disk run (moved)
#     config/           imageset-config.yaml used for that run (needed for disk-to-mirror),
#                       plus the digest-pinned isc_pinned_*.yaml / disc_pinned_*.yaml
#     tools/            verified binaries for OCP_MAX_VERSION (copied)
#     rhacs/            RHACS offline vulnerability data (moved)
#     repo/             git bundle of this repository
#     logs/             oc-mirror log of the run (evidence)
#     MANIFEST.json     what, who, when, from which commit
#     SHA256SUMS        checksum of every file above
#     SHA256SUMS.asc    detached signature of SHA256SUMS
#     transfer-record.md  chain-of-custody form (not covered by SHA256SUMS; filled in by hand)
#
# Usage: 07-package-transfer.sh [--id ID] [--no-tools] [--no-content]
#   --no-content   package without mirror archives (for example, a RHACS feed or
#                  repository-only transfer)
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd git jq sha256sum gpg du find

ID="T-$(date -u +%Y%m%d-%H%M)"
WITH_TOOLS=true
WITH_CONTENT=true
while (($# > 0)); do
  case "$1" in
    --id)         [[ -n "${2:-}" ]] || die "--id needs a value"; ID="$2"; shift ;;
    --no-tools)   WITH_TOOLS=false ;;
    --no-content) WITH_CONTENT=false ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done
[[ "${ID}" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid transfer ID: ${ID}"

# --- Pre-flight -----------------------------------------------------------------
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" && "${ALLOW_DIRTY_REPO:-false}" != "true" ]]; then
  die "the repository has uncommitted changes; commit them so the transfer matches a known commit"
fi
if [[ -z "${TRANSFER_SIGNING_KEY}" && "${REQUIRE_TRANSFER_SIGNATURE}" == "true" ]]; then
  die "TRANSFER_SIGNING_KEY is not set (set REQUIRE_TRANSFER_SIGNATURE=false only in a lab)"
fi

shopt -s nullglob
archives=("${MIRROR_ARCHIVE_DIR}"/mirror_*.tar)
rhacs_files=("${MIRROR_RHACS_DIR}"/*.zip)
shopt -u nullglob
if ${WITH_CONTENT} && ((${#archives[@]} == 0)); then
  die "no mirror_*.tar in ${MIRROR_ARCHIVE_DIR}; run 05-mirror-to-disk.sh (or use --no-content)"
fi

OUT="${MIRROR_TRANSFERS_DIR}/${ID}"
[[ ! -e "${OUT}" ]] || die "${OUT} already exists"
mkdir -p "${OUT}"/{config,repo,logs}
log "assembling transfer ${ID} in ${OUT}"

# --- Content ---------------------------------------------------------------------
# Content transfers are incremental deltas and must be imported in order. Each
# one records the ID of the content transfer before it; the high side refuses to
# import out of order.
CHAIN_FILE="${MIRROR_TRANSFERS_DIR}/.last-content-transfer"
PREV_CONTENT_ID=""
if [[ -f "${CHAIN_FILE}" ]]; then PREV_CONTENT_ID="$(<"${CHAIN_FILE}")"; fi
MIRROR_RUN_ID="" MIRROR_RUN_IMAGESET_SHA256="" MIRROR_RUN_LOG=""
if ${WITH_CONTENT}; then
  # shellcheck source=/dev/null
  [[ -f "${MIRROR_ARCHIVE_DIR}/last-run.env" ]] && source "${MIRROR_ARCHIVE_DIR}/last-run.env"
  current_isc="$(sha256sum "${IMAGESET_CONFIG}" | cut -d' ' -f1)"
  [[ "${MIRROR_RUN_IMAGESET_SHA256}" == "${current_isc}" ]] \
    || die "no record of the last mirror run, or imageset-config.yaml changed since it; re-run 05-mirror-to-disk.sh"
  mkdir -p "${OUT}/content"
  mv "${archives[@]}" "${OUT}/content/"
  # Pinned copies of the image set (catalogs pinned by digest) and the matching
  # delete config that oc-mirror 4.22 wrote for this run (file names as observed
  # with oc-mirror 4.22; copied only if present).
  for kind in isc disc; do
    pinned="$(find "${MIRROR_ARCHIVE_DIR}/working-dir" -maxdepth 1 -name "${kind}_pinned_*.yaml" \
                -printf '%f\n' 2>/dev/null | LC_ALL=C sort | tail -1)"
    if [[ -n "${pinned}" ]]; then
      # oc-mirror puts ':' in these names; it is invalid on exFAT/NTFS media.
      cp "${MIRROR_ARCHIVE_DIR}/working-dir/${pinned}" "${OUT}/config/${pinned//:/}"
    fi
  done
  [[ -n "${MIRROR_RUN_LOG}" && -f "${MIRROR_RUN_LOG}" ]] && cp "${MIRROR_RUN_LOG}" "${OUT}/logs/"
  rm -f "${MIRROR_ARCHIVE_DIR}/last-run.env"
fi
cp "${IMAGESET_CONFIG}" "${OUT}/config/imageset-config.yaml"

if ${WITH_TOOLS}; then
  if [[ -d "${MIRROR_TOOLS_DIR}/${OCP_MAX_VERSION}" ]]; then
    cp -a "${MIRROR_TOOLS_DIR}/${OCP_MAX_VERSION}" "${OUT}/tools"
  else
    warn "no tools for ${OCP_MAX_VERSION} in ${MIRROR_TOOLS_DIR}; run 01-download-tools.sh"
  fi
fi

if ((${#rhacs_files[@]} > 0)); then
  mkdir -p "${OUT}/rhacs"
  for f in "${rhacs_files[@]}"; do
    mv "${f}" "${OUT}/rhacs/"
    rm -f "${f}.sha256"
  done
fi

# --- Repository ------------------------------------------------------------------
branch="$(git -C "${REPO_ROOT}" symbolic-ref --quiet --short HEAD || echo HEAD)"
git -C "${REPO_ROOT}" bundle create "${OUT}/repo/ocp-itsg-33.bundle" "${branch}" 2>/dev/null
git bundle list-heads "${OUT}/repo/ocp-itsg-33.bundle" >/dev/null || die "git bundle is not readable"

# --- Portable file names ---------------------------------------------------------
bad_names="$(cd "${OUT}" && find . -name '*[:\\*?"<>|]*' -printf '%P\n')"
[[ -z "${bad_names}" ]] || die "file names not portable to exFAT/NTFS media:
${bad_names}"

# --- Manifest --------------------------------------------------------------------
file_count="$(find "${OUT}" -type f | wc -l)"
total_bytes="$(du -sb "${OUT}" | cut -f1)"
jq -n \
  --arg id "${ID}" \
  --arg created "$(date -u +%FT%TZ)" \
  --arg by "$(id -un)@$(uname -n)" \
  --arg commit "$(git_state)" --arg branch "${branch}" \
  --arg ocp_channel "${OCP_CHANNEL}" --arg ocp_min "${OCP_MIN_VERSION}" --arg ocp_max "${OCP_MAX_VERSION}" \
  --arg mirror_registry "${MIRROR_REGISTRY_VERSION}" --arg rhacs "${RHACS_VERSION}" \
  --arg isc "$(sha256sum "${OUT}/config/imageset-config.yaml" | cut -d' ' -f1)" \
  --arg run "${MIRROR_RUN_ID}" --arg prev "${PREV_CONTENT_ID}" \
  --argjson content "${WITH_CONTENT}" --argjson tools "${WITH_TOOLS}" \
  --argjson files "${file_count}" --argjson bytes "${total_bytes}" \
  '{transferId:$id, created:$created, createdBy:$by,
    repository:{commit:$commit, branch:$branch},
    versions:{ocpChannel:$ocp_channel, ocpMin:$ocp_min, ocpMax:$ocp_max,
              mirrorRegistry:$mirror_registry, rhacs:$rhacs},
    imagesetConfigSha256:$isc, mirrorRunId:$run,
    previousContentTransferId:(if $content then $prev else null end),
    includes:{content:$content, tools:$tools},
    files:$files, bytes:$bytes}' >"${OUT}/MANIFEST.json"

# --- Checksums and signature -------------------------------------------------------
# shellcheck disable=SC2094  # SHA256SUMS is excluded from the find
( cd "${OUT}" && find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.asc ! -name transfer-record.md \
    -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum >SHA256SUMS )

signing_key="(unsigned)"
if [[ -n "${TRANSFER_SIGNING_KEY}" ]]; then
  gpg --batch --yes --local-user "${TRANSFER_SIGNING_KEY}" --armor --detach-sign \
    --output "${OUT}/SHA256SUMS.asc" "${OUT}/SHA256SUMS"
  signing_key="$(gpg --list-secret-keys --with-colons "${TRANSFER_SIGNING_KEY}" | awk -F: '/^fpr/ {print $10; exit}')"
  log "signed SHA256SUMS with ${signing_key}"
else
  warn "transfer is NOT signed"
fi

# --- Transfer record ---------------------------------------------------------------
record="$(<"${MIRROR_DIR}/templates/transfer-record.md")"
declare -A fields=(
  [TRANSFER_ID]="${ID}"
  [CREATED]="$(jq -r .created "${OUT}/MANIFEST.json")"
  [CREATED_BY]="$(jq -r .createdBy "${OUT}/MANIFEST.json")"
  [GIT_COMMIT]="$(git_state)"
  [OCP_CHANNEL]="${OCP_CHANNEL}"
  [OCP_MIN_VERSION]="${OCP_MIN_VERSION}"
  [OCP_MAX_VERSION]="${OCP_MAX_VERSION}"
  [IMAGESET_SHA256]="$(jq -r .imagesetConfigSha256 "${OUT}/MANIFEST.json")"
  [FILE_COUNT]="$(wc -l <"${OUT}/SHA256SUMS")"
  [TOTAL_SIZE]="$(du -sh "${OUT}" | cut -f1)"
  [SUMS_SHA256]="$(sha256sum "${OUT}/SHA256SUMS" | cut -d' ' -f1)"
  [SIGNING_KEY]="${signing_key}"
)
for k in "${!fields[@]}"; do record="${record//\{\{${k}\}\}/${fields[${k}]}}"; done
printf '%s\n' "${record}" >"${OUT}/transfer-record.md"

if ${WITH_CONTENT}; then printf '%s\n' "${ID}" >"${CHAIN_FILE}"; fi

log "transfer ${ID} ready: $(du -sh "${OUT}" | cut -f1) in ${OUT}"
log "SHA256SUMS digest (write it on the transfer record): ${fields[SUMS_SHA256]}"
log "next: copy to media, then run 08-verify-transfer.sh against the copy"
