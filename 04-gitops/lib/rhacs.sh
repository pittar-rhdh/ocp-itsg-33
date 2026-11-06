# shellcheck shell=bash
# -----------------------------------------------------------------------------
# roxctl helpers for the RHACS scripts. Source after lib/common.sh.
# -----------------------------------------------------------------------------

# Sets ROXCTL, ROX_ENDPOINT, ROX_CA (temporary file) and the credentials used
# by roxctl_central. The temporary files are removed on exit.
rhacs_init() {
  local name="roxctl" tmp
  [[ "${OCP_ARCH}" == "amd64" ]] || name="roxctl-${OCP_ARCH}"
  ROXCTL="$(command -v roxctl || true)"
  [[ -n "${ROXCTL}" ]] || ROXCTL="${HS_TOOLS_DIR}/${OCP_MAX_VERSION}/${name}"
  [[ -x "${ROXCTL}" ]] || die "roxctl not found (it comes with the Phase 1 tools when RHACS_VERSION is set)"

  oc get central.platform.stackrox.io -n "${RHACS_NAMESPACE}" >/dev/null 2>&1 \
    || die "no Central in ${RHACS_NAMESPACE} (sync the itsg33-config application first)"

  ROX_ENDPOINT="${ROX_CENTRAL_ADDRESS}"
  if [[ -z "${ROX_ENDPOINT}" ]]; then
    ROX_ENDPOINT="$(oc get route central -n "${RHACS_NAMESPACE}" -o jsonpath='{.spec.host}'):443"
  fi

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" EXIT
  ROX_CA="${tmp}/central-ca.pem"
  oc get secret central-tls -n "${RHACS_NAMESPACE}" -o jsonpath='{.data.ca\.pem}' \
    | base64 -d >"${ROX_CA}"
  [[ -s "${ROX_CA}" ]] || die "could not read the Central CA (secret central-tls, key ca.pem)"

  # roxctl reads ROX_API_TOKEN or ROX_ADMIN_PASSWORD from the environment.
  if [[ -n "${ROX_API_TOKEN_FILE}" ]]; then
    [[ -r "${ROX_API_TOKEN_FILE}" ]] || die "cannot read ${ROX_API_TOKEN_FILE}"
    ROX_API_TOKEN="$(<"${ROX_API_TOKEN_FILE}")"
    export ROX_API_TOKEN
  else
    warn "ROX_API_TOKEN_FILE not set: using the Central admin password (create an API token for routine use)"
    ROX_ADMIN_PASSWORD="$(oc get secret central-htpasswd -n "${RHACS_NAMESPACE}" \
      -o jsonpath='{.data.password}' | base64 -d)"
    [[ -n "${ROX_ADMIN_PASSWORD}" ]] || die "could not read the Central admin password"
    export ROX_ADMIN_PASSWORD
  fi
}

# roxctl against Central, verifying its certificate with the Central CA.
roxctl_central() {
  "${ROXCTL}" -e "${ROX_ENDPOINT}" --ca "${ROX_CA}" "$@"
}
