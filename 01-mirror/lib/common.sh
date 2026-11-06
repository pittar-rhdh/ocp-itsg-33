# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Helpers for the Phase 1 (low side) scripts. Source, don't execute.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/../../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

MIRROR_DIR="${REPO_ROOT}/01-mirror"
# shellcheck disable=SC2034  # used by the scripts that source this file
IMAGESET_CONFIG="${MIRROR_DIR}/imageset-config.yaml"

load_settings "${MIRROR_DIR}/settings.env"

# Split an operator spec "package|channels|minVersion|defaultChannel" into
# OP_NAME, OP_CHANNELS, OP_MINVERSION, OP_DEFAULT_CHANNEL.
parse_operator() {
  local spec="$1"
  IFS='|' read -r OP_NAME OP_CHANNELS OP_MINVERSION OP_DEFAULT_CHANNEL <<<"${spec}"
  OP_NAME="${OP_NAME// /}"
  OP_CHANNELS="${OP_CHANNELS// /}"
  OP_MINVERSION="${OP_MINVERSION// /}"
  OP_DEFAULT_CHANNEL="${OP_DEFAULT_CHANNEL// /}"
  [[ -n "${OP_NAME}" ]] || die "invalid operator spec (empty package): '${spec}'"
}
