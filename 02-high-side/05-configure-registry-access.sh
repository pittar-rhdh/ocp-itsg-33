#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 05-configure-registry-access.sh: set up least-privilege access to the mirrored
# content in the MIRROR_NAMESPACE organization (AC-2, AC-3, AC-6, IA-5).
#
#   <org>+importer      robot, member of team "importers" (role: creator).
#                       Pushes content with oc-mirror. Lives only on this host.
#   <org>+cluster_pull  robot, read on every repository in the organization
#                       (default permission for new repositories, plus a
#                       grant on existing ones). Goes into the cluster pull secret.
#
# Writes IMPORTER_AUTH_FILE and CLUSTER_PULL_SECRET_FILE (mode 0600) and checks
# that each credential works.
#
# Prerequisites (one-time, in the registry web UI as QUAY_ADMIN_USER):
#   1. Create the organization MIRROR_NAMESPACE.
#   2. In it, create an OAuth application and generate a token with the
#      "Administer Organization" and "Administer Repositories" scopes.
#   3. Save the token in QUAY_OAUTH_TOKEN_FILE (mode 0600). Delete the token
#      (and file) after this script succeeds; re-create it when needed.
#
# Idempotent: re-run it after each import to grant read on new repositories
# that were created before the default permission existed.
#
# Usage: 05-configure-registry-access.sh [--rotate <importer|cluster_pull>]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd curl jq base64

ROTATE=""
if [[ "${1:-}" == "--rotate" ]]; then
  ROTATE="${2:-}"
  [[ "${ROTATE}" == "${IMPORTER_ROBOT}" || "${ROTATE}" == "${CLUSTER_PULL_ROBOT}" ]] \
    || die "--rotate needs '${IMPORTER_ROBOT}' or '${CLUSTER_PULL_ROBOT}'"
fi

[[ -r "${QUAY_OAUTH_TOKEN_FILE}" ]] || die "OAuth token file not readable: ${QUAY_OAUTH_TOKEN_FILE}"
ORG="${MIRROR_NAMESPACE}"
API="https://$(registry_endpoint)/api/v1"
TEAM="importers"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
chmod 0700 "${WORK}"
# Keep the token out of the process list: curl reads the header from a file.
printf 'Authorization: Bearer %s\n' "$(head -n1 "${QUAY_OAUTH_TOKEN_FILE}")" >"${WORK}/auth.hdr"

# api METHOD PATH [JSON-BODY]: sets HTTP_CODE; the response body is in ${WORK}/resp.
# (Not called in a subshell, so HTTP_CODE stays visible to the caller.)
api() {
  local method="$1" path="$2" body="${3:-}" args=()
  if [[ -n "${body}" ]]; then args=(-H 'Content-Type: application/json' --data "${body}"); fi
  HTTP_CODE="$(curl -sS -o "${WORK}/resp" -w '%{http_code}' --cacert "${TLS_CA_BUNDLE}" \
    -H @"${WORK}/auth.hdr" -X "${method}" "${args[@]}" "${API}${path}")"
}
resp() { cat "${WORK}/resp"; }

expect() {
  local what="$1"; shift
  local c
  for c in "$@"; do [[ "${HTTP_CODE}" == "${c}" ]] && return 0; done
  die "${what}: HTTP ${HTTP_CODE}: $(head -c 300 "${WORK}/resp")"
}

# --- Organization ---------------------------------------------------------------------
api GET "/organization/${ORG}"
expect "organization '${ORG}' (create it in the UI first; check the token scopes)" 200
log "organization ${ORG} found"

# --- Robots -------------------------------------------------------------------------------
# robot_token SHORTNAME DESCRIPTION: ensure the robot exists; sets ROBOT_TOKEN.
robot_token() {
  local short="$1" desc="$2"
  if [[ "${ROTATE}" == "${short}" ]]; then
    api POST "/organization/${ORG}/robots/${short}/regenerate"
    expect "regenerate robot ${ORG}+${short}" 200
    log "regenerated token for ${ORG}+${short}"
  else
    api GET "/organization/${ORG}/robots/${short}"
    if [[ "${HTTP_CODE}" != "200" ]]; then
      api PUT "/organization/${ORG}/robots/${short}" "$(jq -nc --arg d "${desc}" '{description:$d}')"
      expect "create robot ${ORG}+${short}" 200 201
      log "created robot ${ORG}+${short}"
    fi
  fi
  ROBOT_TOKEN="$(resp | jq -r '.token // empty')"
}

robot_token "${IMPORTER_ROBOT}" "oc-mirror disk-to-mirror on $(uname -n); push only"
IMPORTER_TOKEN="${ROBOT_TOKEN}"
robot_token "${CLUSTER_PULL_ROBOT}" "OpenShift cluster pull secret; read only"
PULL_TOKEN="${ROBOT_TOKEN}"
[[ -n "${IMPORTER_TOKEN}" && -n "${PULL_TOKEN}" ]] || die "could not read robot tokens"

# --- Importer team (create repositories, write) ------------------------------------------
api PUT "/organization/${ORG}/team/${TEAM}" \
  '{"role":"creator","description":"Robots that import mirrored content"}'
expect "team ${TEAM}" 200
api PUT "/organization/${ORG}/team/${TEAM}/members/${ORG}+${IMPORTER_ROBOT}"
expect "add ${ORG}+${IMPORTER_ROBOT} to ${TEAM}" 200
log "team ${TEAM} (creator) contains ${ORG}+${IMPORTER_ROBOT}"

# --- Default permission: cluster_pull reads every new repository --------------------------
api GET "/organization/${ORG}/prototypes"
expect "list default permissions" 200
protos="$(resp)"
if jq -e --arg n "${ORG}+${CLUSTER_PULL_ROBOT}" \
     '.prototypes[] | select(.delegate.name == $n and .role == "read" and (.activating_user == null))' \
     <<<"${protos}" >/dev/null; then
  log "default permission (read for ${ORG}+${CLUSTER_PULL_ROBOT}) already exists"
else
  api POST "/organization/${ORG}/prototypes" \
    "$(jq -nc --arg n "${ORG}+${CLUSTER_PULL_ROBOT}" '{role:"read", delegate:{name:$n, kind:"user"}}')"
  expect "create default permission" 200 201
  log "created default permission: read for ${ORG}+${CLUSTER_PULL_ROBOT} on new repositories"
fi

# --- Existing repositories ------------------------------------------------------------------
granted=0 next=""
while :; do
  api GET "/repository?namespace=${ORG}${next:+&next_page=${next}}"
  expect "list repositories" 200
  page="$(resp)"
  while IFS= read -r repo; do
    [[ -n "${repo}" ]] || continue
    api PUT "/repository/${ORG}/${repo}/permissions/user/${ORG}+${CLUSTER_PULL_ROBOT}" '{"role":"read"}'
    expect "grant read on ${ORG}/${repo}" 200
    granted=$((granted + 1))
  done < <(jq -r '.repositories[].name' <<<"${page}")
  next="$(jq -r '.next_page // empty' <<<"${page}")"
  [[ -n "${next}" ]] || break
done
log "read for ${ORG}+${CLUSTER_PULL_ROBOT} confirmed on ${granted} existing repositories"

# --- Credential files ------------------------------------------------------------------------
write_auth() {
  local file="$1" user="$2" token="$3"
  mkdir -p "$(dirname "${file}")"
  chmod 0700 "$(dirname "${file}")"
  ( umask 077
    jq -n --arg r "$(registry_endpoint)" --arg a "$(printf '%s:%s' "${user}" "${token}" | base64 -w0)" \
      '{auths: {($r): {auth: $a}}}' >"${file}" )
  # Check the credential against the registry token endpoint.
  printf 'user = "%s:%s"\n' "${user}" "${token}" >"${WORK}/curl.cfg"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --cacert "${TLS_CA_BUNDLE}" -K "${WORK}/curl.cfg" \
    "https://$(registry_endpoint)/v2/auth?service=${REGISTRY_FQDN}&scope=repository:${ORG}/x:pull")"
  rm -f "${WORK}/curl.cfg"
  [[ "${code}" == "200" ]] || die "credential for ${user} was rejected (HTTP ${code})"
  log "wrote ${file} (credential verified)"
}
write_auth "${IMPORTER_AUTH_FILE}" "${ORG}+${IMPORTER_ROBOT}" "${IMPORTER_TOKEN}"
write_auth "${CLUSTER_PULL_SECRET_FILE}" "${ORG}+${CLUSTER_PULL_ROBOT}" "${PULL_TOKEN}"

warn "delete the OAuth token in the UI and remove ${QUAY_OAUTH_TOKEN_FILE} when you are done"
