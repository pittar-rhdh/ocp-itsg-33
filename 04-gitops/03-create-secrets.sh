#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 03-create-secrets.sh: create the Secrets and ConfigMaps that the Git
# configuration refers to but that must never be in Git (IA-5, SC-12, SC-28).
#
#   openshift-config/gc-sso-client-secret   IDP_CLIENT_SECRET_FILE   (IA-2, IA-5)
#   openshift-config/gc-sso-ca              IDP_CA_FILE              (IA-2, SC-8)
#   openshift-config/itsg33-login-template  LOGIN_TEMPLATE_FILE      (AC-8)
#   openshift-logging/siem-tls              SIEM_CA/CERT/KEY_FILE    (AU-9, SC-8)
#   openshift-logging/logging-loki-s3       LOKI_S3_ENV_FILE         (AU-9)
#   openshift-adp/cloud-credentials         OADP_CREDENTIALS_FILE    (CP-9)
#
# A secret whose input file is not set or not present is skipped. Secret input
# files must be mode 0600. Values are never printed; the change log records
# the name and the SHA-256 of the input only.
# When the departmental secret store is available, replace these with
# ExternalSecret resources (External Secrets Operator) in Git.
#
# Without --apply, shows what would be created.
# Usage: CHANGE_ID=<ticket> 03-create-secrets.sh [--apply]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

use_cluster_oc
require_cluster_admin
[[ "${APPLY}" == true ]] && require_change_id

# usable <file> <secret:true|false>: the file is set, readable and, for secret
# material, mode 0600.
usable() {
  local f="$1" secret="$2"
  [[ -n "${f}" && -r "${f}" ]] || return 1
  if [[ "${secret}" == true && "$(stat -c %a "${f}")" != "600" ]]; then
    die "${f} holds secret material and must be mode 0600"
  fi
}

sums() { sha256sum "$@" | awk '{print $1}' | paste -sd, -; }

# apply_object <kind/ns/name> <files...> -- <oc create command...>
apply_object() {
  local what="$1"; shift
  local files=()
  while [[ "$1" != "--" ]]; do files+=("$1"); shift; done
  shift
  if [[ "${APPLY}" != true ]]; then log "would create ${what}"; return; fi
  oc get namespace "$(cut -d/ -f2 <<<"${what}")" >/dev/null 2>&1 \
    || { warn "namespace for ${what} does not exist yet (sync the operators first); skipped"; return; }
  "$@" --dry-run=client -o yaml | oc apply -f - >/dev/null
  record_change secret-updated "${what} sha256(input)=$(sums "${files[@]}")"
  log "created/updated ${what}"
}

skip() { log "skipped $1 (input not set or not found)"; }

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

if usable "${IDP_CLIENT_SECRET_FILE}" true; then
  # One line, without the trailing newline (it would become part of the secret).
  tr -d '\r\n' <"${IDP_CLIENT_SECRET_FILE}" >"${TMP}/clientSecret"
  apply_object secret/openshift-config/gc-sso-client-secret "${IDP_CLIENT_SECRET_FILE}" -- \
    oc create secret generic gc-sso-client-secret -n openshift-config \
    --from-file=clientSecret="${TMP}/clientSecret"
else skip gc-sso-client-secret; fi

if usable "${IDP_CA_FILE}" false; then
  apply_object configmap/openshift-config/gc-sso-ca "${IDP_CA_FILE}" -- \
    oc create configmap gc-sso-ca -n openshift-config --from-file=ca.crt="${IDP_CA_FILE}"
else skip gc-sso-ca; fi

if usable "${LOGIN_TEMPLATE_FILE}" false; then
  grep -q '{{' "${LOGIN_TEMPLATE_FILE}" \
    || die "${LOGIN_TEMPLATE_FILE} does not look like a login template (start from: oc adm create-login-template)"
  apply_object secret/openshift-config/itsg33-login-template "${LOGIN_TEMPLATE_FILE}" -- \
    oc create secret generic itsg33-login-template -n openshift-config \
    --from-file=login.html="${LOGIN_TEMPLATE_FILE}"
else skip itsg33-login-template; fi

if usable "${SIEM_CA_FILE}" false && usable "${SIEM_CERT_FILE}" false && usable "${SIEM_KEY_FILE}" true; then
  apply_object secret/openshift-logging/siem-tls "${SIEM_CA_FILE}" "${SIEM_CERT_FILE}" "${SIEM_KEY_FILE}" -- \
    oc create secret generic siem-tls -n openshift-logging \
    --from-file=ca-bundle.crt="${SIEM_CA_FILE}" \
    --from-file=tls.crt="${SIEM_CERT_FILE}" \
    --from-file=tls.key="${SIEM_KEY_FILE}"
else skip siem-tls; fi

if usable "${LOKI_S3_ENV_FILE}" true; then
  for k in access_key_id access_key_secret bucketnames endpoint region; do
    grep -q "^${k}=" "${LOKI_S3_ENV_FILE}" || die "${LOKI_S3_ENV_FILE} has no ${k}="
  done
  apply_object secret/openshift-logging/logging-loki-s3 "${LOKI_S3_ENV_FILE}" -- \
    oc create secret generic logging-loki-s3 -n openshift-logging --from-env-file="${LOKI_S3_ENV_FILE}"
else skip logging-loki-s3; fi

if usable "${OADP_CREDENTIALS_FILE}" true; then
  apply_object secret/openshift-adp/cloud-credentials "${OADP_CREDENTIALS_FILE}" -- \
    oc create secret generic cloud-credentials -n openshift-adp --from-file=cloud="${OADP_CREDENTIALS_FILE}"
else skip cloud-credentials; fi

[[ "${APPLY}" == true ]] || log "dry run: re-run with --apply to create them"
