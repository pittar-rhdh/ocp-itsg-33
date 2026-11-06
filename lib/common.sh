# shellcheck shell=bash
# -----------------------------------------------------------------------------
# EXAMPLE CODE, NOT VALIDATED: the scripts in this repository are examples and
# have not been run against a real Red Hat subscription, air-gapped environment,
# or cluster. Review and test before use (docs/reference/validation-status.md).
#
# Generic helpers shared by the scripts of every phase. Source, don't execute.
# Phase-specific libraries (for example 01-mirror/lib/common.sh) source this
# file and then load their own settings.
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=SCRIPTDIR/../versions.env
source "${REPO_ROOT}/versions.env"

log()  { printf '%s [INFO]  %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
warn() { printf '%s [WARN]  %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die()  { printf '%s [ERROR] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; exit 1; }

require_cmd() {
  local c missing=()
  for c in "$@"; do command -v "${c}" >/dev/null 2>&1 || missing+=("${c}"); done
  ((${#missing[@]} == 0)) || die "missing required command(s): ${missing[*]}"
}

# Timestamp used in file names (UTC, sortable).
stamp() { date -u +%Y%m%dT%H%M%SZ; }

# Map the OpenShift architecture name to the name used on mirror.openshift.com
# and in release image tags.
arch_dir() {
  case "${OCP_ARCH}" in
    amd64)   echo x86_64 ;;
    arm64)   echo aarch64 ;;
    ppc64le) echo ppc64le ;;
    s390x)   echo s390x ;;
    *) die "unsupported OCP_ARCH: ${OCP_ARCH}" ;;
  esac
}

# Short git description of the repository state, for records.
git_state() {
  local commit dirty=""
  commit="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
  if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null)" ]]; then dirty="-dirty"; fi
  echo "${commit}${dirty}"
}

# Load a settings file and its optional *.local.env override next to it.
# Precedence: exported environment variables > *.local.env > defaults.
# Settings files only assign defaults (': "${VAR:=default}"'), so the override
# is read first and defaults derived from it (for example, paths under
# MIRROR_BASE) follow automatically.
load_settings() {
  local file="$1" local_file="${1%.env}.local.env" _n
  local -A _keep=()
  if [[ -f "${local_file}" ]]; then
    # Remember exported values of the variables the override file assigns...
    while IFS= read -r _n; do
      if [[ "$(declare -p "${_n}" 2>/dev/null)" == "declare -x"* ]]; then _keep["${_n}"]="${!_n}"; fi
    done < <(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' "${local_file}")
    # shellcheck source=/dev/null
    source "${local_file}"
    # ...and put them back, so the environment wins over the file.
    for _n in "${!_keep[@]}"; do
      printf -v "${_n}" '%s' "${_keep[${_n}]}"
      export "${_n?}"
    done
  fi
  # shellcheck source=/dev/null
  source "${file}"
}
