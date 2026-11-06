#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 02-validate-environment.sh: check the environment the installer depends on,
# from the provisioner host. EXAMPLE, not validated.
#
#   - DNS: api, api-int (if present), *.apps resolve to the VIPs, with PTR records
#   - mirror registry: TLS trusted with the CA bundle, pull credential accepted
#   - BMCs: Redfish service root reachable and credentials accepted; for IPMI,
#     `ipmitool ... power status` (if ipmitool is installed)
#   - NTP servers resolve
# Writes a report to EVIDENCE_DIR. Exits non-zero if any check FAILED.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd dig curl jq python3
require_pyyaml

FAILS=0
pass() { printf '  [PASS] %s\n' "$*"; }
wrn()  { printf '  [WARN] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }

CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
mkdir -p "${EVIDENCE_DIR}"
REPORT="${EVIDENCE_DIR}/environment-check-$(stamp).txt"

{
echo "Environment check for ${CLUSTER_DOMAIN} at $(date -u +%FT%TZ) by $(id -un)@$(uname -n)"

echo "DNS"
check_a() {
  local name="$1" want="$2" got
  got="$(dig +short A "${name}" | tail -1)"
  if [[ "${got}" == "${want}" ]]; then pass "${name} -> ${got}"; else fail "${name} -> '${got}' (expected ${want})"; fi
}
check_a "api.${CLUSTER_DOMAIN}" "${API_VIP}"
check_a "test-$(date +%s).apps.${CLUSTER_DOMAIN}" "${INGRESS_VIP}"
ptr="$(dig +short -x "${API_VIP}" | head -1)"
if [[ -n "${ptr}" ]]; then pass "PTR ${API_VIP} -> ${ptr}"; else fail "no PTR record for ${API_VIP} (Red Hat requires A and PTR for the API)"; fi
api_int="$(dig +short A "api-int.${CLUSTER_DOMAIN}" | tail -1)"
[[ -z "${api_int}" || "${api_int}" == "${API_VIP}" ]] || wrn "api-int.${CLUSTER_DOMAIN} -> ${api_int}, not the API VIP"
if dig +tcp +short A "api.${CLUSTER_DOMAIN}" >/dev/null 2>&1; then pass "DNS over TCP works (CoreDNS needs TCP and UDP)"; else fail "DNS over TCP failed"; fi

echo "Node addresses (from networkConfig, if present)"
while IFS=$'\t' read -r name ip; do
  [[ -n "${ip}" ]] || continue
  ptr="$(dig +short -x "${ip}" | head -1)"
  if [[ -n "${ptr}" ]]; then pass "${name} ${ip} PTR -> ${ptr}"; else fail "${name} ${ip} has no PTR record (needed to set host names)"; fi
done < <(python3 - "${HOSTS_FILE}" <<'PY'
import sys, yaml
for h in yaml.safe_load(open(sys.argv[1])) or []:
    nc = h.get("networkConfig") or {}
    for i in nc.get("interfaces", []):
        for a in ((i.get("ipv4") or {}).get("address") or []):
            print(f"{h.get('name')}\t{a.get('ip')}")
            break
PY
)

echo "Mirror registry"
load_release
reg="${OCP_RELEASE_MIRROR%%/*}"
code="$(curl -s -o /dev/null -w '%{http_code}' --cacert "${CA_BUNDLE_FILE}" "https://${reg}/health/instance" || true)"
if [[ "${code}" == "200" ]]; then pass "https://${reg} is healthy and trusted with ${CA_BUNDLE_FILE}"; else fail "https://${reg}/health/instance returned ${code:-no response}"; fi
if oc image info --registry-config "${PULL_SECRET_FILE}" --certificate-authority "${CA_BUNDLE_FILE}" \
     "${OCP_RELEASE_MIRROR}@${OCP_RELEASE_DIGEST}" >/dev/null 2>&1; then
  pass "release ${OCP_RELEASE_DIGEST} readable with the cluster pull secret"
else
  fail "cannot read ${OCP_RELEASE_MIRROR}@${OCP_RELEASE_DIGEST} with the cluster pull secret"
fi

echo "NTP servers"
for s in ${NTP_SERVERS}; do
  if [[ "${s}" =~ ^[0-9.]+$ ]] || [[ -n "$(dig +short "${s}" | head -1)" ]]; then pass "${s}"; else fail "${s} does not resolve"; fi
done

echo "BMCs"
if [[ -r "${BMC_CREDENTIALS_FILE}" ]]; then
  perms="$(stat -c '%a' "${BMC_CREDENTIALS_FILE}")"
  [[ "${perms}" =~ ^[46]00$ ]] || fail "${BMC_CREDENTIALS_FILE} must be mode 0600 (is ${perms})"
  # shellcheck source=/dev/null
  source "${BMC_CREDENTIALS_FILE}"
else
  fail "BMC credentials file not readable: ${BMC_CREDENTIALS_FILE}"
fi
cacert=()
[[ -n "${BMC_CA_BUNDLE}" ]] && cacert=(--cacert "${BMC_CA_BUNDLE}")
while IFS=$'\t' read -r name role addr; do
  v="$(host_var "${name}")"
  uvar="BMC_USERNAME_${v}" pvar="BMC_PASSWORD_${v}"
  user="${!uvar:-}" pass_="${!pvar:-}"
  if [[ -z "${user}" || -z "${pass_}" ]]; then fail "${name}: no ${uvar}/${pvar} in the credentials file"; continue; fi
  scheme="${addr%%://*}" rest="${addr#*://}" hostport="${rest%%/*}"
  case "${scheme}" in
    redfish-virtualmedia|idrac-virtualmedia|redfish|redfish+https|idrac-redfish)
      cfg="$(mktemp)"; printf 'user = "%s:%s"\n' "${user}" "${pass_}" >"${cfg}"
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${cacert[@]}" -K "${cfg}" "https://${hostport}/redfish/v1/Systems" || true)"
      rm -f "${cfg}"
      if [[ "${code}" == "200" ]]; then pass "${name} (${role}) ${scheme}://${hostport}: Redfish reachable, TLS verified, credentials accepted"
      elif [[ "${code}" == "000" ]]; then fail "${name}: cannot reach https://${hostport} or the TLS certificate is not trusted (set BMC_CA_BUNDLE)"
      else fail "${name}: Redfish returned HTTP ${code}"; fi
      if [[ "${PROVISIONING_METHOD}" == "virtualmedia" && "${scheme}" != *virtualmedia ]]; then
        fail "${name}: ${scheme}:// is network (PXE) boot; without a provisioning network use a virtual media driver"
      fi ;;
    redfish+http)
      fail "${name}: redfish+http:// disables TLS to the BMC; not acceptable for this design (SC-8)" ;;
    ipmi)
      [[ "${PROVISIONING_METHOD}" == "pxe" ]] || fail "${name}: IPMI requires a provisioning network (PROVISIONING_METHOD=pxe)"
      wrn "${name}: IPMI is unencrypted; Red Hat recommends it only on a secured management network"
      if command -v ipmitool >/dev/null; then
        if IPMI_PASSWORD="${pass_}" ipmitool -I lanplus -H "${hostport%%:*}" -U "${user}" -E power status >/dev/null 2>&1; then
          pass "${name}: IPMI reachable, credentials accepted"
        else fail "${name}: IPMI power status failed"; fi
      fi ;;
    *) fail "${name}: unsupported BMC address scheme '${scheme}'" ;;
  esac
done < <(list_hosts)

echo
} 2>&1 | tee "${REPORT}"
FAILS="$(grep -c '\[FAIL\]' "${REPORT}" || true)"
chmod 0600 "${REPORT}"
((FAILS == 0)) || die "${FAILS} check(s) failed; report: ${REPORT}"
log "environment checks passed; report: ${REPORT}"
