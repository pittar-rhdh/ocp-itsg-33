#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 01-check-provisioner.sh: check that the provisioner host is ready to run a
# FIPS, air-gapped, bare-metal IPI installation. EXAMPLE, not validated.
#
# Checks the host (RHEL 9, FIPS, SELinux, time, libvirt, bridges, firewall) and
# the Phase 2 hand-off in INPUTS_DIR (installer checksum and pinned release).
# Exits non-zero if any check FAILED.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

FAILS=0
pass() { printf '  [PASS] %s\n' "$*"; }
wrn()  { printf '  [WARN] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "Operating system"
if [[ -r /etc/redhat-release ]] && grep -q "release ${RHEL_HOST_VERSION}" /etc/redhat-release; then
  pass "$(cat /etc/redhat-release)"
else
  fail "the provisioner must run RHEL ${RHEL_HOST_VERSION}.x"
fi
if [[ "$(cat /proc/sys/crypto/fips_enabled 2>/dev/null)" == "1" ]]; then
  pass "FIPS mode is enabled"
elif [[ "${FIPS}" == "true" ]]; then
  fail "FIPS mode is not enabled; a FIPS cluster must be installed from a RHEL host in FIPS mode"
else
  wrn "FIPS mode is not enabled (FIPS=false in settings)"
fi
if have getenforce && [[ "$(getenforce)" == "Enforcing" ]]; then pass "SELinux is enforcing"; else fail "SELinux is not enforcing"; fi
if have chronyc && chronyc -n tracking 2>/dev/null | grep -q 'Leap status *: Normal'; then
  pass "time is synchronized"
else
  fail "time is not synchronized (chronyd); certificates and logs depend on it"
fi

echo "Installation user"
if (($(id -u) == 0)); then
  fail "run as the non-root installation user (Red Hat's procedure uses 'kni'), not root"
else
  pass "running as $(id -un)"
  if id -nG | tr ' ' '\n' | grep -qx libvirt; then pass "member of the libvirt group"; else fail "$(id -un) is not in the libvirt group"; fi
  if sudo -n true 2>/dev/null; then pass "passwordless sudo available"; else wrn "sudo needs a password or is not configured (Red Hat's procedure grants NOPASSWD sudo)"; fi
fi

echo "Packages and services"
for c in virsh qemu-img nmstatectl ipmitool jq python3 curl openssl dig; do
  if have "${c}"; then pass "${c}"; else fail "${c} not found"; fi
done
if python3 -c 'import yaml' 2>/dev/null; then pass "python3-pyyaml"; else fail "python3-pyyaml not installed"; fi
if have virsh && virsh -c qemu:///system pool-info default >/dev/null 2>&1; then
  pass "libvirt storage pool 'default' exists"
else
  fail "libvirt storage pool 'default' is missing (virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images)"
fi
free_gb="$(df -BG --output=avail /var/lib/libvirt/images 2>/dev/null | tail -1 | tr -dc '0-9' || true)"
if [[ -n "${free_gb}" ]] && ((free_gb >= 100)); then pass "${free_gb} GiB free for the bootstrap VM"; else fail "need about 100 GiB free under /var/lib/libvirt/images (bootstrap VM)"; fi

echo "Network bridges"
for br in "${EXTERNAL_BRIDGE}" $([[ "${PROVISIONING_METHOD}" == "pxe" ]] && echo "${PROVISIONING_BRIDGE}"); do
  if ip -o link show "${br}" >/dev/null 2>&1; then
    pass "bridge ${br} exists ($(ip -o -4 addr show "${br}" | awk '{print $4}' | head -1))"
  else
    fail "bridge ${br} is missing (create it with nmstatectl; see the docs)"
  fi
done
case "${PROVISIONING_METHOD}" in
  virtualmedia|pxe) pass "provisioning method: ${PROVISIONING_METHOD}" ;;
  *) fail "PROVISIONING_METHOD must be virtualmedia or pxe" ;;
esac

echo "Firewall"
if have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
  pass "firewalld is running"
  zone_cfg="$(sudo -n firewall-cmd --list-all 2>/dev/null || firewall-cmd --list-all 2>/dev/null)"
  for p in 6180/tcp 6183/tcp; do
    if grep -qE "ports:.*${p}" <<<"${zone_cfg}"; then pass "${p} open (BMC access to the boot image)"; else wrn "${p} not visible in the default zone; BMCs must reach the provisioner on 6180 (HTTP) or 6183 (TLS)"; fi
  done
  if grep -qE 'services:.*\bhttp\b|ports:.*\b80/tcp' <<<"${zone_cfg}"; then pass "http (80/tcp) open"; else wrn "http (80/tcp) not open; Red Hat's procedure enables it for the provisioner"; fi
else
  fail "firewalld is not running"
fi

echo "SSH key for the core user"
if [[ -r "${SSH_PUBLIC_KEY_FILE}" ]]; then
  ktype="$(awk '{print $1}' "${SSH_PUBLIC_KEY_FILE}")"
  if [[ "${FIPS}" == "true" && "${ktype}" == "ssh-ed25519" ]]; then
    fail "${SSH_PUBLIC_KEY_FILE} is ed25519; in FIPS mode Red Hat requires RSA or ECDSA"
  else
    pass "${SSH_PUBLIC_KEY_FILE} (${ktype})"
  fi
else
  fail "SSH public key not found: ${SSH_PUBLIC_KEY_FILE}"
fi

echo "Phase 2 hand-off (${INPUTS_DIR})"
for f in "${RELEASE_ENV}" "${INSTALLER}" "${IDMS_FILE}" "${PULL_SECRET_FILE}" "${CA_BUNDLE_FILE}"; do
  if [[ -r "${f}" ]]; then pass "$(basename "${f}")"; else fail "missing: ${f}"; fi
done
if [[ -r "${RELEASE_ENV}" && -r "${INSTALLER}" ]]; then
  load_release
  if [[ "$(sha256sum "${INSTALLER}" | cut -d' ' -f1)" == "${OCP_INSTALLER_SHA256}" ]]; then
    pass "installer checksum matches release.env"
  else
    fail "installer checksum does NOT match release.env"
  fi
  if "${INSTALLER}" version 2>/dev/null | grep -q "release image ${OCP_RELEASE_IMAGE}"; then
    pass "installer is pinned to ${OCP_RELEASE_IMAGE}"
  else
    fail "installer is not pinned to ${OCP_RELEASE_IMAGE}"
  fi
fi
if [[ -r "${PULL_SECRET_FILE}" ]]; then
  perms="$(stat -c '%a' "${PULL_SECRET_FILE}")"
  if [[ "${perms}" =~ ^[46]00$ ]]; then pass "pull secret permissions ${perms}"; else fail "pull secret must be mode 0600 (is ${perms})"; fi
  if jq -e '.auths | keys | map(select(test("redhat.io|quay.io|openshift.com"))) | length == 0' "${PULL_SECRET_FILE}" >/dev/null 2>&1; then
    pass "pull secret has no Red Hat registry credentials (mirror only)"
  else
    wrn "pull secret contains Red Hat registry credentials; use the pull-only mirror credential"
  fi
fi
for t in oc butane; do
  if have "${t}"; then pass "${t} ($(command -v "${t}"))"; else fail "${t} not found (copy it into ${INPUTS_DIR})"; fi
done

echo
((FAILS == 0)) || die "${FAILS} check(s) failed"
log "provisioner host is ready"
