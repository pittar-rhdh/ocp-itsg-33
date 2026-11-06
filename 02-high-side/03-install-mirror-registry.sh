#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 03-install-mirror-registry.sh: install (or upgrade) the mirror registry for
# Red Hat OpenShift on this host, rootless, with the departmental certificate,
# then apply the hardening in 04-harden-mirror-registry.sh.
#
# Run as the unprivileged registry service account (not root). The installer
# uses Ansible over SSH to localhost with a key it generates
# (~/.ssh/quay_installer), so sshd must accept key logins for this account from
# localhost during the install.
#
# Usage: 03-install-mirror-registry.sh [--upgrade]
#   --upgrade   upgrade an existing installation to MIRROR_REGISTRY_VERSION
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd tar podman curl sed

MODE=install
[[ "${1:-}" == "--upgrade" ]] && MODE=upgrade
(($(id -u) != 0)) || die "run as the registry service account, not root"

TARBALL="${HS_TOOLS_DIR}/${OCP_MAX_VERSION}/mirror-registry-${OCP_ARCH}.tar.gz"
[[ -f "${TARBALL}" ]] || die "not found: ${TARBALL} (accept a transfer that includes tools)"

# The certificate must be right before the installer embeds it.
"${HS_DIR}/02-check-registry-host.sh" --tls-only

installed=false
if systemctl --user cat quay-app.service >/dev/null 2>&1; then installed=true; fi
if [[ "${MODE}" == "install" ]] && ${installed}; then
  die "the mirror registry is already installed; use --upgrade, or uninstall deliberately first"
fi
if [[ "${MODE}" == "upgrade" ]] && ! ${installed}; then
  die "no existing installation found (quay-app.service); run without --upgrade"
fi

WORK="${QUAY_BASE}/installer-${MIRROR_REGISTRY_VERSION}"
mkdir -p "${WORK}" "${QUAY_ROOT}" "${QUAY_STORAGE}" "${QUAY_SQLITE}"
chmod 0750 "${QUAY_BASE}" "${QUAY_ROOT}"
log "extracting ${TARBALL} into ${WORK}"
tar -xzf "${TARBALL}" -C "${WORK}"
[[ -x "${WORK}/mirror-registry" ]] || die "mirror-registry binary missing from the tarball"

LOGFILE="${QUAY_BASE}/mirror-registry-${MODE}-$(stamp).log"
args=(
  --quayHostname "$(registry_endpoint)"
  --quayRoot "${QUAY_ROOT}"
  --quayStorage "${QUAY_STORAGE}"
  --sqliteStorage "${QUAY_SQLITE}"
  --sslCert "${TLS_CERT}"
  --sslKey "${TLS_KEY}"
  --no-color
)

secret=""
if [[ "${MODE}" == "install" ]]; then
  [[ -r "${QUAY_ADMIN_PASSWORD_FILE}" ]] || die "password file not readable: ${QUAY_ADMIN_PASSWORD_FILE}"
  perms="$(stat -c '%a' "${QUAY_ADMIN_PASSWORD_FILE}")"
  [[ "${perms}" =~ ^[46]00$ ]] || die "${QUAY_ADMIN_PASSWORD_FILE} must be mode 0600 (is ${perms})"
  secret="$(head -n1 "${QUAY_ADMIN_PASSWORD_FILE}")"
  [[ ${#secret} -ge 12 && "${secret}" != *[[:space:]]* ]] \
    || die "administrator password must be at least 12 characters with no whitespace"
  # Note: the installer takes the password as an argument, so it is briefly
  # visible in the process list. Install from a host with no other users logged in.
  args+=(--initUser "${QUAY_ADMIN_USER}" --initPassword "${secret}")
fi

log "running mirror-registry ${MODE} (${MIRROR_REGISTRY_VERSION}); log: ${LOGFILE}"
set +e
( cd "${WORK}" && ./mirror-registry "${MODE}" "${args[@]}" ) 2>&1 \
  | if [[ -n "${secret}" ]]; then sed -u "s/${secret//\//\\/}/********/g"; else cat; fi \
  | tee "${LOGFILE}"
rc=${PIPESTATUS[0]}
set -e
unset secret
chmod 0600 "${LOGFILE}"
((rc == 0)) || die "mirror-registry ${MODE} failed (exit ${rc}); see ${LOGFILE}"

ensure_registry_trust
log "installed; applying hardening"
"${HS_DIR}/04-harden-mirror-registry.sh"

log "next: create the '${MIRROR_NAMESPACE}' organization and an OAuth token, then run 05-configure-registry-access.sh"
