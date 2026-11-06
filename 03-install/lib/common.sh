# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Helpers for the Phase 3 (bare-metal IPI install) scripts. Source, don't execute.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/../../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

INSTALL_SRC="${REPO_ROOT}/03-install"
load_settings "${INSTALL_SRC}/settings.env"

# Phase 2 hand-off files (used by the scripts that source this file).
# shellcheck disable=SC2034
{
  RELEASE_ENV="${INPUTS_DIR}/release.env"
  INSTALLER="${INPUTS_DIR}/openshift-install-fips"
  IDMS_FILE="${INPUTS_DIR}/idms-oc-mirror.yaml"
  PULL_SECRET_FILE="${INPUTS_DIR}/cluster-pull-secret.json"
  CA_BUNDLE_FILE="${INPUTS_DIR}/ca-bundle.crt"
}

# Tools from the inputs directory first (oc, butane), then the system PATH.
PATH="${INPUTS_DIR}:${PATH}"
export PATH

# Load release.env written by 02-high-side/07-extract-installer.sh.
load_release() {
  [[ -r "${RELEASE_ENV}" ]] || die "not found: ${RELEASE_ENV} (copy the Phase 2 hand-off into ${INPUTS_DIR})"
  # shellcheck source=/dev/null
  source "${RELEASE_ENV}"
  [[ -n "${OCP_RELEASE_DIGEST:-}" && -n "${OCP_INSTALLER_SHA256:-}" ]] || die "release.env is incomplete"
}

# Python with PyYAML is used to read and check YAML (RHEL 9: python3-pyyaml).
require_pyyaml() {
  python3 -c 'import yaml' 2>/dev/null || die "python3 with PyYAML is required (dnf install python3-pyyaml)"
}

# Print "name<TAB>role<TAB>bmc-address" for each host in HOSTS_FILE.
list_hosts() {
  python3 - "${HOSTS_FILE}" <<'PY'
import sys, yaml
hosts = yaml.safe_load(open(sys.argv[1]))
if not isinstance(hosts, list):
    sys.exit("hosts file must be a YAML list of hosts")
for h in hosts:
    print("\t".join([h.get("name", ""), h.get("role", ""), (h.get("bmc") or {}).get("address", "")]))
PY
}

# Shell-safe variable suffix for a host name: openshift-master-0 -> OPENSHIFT_MASTER_0
host_var() { local n="${1^^}"; echo "${n//[^A-Z0-9]/_}"; }

# Record a file in the evidence directory with its checksum.
keep_evidence() {
  local src="$1" name="${2:-$(basename "$1")}"
  mkdir -p "${EVIDENCE_DIR}"
  cp "${src}" "${EVIDENCE_DIR}/${name}"
  ( cd "${EVIDENCE_DIR}" && sha256sum "${name}" >>SHA256SUMS )
}
