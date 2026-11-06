#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 04-create-manifests.sh: generate the installation manifests and add the
# install-time security settings. EXAMPLE, not validated.
#
#   openshift-install-fips create manifests
#   + openshift/99-{master,worker}-chrony.yaml           (AU-8; required NTP for disconnected)
#   + openshift/99-{master,worker}-disk-encryption.yaml  (SC-28; DISK_ENCRYPTION=tpm2)
#   + manifests/cluster-network-03-config.yml            (SC-8; IPSEC_MODE)
#
# MachineConfigs are generated with Butane from 03-install/manifests/*.bu.tmpl.
# All generated manifests are copied (with checksums) to EVIDENCE_DIR, because
# the installer consumes them during `create cluster`.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd butane sha256sum

load_release
[[ -f "${INSTALL_DIR}/install-config.yaml" ]] || die "no install-config.yaml in ${INSTALL_DIR}; run 03-render-install-config.sh"
[[ ! -d "${INSTALL_DIR}/manifests" ]] || die "${INSTALL_DIR}/manifests already exists; start again from an empty directory"
[[ "$(sha256sum "${INSTALLER}" | cut -d' ' -f1)" == "${OCP_INSTALLER_SHA256}" ]] || die "installer checksum mismatch"

log "creating manifests with $(basename "${INSTALLER}")"
"${INSTALLER}" create manifests --dir "${INSTALL_DIR}" --log-level info

SRC="${INSTALL_SRC}/manifests"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Fill {{KEY}} placeholders in a template: render <template> KEY=value ...
render() {
  local tmpl="$1"; shift
  python3 - "${tmpl}" "$@" <<'PY'
import sys
t = open(sys.argv[1]).read()
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    t = t.replace("{{%s}}" % k, v)
if "{{" in t:
    sys.exit("unresolved placeholder in " + sys.argv[1])
print(t, end="")
PY
}

chrony_servers=""
for s in ${NTP_SERVERS}; do chrony_servers+="          server ${s} iburst"$'\n'; done
chrony_servers="${chrony_servers%$'\n'}"

for role in master worker; do
  render "${SRC}/99-ROLE-chrony.bu.tmpl" "ROLE=${role}" "CHRONY_SERVERS=${chrony_servers}" >"${WORK}/chrony-${role}.bu"
  butane --strict "${WORK}/chrony-${role}.bu" -o "${INSTALL_DIR}/openshift/99-${role}-chrony.yaml"
  log "added openshift/99-${role}-chrony.yaml"

  case "${DISK_ENCRYPTION}" in
    tpm2)
      render "${SRC}/99-ROLE-disk-encryption.bu.tmpl" "ROLE=${role}" "FIPS=${FIPS}" >"${WORK}/luks-${role}.bu"
      butane --strict "${WORK}/luks-${role}.bu" -o "${INSTALL_DIR}/openshift/99-${role}-disk-encryption.yaml"
      log "added openshift/99-${role}-disk-encryption.yaml (LUKS2, TPM 2.0)" ;;
    none) warn "DISK_ENCRYPTION=none: boot disks will NOT be encrypted (record the justification, SC-28)" ;;
    *) die "DISK_ENCRYPTION must be tpm2 or none" ;;
  esac
done

case "${IPSEC_MODE}" in
  Full|External)
    render "${SRC}/cluster-network-03-config.yml.tmpl" "IPSEC_MODE=${IPSEC_MODE}" \
      >"${INSTALL_DIR}/manifests/cluster-network-03-config.yml"
    log "added manifests/cluster-network-03-config.yml (IPsec ${IPSEC_MODE})" ;;
  Disabled) warn "IPSEC_MODE=Disabled: east-west traffic is not encrypted (record the TRA justification, SC-8)" ;;
  *) die "IPSEC_MODE must be Full, External, or Disabled" ;;
esac

# Evidence: every manifest the installer will consume, with checksums.
tar -C "${INSTALL_DIR}" -czf "${WORK}/manifests.tar.gz" manifests openshift
keep_evidence "${WORK}/manifests.tar.gz" "manifests-$(stamp).tar.gz"
( cd "${INSTALL_DIR}" && find manifests openshift -type f | LC_ALL=C sort | xargs sha256sum ) >"${WORK}/list"
keep_evidence "${WORK}/list" "manifests-$(stamp).sha256"

log "manifests ready in ${INSTALL_DIR}; review them, then run 05-install-cluster.sh"
