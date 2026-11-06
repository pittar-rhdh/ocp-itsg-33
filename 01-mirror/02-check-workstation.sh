#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 02-check-workstation.sh: check that the low-side mirror workstation is ready.
#
# Reports every problem it finds, then exits non-zero if any check FAILED.
# Warnings don't stop the run, but they should be resolved or recorded.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

FAILS=0
pass() { printf '  [PASS] %s\n' "$*"; }
wrn()  { printf '  [WARN] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }

echo "Operating system"
if [[ -r /etc/redhat-release ]] && grep -q "release ${RHEL_HOST_VERSION}" /etc/redhat-release; then
  pass "$(cat /etc/redhat-release)"
else
  wrn "expected RHEL ${RHEL_HOST_VERSION}; found: $(cat /etc/redhat-release 2>/dev/null || uname -sr)"
fi
if [[ "$(cat /proc/sys/crypto/fips_enabled 2>/dev/null)" == "1" ]]; then
  pass "FIPS mode is enabled"
else
  wrn "FIPS mode is not enabled (recommended for consistency with the high side; see AD-18)"
fi

echo "Commands"
for c in oc oc-mirror jq git curl gpg gpgv sha256sum tar; do
  if command -v "${c}" >/dev/null 2>&1; then pass "${c}"; else fail "${c} not found"; fi
done

if command -v oc >/dev/null 2>&1; then
  oc_ver="$(oc version --client -o json 2>/dev/null | jq -r '.releaseClientVersion // .clientVersion.gitVersion // ""')"
  if [[ "${oc_ver}" == "${OCP_MINOR}".* ]]; then
    pass "oc client ${oc_ver} matches ${OCP_MINOR}"
  else
    fail "oc client '${oc_ver}' does not match ${OCP_MINOR} (run 01-download-tools.sh --install)"
  fi
fi
if command -v oc-mirror >/dev/null 2>&1; then
  if oc-mirror --v2 --help >/dev/null 2>&1; then
    pass "oc-mirror supports --v2"
  else
    fail "oc-mirror does not support --v2"
  fi
fi

echo "Registry credentials"
if [[ -r "${REGISTRY_AUTH_FILE}" ]]; then
  perms="$(stat -c '%a' "${REGISTRY_AUTH_FILE}")"
  if [[ "${perms}" =~ ^[46]00$ ]]; then
    pass "auth file permissions ${perms}"
  else
    wrn "auth file ${REGISTRY_AUTH_FILE} has permissions ${perms}; use 0600"
  fi
  for r in registry.redhat.io quay.io; do
    if jq -e --arg r "${r}" '.auths | has($r)' "${REGISTRY_AUTH_FILE}" >/dev/null 2>&1; then
      pass "credentials for ${r}"
    else
      fail "no credentials for ${r} in ${REGISTRY_AUTH_FILE}"
    fi
  done
else
  fail "auth file not readable: ${REGISTRY_AUTH_FILE} (save the Red Hat pull secret there)"
fi

echo "Red Hat release key"
if [[ -r "${RH_RELEASE_KEY}" ]]; then pass "${RH_RELEASE_KEY}"; else fail "missing ${RH_RELEASE_KEY}"; fi

echo "Storage"
mkdir -p "${MIRROR_BASE}" 2>/dev/null || true
if [[ -d "${MIRROR_BASE}" ]]; then
  free_gb="$(df -BG --output=avail "${MIRROR_BASE}" | tail -1 | tr -dc '0-9')"
  if ((free_gb >= MIRROR_MIN_FREE_GB)); then
    pass "${free_gb} GiB free under ${MIRROR_BASE}"
  else
    fail "${free_gb} GiB free under ${MIRROR_BASE}; need at least ${MIRROR_MIN_FREE_GB} GiB"
  fi
else
  fail "cannot create ${MIRROR_BASE}"
fi
if [[ -d "${MIRROR_CACHE_DIR}" ]]; then
  pass "cache exists (incremental mirroring possible)"
else
  wrn "no cache at ${MIRROR_CACHE_DIR}; the first run is a full mirror"
fi

echo "Connectivity"
for url in https://registry.redhat.io/v2/ https://quay.io/v2/ \
           https://api.openshift.com/api/upgrades_info/v1/graph "${CONTENT_BASE_URL}/"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${url}" || true)"
  if [[ "${code}" =~ ^(200|301|302|307|400|401)$ ]]; then pass "${url} (${code})"; else fail "${url} (${code:-no response})"; fi
done

echo "Transfer signing"
if [[ -n "${TRANSFER_SIGNING_KEY}" ]]; then
  if gpg --list-secret-keys "${TRANSFER_SIGNING_KEY}" >/dev/null 2>&1; then
    pass "signing key ${TRANSFER_SIGNING_KEY} available"
  else
    fail "secret key ${TRANSFER_SIGNING_KEY} not found in the GPG keyring"
  fi
elif [[ "${REQUIRE_TRANSFER_SIGNATURE}" == "true" ]]; then
  fail "TRANSFER_SIGNING_KEY is not set and REQUIRE_TRANSFER_SIGNATURE=true"
else
  wrn "transfers will not be signed (REQUIRE_TRANSFER_SIGNATURE=false)"
fi

echo
if ((FAILS > 0)); then die "${FAILS} check(s) failed"; fi
log "workstation is ready"
