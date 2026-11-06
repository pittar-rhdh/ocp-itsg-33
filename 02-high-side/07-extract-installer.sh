#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 07-extract-installer.sh: extract the FIPS-capable bare-metal installer from
# the release in the mirror registry.
#
# Red Hat's 4.22 FIPS procedure extracts the installer with
# --command=openshift-install-fips (oc 4.16+); the bare-metal IPI procedure uses
# --command=openshift-baremetal-install. In the oc source both map to the same
# binary in the release's "baremetal-installer" image.
#
# The installer is pinned to the canonical release digest
# (quay.io/openshift-release-dev/ocp-release@sha256:...), and resolved through
# the mirror with the IDMS that oc-mirror generated, so install-config.yaml can
# use the same imageDigestSources.
#
# Output: ${HS_INSTALLER_DIR}/<version>/openshift-install-fips + release.env
#
# Usage: 07-extract-installer.sh [version]      (default OCP_MAX_VERSION)
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd jq sha256sum

VER="${1:-${OCP_MAX_VERSION}}"
use_transfer_tools "${VER}"
[[ -r "${CLUSTER_PULL_SECRET_FILE}" ]] || die "pull secret not found: ${CLUSTER_PULL_SECRET_FILE} (run 05-configure-registry-access.sh)"

CR="${HS_CLUSTER_RESOURCES_DIR}/current"
IDMS="${CR}/idms-oc-mirror.yaml"
[[ -f "${IDMS}" ]] || die "no IDMS in ${CR}; import a transfer that contains the release first"

MIRROR_REF="$(registry_endpoint)/${MIRROR_NAMESPACE}/openshift/release-images:${VER}-$(arch_dir)"
CA=(--certificate-authority "${TLS_CA_BUNDLE}")

log "resolving ${MIRROR_REF}"
info="$(oc adm release info -a "${CLUSTER_PULL_SECRET_FILE}" "${CA[@]}" -o json "${MIRROR_REF}")" \
  || die "release ${VER} not found in the mirror registry"
DIGEST="$(jq -r .digest <<<"${info}")"
[[ "$(jq -r .metadata.version <<<"${info}")" == "${VER}" ]] || die "release metadata version does not match ${VER}"
[[ "${DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "unexpected digest: ${DIGEST}"

# The release digest must be one that oc-mirror mirrored a signature for.
SIG="${CR}/signature-configmap.json"
if [[ -f "${SIG}" ]]; then
  jq -e --arg d "sha256-${DIGEST#sha256:}-" '.binaryData | keys[] | select(startswith($d))' "${SIG}" >/dev/null \
    || die "no mirrored release signature for ${DIGEST}"
  log "release signature present for ${DIGEST}"
else
  warn "no signature-configmap.json in ${CR}; the release signature can't be cross-checked"
fi

RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release@${DIGEST}"
OUT="${HS_INSTALLER_DIR}/${VER}"
mkdir -p "${OUT}"
log "extracting openshift-install-fips for ${RELEASE_IMAGE}"
oc adm release extract -a "${CLUSTER_PULL_SECRET_FILE}" "${CA[@]}" --idms-file "${IDMS}" \
  --command=openshift-install-fips --to "${OUT}" "${RELEASE_IMAGE}"
BIN="${OUT}/openshift-install-fips"
[[ -x "${BIN}" ]] || die "extraction did not produce ${BIN}"

vout="$("${BIN}" version)"
printf '%s\n' "${vout}"
grep -q "release image ${RELEASE_IMAGE}" <<<"${vout}" || die "installer is not pinned to ${RELEASE_IMAGE}"

cat >"${OUT}/release.env" <<EOF
# Written by 02-high-side/07-extract-installer.sh on $(date -u +%FT%TZ)
OCP_RELEASE_VERSION=${VER}
OCP_RELEASE_DIGEST=${DIGEST}
OCP_RELEASE_IMAGE=${RELEASE_IMAGE}
OCP_RELEASE_MIRROR=${MIRROR_REF%:*}
OCP_INSTALLER=${BIN}
OCP_INSTALLER_SHA256=$(sha256sum "${BIN}" | cut -d' ' -f1)
OCP_IDMS_FILE=$(readlink -f "${IDMS}")
EOF
log "installer ready: ${BIN}"
log "release details for Phase 3: ${OUT}/release.env"
[[ "$(cat /proc/sys/crypto/fips_enabled 2>/dev/null)" == "1" ]] \
  || warn "this host is not in FIPS mode; run the installer from a FIPS-enabled RHEL 9 host"
