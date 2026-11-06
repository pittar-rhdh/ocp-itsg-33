#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 04-harden-mirror-registry.sh: apply and verify the security settings that the
# mirror registry installer leaves at permissive defaults.
#
#   FEATURE_USER_CREATION: false      no self-registration (AC-2)
#   FEATURE_ANONYMOUS_ACCESS: false   every pull is authenticated (AC-3, AC-14)
#   FEATURE_REPO_MIRROR: false        no outbound repository mirroring (CM-7)
#   SUPER_USERS: [QUAY_ADMIN_USER]    the default lists an unused "admin" name (AC-6)
#   SSL_PROTOCOLS: TLSv1.2, TLSv1.3   (SC-8, SC-13, ITSP.40.062)
#
# Idempotent. Re-run after every mirror registry upgrade, and as a periodic
# configuration check. Restarts the registry only when something changed.
#
# Usage: 04-harden-mirror-registry.sh [--check] [--rotate-cert]
#   --check        report drift without changing anything (exit 1 on drift)
#   --rotate-cert  install TLS_CERT/TLS_KEY as the serving certificate
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd curl openssl sha256sum awk

CHECK_ONLY=false
ROTATE=false
for a in "$@"; do
  case "${a}" in
    --check) CHECK_ONLY=true ;;
    --rotate-cert) ROTATE=true ;;
    *) die "unknown argument: ${a}" ;;
  esac
done

CONF_DIR="${QUAY_ROOT}/quay-config"
CONFIG="${CONF_DIR}/config.yaml"
[[ -f "${CONFIG}" ]] || die "not found: ${CONFIG}"

# Desired top-level settings. Values are written verbatim as YAML.
declare -A WANT=(
  [FEATURE_USER_CREATION]="false"
  [FEATURE_ANONYMOUS_ACCESS]="false"
  [FEATURE_REPO_MIRROR]="false"
  [SUPER_USERS]="[${QUAY_ADMIN_USER}]"
  [SSL_PROTOCOLS]="[TLSv1.2, TLSv1.3]"
)

# Print the value of a top-level key on one line, normalizing a block list
# ("KEY:\n  - a\n  - b") to the flow form "[a, b]".
get_key() {
  awk -v k="$1" '
    $0 ~ "^"k":" { found=1; v=$0; sub("^"k":[ ]*", "", v)
                   if (v != "") { print v; exit } ; inlist=1; next }
    inlist && /^[ ]+- / { i=$0; sub(/^[ ]+- /, "", i); items = items (items ? ", " : "") i; next }
    inlist { exit }
    END { if (inlist) print "[" items "]"; else if (!found) print "<unset>" }
  ' "${CONFIG}"
}

# Replace (or append) a top-level key with a single-line value, removing any
# block-list lines that followed it.
set_key() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp "${CONF_DIR}/.config.XXXXXX")"
  awk -v k="${key}" -v v="${value}" '
    $0 ~ "^"k":" { print k": "v; done=1; skip=1; next }
    skip && /^[ ]+- / { next }
    { skip=0; print }
    END { if (!done) print k": "v }
  ' "${CONFIG}" >"${tmp}"
  chmod --reference="${CONFIG}" "${tmp}"
  mv "${tmp}" "${CONFIG}"
}

drift=0
for k in "${!WANT[@]}"; do
  have="$(get_key "${k}")"
  if [[ "${have}" == "${WANT[${k}]}" ]]; then
    printf '  [OK]    %-26s %s\n' "${k}" "${have}"
  else
    printf '  [DRIFT] %-26s %s (want %s)\n' "${k}" "${have}" "${WANT[${k}]}"
    drift=$((drift + 1))
  fi
done

cert_drift=false
if ! cmp -s "${TLS_CERT}" "${CONF_DIR}/ssl.cert"; then
  printf '  [DRIFT] %-26s serving certificate differs from TLS_CERT\n' "ssl.cert"
  cert_drift=true
fi

if ${CHECK_ONLY} && { ((drift > 0)) || ${cert_drift}; }; then
  die "configuration drift detected"
fi

changed=false
if ((drift > 0)); then
  mkdir -p "${QUAY_BASE}/config-backups"
  backup="${QUAY_BASE}/config-backups/config.yaml.$(stamp)"
  cp -p "${CONFIG}" "${backup}"
  for k in "${!WANT[@]}"; do
    [[ "$(get_key "${k}")" == "${WANT[${k}]}" ]] || set_key "${k}" "${WANT[${k}]}"
  done
  log "updated ${CONFIG} (backup: ${backup})"
  changed=true
fi

if ${ROTATE}; then
  "${HS_DIR}/02-check-registry-host.sh" --tls-only
  mkdir -p "${QUAY_BASE}/config-backups"
  cp -p "${CONF_DIR}/ssl.cert" "${QUAY_BASE}/config-backups/ssl.cert.$(stamp)"
  install -m 0640 "${TLS_CERT}" "${CONF_DIR}/ssl.cert"
  install -m 0600 "${TLS_KEY}" "${CONF_DIR}/ssl.key"
  log "installed new serving certificate"
  changed=true
elif ${cert_drift}; then
  warn "serving certificate differs from TLS_CERT; run with --rotate-cert to install it"
fi

if ${changed}; then
  log "restarting quay-app"
  systemctl --user restart quay-app.service
fi

# --- Verify the running registry ----------------------------------------------------
url="https://$(registry_endpoint)"
log "waiting for ${url}/health/instance"
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --cacert "${TLS_CA_BUNDLE}" "${url}/health/instance" || true)"
  [[ "${code}" == "200" ]] && break
  sleep 10
done
[[ "${code}" == "200" ]] || die "registry is not healthy at ${url} (HTTP ${code:-none}); see: journalctl --user -u quay-app"
log "registry healthy; TLS verified against ${TLS_CA_BUNDLE}"

code="$(curl -s -o /dev/null -w '%{http_code}' --cacert "${TLS_CA_BUNDLE}" "${url}/v2/_catalog")"
[[ "${code}" == "401" ]] || die "anonymous request to /v2/_catalog returned ${code}; expected 401"
log "anonymous access is refused (401)"

for proto in tls1_2 tls1_3; do
  if openssl s_client -connect "$(registry_endpoint)" -servername "${REGISTRY_FQDN}" "-${proto}" \
       -CAfile "${TLS_CA_BUNDLE}" -verify_return_error </dev/null >/dev/null 2>&1; then
    log "${proto//_/.} handshake OK"
  else
    warn "${proto//_/.} handshake failed"
  fi
done

record="${QUAY_BASE}/hardening.log"
printf '%s\t%s\tconfig.yaml=%s\tssl.cert=%s\n' "$(date -u +%FT%TZ)" "$(id -un)" \
  "$(sha256sum "${CONFIG}" | cut -d' ' -f1)" "$(sha256sum "${CONF_DIR}/ssl.cert" | cut -d' ' -f1)" >>"${record}"
log "hardening verified; recorded in ${record}"
