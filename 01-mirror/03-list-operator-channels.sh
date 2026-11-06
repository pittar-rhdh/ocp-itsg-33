#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 03-list-operator-channels.sh: show what the live catalogs offer, so that
# channels and versions in versions.env can be pinned deliberately.
#
# Writes one report per run to ${MIRROR_REPORTS_DIR}:
#   - available OpenShift releases in OCP_CHANNEL (from the update graph)
#   - for every operator in OPERATORS / CSI_OPERATORS: default channel, channels,
#     and versions, as reported by `oc-mirror list operators --v2`
#
# Usage: 03-list-operator-channels.sh [package ...]
#   With no arguments, every configured package is listed.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd oc-mirror curl jq

mkdir -p "${MIRROR_REPORTS_DIR}"
REPORT="${MIRROR_REPORTS_DIR}/catalog-report-$(stamp).txt"
export REGISTRY_AUTH_FILE

list_pkg() {
  local catalog="$1" pkg="$2"
  printf '\n=== %s  (%s)\n' "${pkg}" "${catalog}"
  oc-mirror list operators --catalog="${catalog}" --package="${pkg}" --v2 2>&1 || echo "(lookup failed)"
}

{
  echo "Catalog report generated $(date -u +%FT%TZ) from versions.env at $(git_state)"
  printf '\n=== OpenShift releases in %s (%s)\n' "${OCP_CHANNEL}" "${OCP_ARCH}"
  curl -fsSL -H 'Accept: application/json' \
    "https://api.openshift.com/api/upgrades_info/v1/graph?channel=${OCP_CHANNEL}&arch=${OCP_ARCH}" \
    | jq -r '.nodes[].version' | sort -V | tail -15
  echo "(configured: min ${OCP_MIN_VERSION}, max ${OCP_MAX_VERSION})"

  if (($# > 0)); then
    for p in "$@"; do list_pkg "${OCP_OPERATOR_CATALOG}" "${p}"; done
  else
    for spec in "${OPERATORS[@]}"; do
      parse_operator "${spec}"; list_pkg "${OCP_OPERATOR_CATALOG}" "${OP_NAME}"
    done
    for spec in "${CSI_OPERATORS[@]}"; do
      parse_operator "${spec}"; list_pkg "${CERTIFIED_OPERATOR_CATALOG}" "${OP_NAME}"
    done
  fi
} | tee "${REPORT}"

log "report saved to ${REPORT}"
