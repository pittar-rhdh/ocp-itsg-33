# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Helpers for the Phase 2 (high side) scripts. Source, don't execute.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/../../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

HS_DIR="${REPO_ROOT}/02-high-side"
load_settings "${HS_DIR}/settings.env"

# host:port that clients use for the mirror registry.
registry_endpoint() { echo "${REGISTRY_FQDN}:${REGISTRY_PORT}"; }

# --- Import ledger ------------------------------------------------------------------
# Tab-separated, append-only record of every accepted and imported transfer:
#   time  transfer-id  event  sha256(SHA256SUMS)  user  detail
# events: accepted | imported | import-failed | rhacs-staged
ledger_add() {
  local id="$1" event="$2" digest="${3:--}" detail="${4:--}"
  mkdir -p "$(dirname "${HS_LEDGER}")"
  if [[ ! -f "${HS_LEDGER}" ]]; then
    printf 'time\ttransfer\tevent\tsums_sha256\tuser\tdetail\n' >"${HS_LEDGER}"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "${id}" "${event}" "${digest}" \
    "$(id -un)" "${detail}" >>"${HS_LEDGER}"
}

# Most recent transfer ID with the given event ("" if none).
ledger_last() {
  local event="$1"
  [[ -f "${HS_LEDGER}" ]] || { echo ""; return; }
  awk -F'\t' -v e="${event}" 'NR > 1 && $3 == e {id = $2} END {print id}' "${HS_LEDGER}"
}

ledger_has() {
  local id="$1" event="$2"
  [[ -f "${HS_LEDGER}" ]] && awk -F'\t' -v i="${id}" -v e="${event}" \
    'NR > 1 && $2 == i && $3 == e {found = 1} END {exit !found}' "${HS_LEDGER}"
}

# Path of an accepted transfer; dies if it isn't accepted.
accepted_transfer() {
  local id="$1"
  ledger_has "${id}" accepted || die "transfer ${id} has not been accepted (run 01-accept-transfer.sh)"
  [[ -d "${HS_TRANSFERS_DIR}/${id}" ]] || die "accepted transfer ${id} is missing from ${HS_TRANSFERS_DIR}"
  echo "${HS_TRANSFERS_DIR}/${id}"
}

# Make rootless podman / oc-mirror (containers/image) trust the departmental CA
# for the mirror registry, without needing root.
ensure_registry_trust() {
  local d
  d="${HOME}/.config/containers/certs.d/$(registry_endpoint)"
  mkdir -p "${d}"
  if ! cmp -s "${TLS_CA_BUNDLE}" "${d}/ca.crt"; then
    install -m 0644 "${TLS_CA_BUNDLE}" "${d}/ca.crt"
    log "installed ${TLS_CA_BUNDLE} as ${d}/ca.crt"
  fi
}

# Put oc and oc-mirror from the accepted tools for an OpenShift version
# (default OCP_MAX_VERSION) first on PATH.
use_transfer_tools() {
  local dir="${HS_TOOLS_DIR}/${1:-${OCP_MAX_VERSION}}/bin"
  if [[ -x "${dir}/oc" && -x "${dir}/oc-mirror" ]]; then
    PATH="${dir}:${PATH}"
    export PATH
  fi
  require_cmd oc oc-mirror
}
