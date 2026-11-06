#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 05-install-cluster.sh: run the bare-metal IPI installation. EXAMPLE, not validated.
#
# Before running:
#   - 01-check-provisioner.sh and 02-validate-environment.sh pass
#   - all cluster nodes are powered off (Red Hat's procedure)
#   - no bootstrap VM is left from an earlier attempt (see the docs)
#   - the change is approved and an installation window is open (CM-3)
#
# After the install, auth/kubeconfig and auth/kubeadmin-password are the
# break-glass credentials: seal them in the departmental vault (AC-2, AC-6(9)).
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd virsh sha256sum

load_release
[[ -d "${INSTALL_DIR}/manifests" ]] || die "no manifests in ${INSTALL_DIR}; run 04-create-manifests.sh"
[[ "$(sha256sum "${INSTALLER}" | cut -d' ' -f1)" == "${OCP_INSTALLER_SHA256}" ]] || die "installer checksum mismatch"
if [[ "${FIPS}" == "true" && "$(cat /proc/sys/crypto/fips_enabled 2>/dev/null)" != "1" ]]; then
  die "this host is not in FIPS mode; a FIPS cluster must be installed from a FIPS-enabled RHEL host"
fi
if virsh -c qemu:///system list --all --name 2>/dev/null | grep -q bootstrap; then
  die "a bootstrap VM from an earlier attempt exists; clean it up first (see the docs)"
fi

LOG="${EVIDENCE_DIR}/install-$(stamp).log"
mkdir -p "${EVIDENCE_DIR}"
log "installing ${CLUSTER_NAME}.${BASE_DOMAIN} (${OCP_RELEASE_VERSION}, ${OCP_RELEASE_DIGEST})"
log "this takes a long time; follow ${INSTALL_DIR}/.openshift_install.log for detail"

set +e
"${INSTALLER}" create cluster --dir "${INSTALL_DIR}" --log-level info 2>&1 | tee "${LOG}"
rc=${PIPESTATUS[0]}
set -e
chmod 0600 "${LOG}"
keep_evidence "${INSTALL_DIR}/.openshift_install.log" "openshift_install-$(stamp).log" 2>/dev/null || true
chmod 0600 "${EVIDENCE_DIR}"/openshift_install-*.log 2>/dev/null || true

if ((rc != 0)); then
  warn "the installer exited with ${rc}. If only the final wait timed out, continue with:"
  warn "  ${INSTALLER} wait-for install-complete --dir ${INSTALL_DIR} --log-level debug"
  warn "Gather data: ${INSTALLER} gather bootstrap --dir ${INSTALL_DIR}"
  die "installation did not complete"
fi

chmod 0600 "${INSTALL_DIR}/auth/"*
log "installation complete"
log "BREAK-GLASS: seal ${INSTALL_DIR}/auth/kubeconfig and auth/kubeadmin-password in the vault now,"
log "then remove them from this host after the identity provider is configured (Phase 4)."
log "next: KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig 06-post-install.sh"
