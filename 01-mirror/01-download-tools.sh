#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 01-download-tools.sh: download and verify the binaries that go to the high side.
#
#   oc, kubectl       openshift-client-linux-<arch>-rhel9-<OCP_MAX_VERSION>.tar.gz
#   oc-mirror         oc-mirror.rhel9.tar.gz (same release directory)
#   mirror-registry   mirror-registry-<arch>.tar.gz (MIRROR_REGISTRY_VERSION)
#   roxctl            RHACS CLI (RHACS_VERSION, optional)
#   butane            MachineConfig generator (BUTANE_VERSION), used in Phase 3
#
# Integrity (SA-12, SI-7): the OpenShift client and mirror-registry checksum lists
# are verified against the Red Hat release key before any file is trusted. The
# RHACS CLI publishes an unsigned checksum list only; it is checked and recorded.
#
# Usage: 01-download-tools.sh [--install]
#   --install   also extract oc, kubectl, and oc-mirror into ~/.local/bin
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd curl gpg gpgv sha256sum tar

INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

[[ -r "${RH_RELEASE_KEY}" ]] || die "Red Hat release key not found: ${RH_RELEASE_KEY}"

DEST="${MIRROR_TOOLS_DIR}/${OCP_MAX_VERSION}"
mkdir -p "${DEST}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# gpgv needs a binary keyring.
gpg --dearmor <"${RH_RELEASE_KEY}" >"${WORK}/redhat.gpg"

fetch() { curl -fsSL --retry 3 -o "$2" "$1" || die "download failed: $1"; }

# Fetch <base>/sha256sum.txt.gpg (inline-signed), verify it, and write the
# verified checksum list to <out>.
fetch_signed_sums() {
  local base="$1" out="$2"
  fetch "${base}/sha256sum.txt.gpg" "${WORK}/sums.gpg"
  gpgv --keyring "${WORK}/redhat.gpg" --output "${out}" "${WORK}/sums.gpg" 2>"${WORK}/gpgv.log" \
    || { cat "${WORK}/gpgv.log" >&2; die "signature verification FAILED for ${base}/sha256sum.txt.gpg"; }
  log "verified Red Hat signature on ${base}/sha256sum.txt.gpg"
}

# Download <base>/<file> into DEST and check it against the verified list <sums>.
fetch_and_check() {
  local base="$1" file="$2" sums="$3" expected
  expected="$(awk -v f="${file}" '$2 == f || $2 == "./"f {print $1; exit}' "${sums}")"
  [[ -n "${expected}" ]] || die "${file} is not listed in the verified checksum file"
  if [[ -f "${DEST}/${file}" ]] && echo "${expected}  ${DEST}/${file}" | sha256sum -c --quiet - 2>/dev/null; then
    log "already present and valid: ${file}"
    return
  fi
  log "downloading ${file}"
  fetch "${base}/${file}" "${DEST}/${file}.part"
  echo "${expected}  ${DEST}/${file}.part" | sha256sum -c --quiet - || die "checksum mismatch: ${file}"
  mv "${DEST}/${file}.part" "${DEST}/${file}"
}

# --- OpenShift clients ---------------------------------------------------------
OCP_BASE="${CONTENT_BASE_URL}/openshift-v4/$(arch_dir)/clients/ocp/${OCP_MAX_VERSION}"
fetch_signed_sums "${OCP_BASE}" "${WORK}/ocp-sums.txt"
OC_TARBALL="openshift-client-linux-${OCP_ARCH}-rhel9-${OCP_MAX_VERSION}.tar.gz"
fetch_and_check "${OCP_BASE}" "${OC_TARBALL}" "${WORK}/ocp-sums.txt"
fetch_and_check "${OCP_BASE}" "oc-mirror.rhel9.tar.gz" "${WORK}/ocp-sums.txt"
cp "${WORK}/ocp-sums.txt" "${DEST}/sha256sum.ocp-clients.verified.txt"

# --- mirror registry -----------------------------------------------------------
MR_BASE="${CONTENT_BASE_URL}/cgw/mirror-registry/${MIRROR_REGISTRY_VERSION}"
fetch_signed_sums "${MR_BASE}" "${WORK}/mr-sums.txt"
fetch_and_check "${MR_BASE}" "mirror-registry-${OCP_ARCH}.tar.gz" "${WORK}/mr-sums.txt"
cp "${WORK}/mr-sums.txt" "${DEST}/sha256sum.mirror-registry.verified.txt"

# --- RHACS CLI (optional) ------------------------------------------------------
if [[ -n "${RHACS_VERSION}" ]]; then
  [[ "${OCP_ARCH}" == "amd64" ]] && ROXCTL="roxctl" || ROXCTL="roxctl-${OCP_ARCH}"
  ACS_BASE="${CONTENT_BASE_URL}/rhacs/assets/${RHACS_VERSION}/bin/Linux"
  fetch "${ACS_BASE}/sha256sum.txt" "${WORK}/acs-sums.txt"
  warn "RHACS publishes an unsigned checksum list; integrity relies on TLS to mirror.openshift.com"
  fetch_and_check "${ACS_BASE}" "${ROXCTL}" "${WORK}/acs-sums.txt"
  chmod 0755 "${DEST}/${ROXCTL}"
  cp "${WORK}/acs-sums.txt" "${DEST}/sha256sum.rhacs.unsigned.txt"
else
  warn "RHACS_VERSION is empty in versions.env; skipping roxctl"
fi

# --- Butane (Phase 3: install-time MachineConfigs) ----------------------------------
if [[ -n "${BUTANE_VERSION}" ]]; then
  BUTANE_BASE="${CONTENT_BASE_URL}/openshift-v4/clients/butane/v${BUTANE_VERSION}"
  fetch "${BUTANE_BASE}/sha256sum.txt" "${WORK}/butane-sums.txt"
  warn "Butane publishes an unsigned checksum list; integrity relies on TLS to mirror.openshift.com"
  fetch_and_check "${BUTANE_BASE}" "butane-${OCP_ARCH}" "${WORK}/butane-sums.txt"
  chmod 0755 "${DEST}/butane-${OCP_ARCH}"
  cp "${WORK}/butane-sums.txt" "${DEST}/sha256sum.butane.unsigned.txt"
else
  warn "BUTANE_VERSION is empty in versions.env; skipping butane"
fi

# --- Record ---------------------------------------------------------------------
( cd "${DEST}" && find . -maxdepth 1 -type f ! -name 'SHA256SUMS' -printf '%P\n' | sort \
    | xargs sha256sum >SHA256SUMS )
log "tools for ${OCP_MAX_VERSION} are in ${DEST}"

if ${INSTALL}; then
  mkdir -p "${HOME}/.local/bin"
  tar -xzf "${DEST}/${OC_TARBALL}" -C "${HOME}/.local/bin" oc kubectl
  tar -xzf "${DEST}/oc-mirror.rhel9.tar.gz" -C "${HOME}/.local/bin" oc-mirror
  chmod 0755 "${HOME}/.local/bin/oc" "${HOME}/.local/bin/kubectl" "${HOME}/.local/bin/oc-mirror"
  log "installed oc, kubectl, oc-mirror into ${HOME}/.local/bin"
fi
