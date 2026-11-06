#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 02-check-registry-host.sh: check that the registry host is ready for (or
# still compliant with) the mirror registry installation.
#
# Run before 03-install-mirror-registry.sh, and again on a schedule (for
# example, monthly) as a configuration check (CM-6, SC-17, AU-8).
# Exits non-zero if any check FAILED.
#
# Usage: 02-check-registry-host.sh [--tls-only]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

TLS_ONLY=false
[[ "${1:-}" == "--tls-only" ]] && TLS_ONLY=true

FAILS=0
pass() { printf '  [PASS] %s\n' "$*"; }
wrn()  { printf '  [WARN] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

check_tls() {
  echo "TLS certificate (${TLS_CERT})"
  if ! have openssl; then fail "openssl not found"; return; fi
  local f
  for f in "${TLS_CERT}" "${TLS_KEY}" "${TLS_CA_BUNDLE}"; do
    [[ -r "${f}" ]] || { fail "not readable: ${f}"; return; }
  done
  local key_perm
  key_perm="$(stat -c '%a' "${TLS_KEY}")"
  if [[ "${key_perm}" =~ ^[46]00$ ]]; then pass "private key permissions ${key_perm}"; else fail "private key permissions ${key_perm}; use 0600"; fi

  if [[ "$(openssl x509 -in "${TLS_CERT}" -noout -pubkey | openssl sha256)" == \
        "$(openssl pkey -in "${TLS_KEY}" -pubout | openssl sha256)" ]]; then
    pass "certificate and private key match"
  else
    fail "certificate and private key do NOT match"
  fi

  if openssl x509 -in "${TLS_CERT}" -noout -checkhost "${REGISTRY_FQDN}" 2>/dev/null | grep -q 'does match'; then
    pass "subjectAltName covers ${REGISTRY_FQDN}"
  else
    fail "certificate is not valid for ${REGISTRY_FQDN} (check subjectAltName)"
  fi

  # Leaf first, any intermediates after it in the same file.
  local tmp
  tmp="$(mktemp -d)"
  awk -v d="${tmp}" '/BEGIN CERT/ {n++} n {print > (d "/c" n ".pem")}' "${TLS_CERT}"
  local vargs=(-purpose sslserver -CAfile "${TLS_CA_BUNDLE}") vout
  if [[ -f "${tmp}/c2.pem" ]]; then
    cat "${tmp}"/c[2-9]*.pem >"${tmp}/chain.pem"
    vargs+=(-untrusted "${tmp}/chain.pem")
  fi
  if vout="$(openssl verify "${vargs[@]}" "${tmp}/c1.pem" 2>&1)"; then
    pass "certificate chains to ${TLS_CA_BUNDLE} (purpose sslserver)"
  else
    fail "certificate does not verify against ${TLS_CA_BUNDLE}: $(grep -m1 "^error" <<<"${vout}" || tail -1 <<<"${vout}")"
  fi

  local text
  text="$(openssl x509 -in "${tmp}/c1.pem" -noout -text)"
  rm -rf "${tmp}"
  if grep -qiE 'Signature Algorithm: (sha1|md5)' <<<"${text}"; then
    fail "certificate uses a SHA-1/MD5 signature (ITSP.40.111)"
  else
    pass "signature algorithm: $(grep -m1 'Signature Algorithm' <<<"${text}" | awk '{print $3}')"
  fi
  local bits
  bits="$(grep -m1 -oE 'Public-Key: \(([0-9]+) bit' <<<"${text}" | grep -oE '[0-9]+')"
  if grep -q 'rsaEncryption' <<<"${text}"; then
    if ((bits >= 3072)); then pass "RSA ${bits}-bit key"
    elif ((bits >= 2048)); then wrn "RSA ${bits}-bit key; ITSP.40.111 recommends 3072+ for use beyond 2030"
    else fail "RSA ${bits}-bit key is too short"; fi
  else
    pass "key: ${bits}-bit $(grep -m1 -oE 'ASN1 OID: [a-z0-9]+' <<<"${text}" || echo EC)"
  fi

  local days=$((TLS_EXPIRY_WARN_DAYS * 86400)) end
  end="$(openssl x509 -in "${TLS_CERT}" -noout -enddate | cut -d= -f2)"
  if ! openssl x509 -in "${TLS_CERT}" -noout -checkend 0 >/dev/null; then
    fail "certificate EXPIRED (${end})"
  elif ! openssl x509 -in "${TLS_CERT}" -noout -checkend "${days}" >/dev/null; then
    wrn "certificate expires within ${TLS_EXPIRY_WARN_DAYS} days (${end}); plan rotation"
  else
    pass "certificate valid until ${end}"
  fi
}

if ${TLS_ONLY}; then
  check_tls
  echo
  ((FAILS == 0)) || die "${FAILS} check(s) failed"
  log "TLS checks passed"
  exit 0
fi

echo "Operating system"
if [[ -r /etc/redhat-release ]] && grep -q "release ${RHEL_HOST_VERSION}" /etc/redhat-release; then
  pass "$(cat /etc/redhat-release)"
else
  fail "expected RHEL ${RHEL_HOST_VERSION}; found: $(cat /etc/redhat-release 2>/dev/null || uname -sr)"
fi
if [[ "$(cat /proc/sys/crypto/fips_enabled 2>/dev/null)" == "1" ]]; then
  pass "FIPS mode is enabled"
else
  fail "FIPS mode is not enabled (required on the high side, AD-18)"
fi
if have getenforce && [[ "$(getenforce)" == "Enforcing" ]]; then
  pass "SELinux is enforcing"
else
  fail "SELinux is not enforcing"
fi
if have systemctl && systemctl is-active --quiet auditd 2>/dev/null; then
  pass "auditd is running"
else
  fail "auditd is not running (AU-2, AU-12)"
fi

echo "Commands"
for c in podman openssl jq curl tar sha256sum gpg gpgv git getent; do
  if have "${c}"; then pass "${c}"; else fail "${c} not found"; fi
done

echo "Service account"
if (($(id -u) == 0)); then
  fail "run as the unprivileged registry service account, not root (rootless install)"
else
  pass "running as $(id -un) (rootless)"
  if grep -q "^$(id -un):" /etc/subuid 2>/dev/null && grep -q "^$(id -un):" /etc/subgid 2>/dev/null; then
    pass "subordinate UID/GID ranges configured"
  else
    fail "no /etc/subuid or /etc/subgid entry for $(id -un) (needed by rootless podman)"
  fi
  if have loginctl && [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" == "yes" ]]; then
    pass "systemd linger enabled (registry survives logout and reboot)"
  else
    wrn "linger not enabled yet for $(id -un) (the installer enables it)"
  fi
fi

echo "Name resolution and time"
addr="$(getent ahostsv4 "${REGISTRY_FQDN}" 2>/dev/null | awk 'NR == 1 {print $1}')"
if [[ -n "${addr}" ]]; then
  pass "${REGISTRY_FQDN} -> ${addr}"
  if ip -o addr show 2>/dev/null | grep -qw "${addr}"; then
    pass "${addr} is configured on this host"
  else
    wrn "${addr} is not an address of this host (load balancer or NAT in front?)"
  fi
  rname="$(getent hosts "${addr}" | awk '{print $2}')"
  if [[ "${rname}" == "${REGISTRY_FQDN}" ]]; then pass "reverse lookup ${addr} -> ${rname}"
  else wrn "reverse lookup of ${addr} returns '${rname:-nothing}'"; fi
else
  fail "${REGISTRY_FQDN} does not resolve"
fi
if have chronyc && chronyc -n tracking 2>/dev/null | grep -q 'Leap status *: Normal'; then
  pass "time is synchronized ($(chronyc -n tracking | awk -F': ' '/Reference ID/ {print $2}'))"
else
  fail "time is not synchronized with chronyd (AU-8; also breaks TLS validation)"
fi

echo "Storage"
if [[ -d "${QUAY_BASE}" ]]; then
  mnt="$(findmnt -n -o TARGET --target "${QUAY_BASE}")"
  if [[ "${mnt}" == "/" || "${mnt}" == "/home" ]]; then
    wrn "${QUAY_BASE} is on ${mnt}; use a dedicated filesystem so a full registry can't fill the OS"
  else
    pass "${QUAY_BASE} is on dedicated mount ${mnt}"
  fi
  free_gb="$(df -BG --output=avail "${QUAY_BASE}" | tail -1 | tr -dc '0-9')"
  if ((free_gb >= HS_MIN_FREE_GB)); then pass "${free_gb} GiB free"
  else fail "${free_gb} GiB free under ${QUAY_BASE}; need ${HS_MIN_FREE_GB} GiB"; fi
  if [[ -w "${QUAY_BASE}" ]]; then pass "${QUAY_BASE} is writable by $(id -un)"; else fail "${QUAY_BASE} is not writable by $(id -un)"; fi
else
  fail "${QUAY_BASE} does not exist"
fi

echo "Firewall"
if have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
  if firewall-cmd --list-all 2>/dev/null | grep -qE "ports:.*\b${REGISTRY_PORT}/tcp"; then
    pass "${REGISTRY_PORT}/tcp is open in the active zone"
  else
    wrn "${REGISTRY_PORT}/tcp not listed in the default zone (check rich rules or zone sources)"
  fi
else
  fail "firewalld is not running"
fi

echo "Transfer verification key"
if [[ -r "${TRANSFER_VERIFY_KEY}" ]]; then
  pass "${TRANSFER_VERIFY_KEY} ($(gpg --show-keys --with-colons "${TRANSFER_VERIFY_KEY}" 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}'))"
else
  fail "public transfer key not found: ${TRANSFER_VERIFY_KEY}"
fi

check_tls

echo
((FAILS == 0)) || die "${FAILS} check(s) failed"
log "registry host is ready"
