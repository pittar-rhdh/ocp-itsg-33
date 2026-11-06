#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 03-render-install-config.sh: build install-config.yaml from the template,
# settings, host inventory, and Phase 2 hand-off. EXAMPLE, not validated.
#
#   install-config.yaml.tmpl + settings.env   -> cluster-level values
#   HOSTS_FILE + BMC_CREDENTIALS_FILE           -> platform.baremetal.hosts
#   idms-oc-mirror.yaml                         -> imageDigestSources
#   ca-bundle.crt                               -> additionalTrustBundle
#   cluster-pull-secret.json, SSH public key    -> pullSecret, sshKey
#
# Output (mode 0600, contains secrets):  ${INSTALL_DIR}/install-config.yaml
# Evidence copy with secrets removed:    ${EVIDENCE_DIR}/install-config.redacted.yaml
#
# The installer consumes (deletes) install-config.yaml when it creates
# manifests; a backup is kept as ${INSTALL_BASE}/install-config.<cluster>.yaml.bak.
#
# Usage: 03-render-install-config.sh [--force]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd jq python3 awk
require_pyyaml

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

load_release
for f in "${HOSTS_FILE}" "${BMC_CREDENTIALS_FILE}" "${IDMS_FILE}" "${CA_BUNDLE_FILE}" "${PULL_SECRET_FILE}" "${SSH_PUBLIC_KEY_FILE}"; do
  [[ -r "${f}" ]] || die "not readable: ${f}"
done
[[ "$(stat -c '%a' "${BMC_CREDENTIALS_FILE}")" =~ ^[46]00$ ]] || die "${BMC_CREDENTIALS_FILE} must be mode 0600"
[[ "${PROVISIONING_METHOD}" =~ ^(virtualmedia|pxe)$ ]] || die "PROVISIONING_METHOD must be virtualmedia or pxe"
[[ "${LOAD_BALANCER_TYPE}" =~ ^(OpenShiftManagedDefault|UserManaged)$ ]] || die "invalid LOAD_BALANCER_TYPE"
[[ "${COMPUTE_REPLICAS}" == 0 || "${COMPUTE_REPLICAS}" -ge 2 ]] || die "COMPUTE_REPLICAS must be 0 or at least 2"
if [[ "${FIPS}" == "true" && "$(awk '{print $1}' "${SSH_PUBLIC_KEY_FILE}")" == "ssh-ed25519" ]]; then
  die "FIPS clusters need an RSA or ECDSA SSH key; ${SSH_PUBLIC_KEY_FILE} is ed25519"
fi

OUT="${INSTALL_DIR}/install-config.yaml"
if [[ -e "${INSTALL_DIR}" ]] && ! ${FORCE}; then
  die "${INSTALL_DIR} already exists. Red Hat: use an empty directory and never reuse one. Use --force only before 'create manifests' has run."
fi
[[ ! -e "${INSTALL_DIR}/manifests" && ! -e "${INSTALL_DIR}/.openshift_install_state.json" ]] \
  || die "${INSTALL_DIR} has already been used by the installer; start from a new, empty directory"
mkdir -p "${INSTALL_DIR}" "${EVIDENCE_DIR}"
chmod 0700 "${INSTALL_DIR}" "${INSTALL_BASE}"

# shellcheck source=/dev/null
source "${BMC_CREDENTIALS_FILE}"
# Credentials reach the python helpers through the environment (never argv).
for v in $(compgen -A variable | grep -E '^BMC_(USERNAME|PASSWORD)_'); do export "${v?}"; done
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
chmod 0700 "${WORK}"

# --- Generated blocks ------------------------------------------------------------------
indent() { local n="$1"; sed "s/^/$(printf '%*s' "${n}" '')/"; }
yaml_sq() { local s="$1"; printf "'%s'" "${s//\'/\'\'}"; }   # YAML single-quoted scalar

# Provisioning network
if [[ "${PROVISIONING_METHOD}" == "virtualmedia" ]]; then
  printf '    provisioningNetwork: "Disabled"\n' >"${WORK}/PROVISIONING"
  [[ -z "${CLUSTER_PROVISIONING_IP}" ]] || printf '    clusterProvisioningIP: %s\n' "${CLUSTER_PROVISIONING_IP}" >>"${WORK}/PROVISIONING"
  [[ -z "${BOOTSTRAP_PROVISIONING_IP}" ]] || printf '    bootstrapProvisioningIP: %s\n' "${BOOTSTRAP_PROVISIONING_IP}" >>"${WORK}/PROVISIONING"
  [[ -n "${CLUSTER_PROVISIONING_IP}" && -n "${BOOTSTRAP_PROVISIONING_IP}" ]] \
    || warn "CLUSTER_PROVISIONING_IP / BOOTSTRAP_PROVISIONING_IP not set; Red Hat asks for two reserved machine-network addresses when the provisioning network is disabled"
else
  printf '    provisioningNetwork: "Managed"\n    provisioningNetworkCIDR: %s\n    provisioningBridge: %s\n' \
    "${PROVISIONING_NETWORK_CIDR}" "${PROVISIONING_BRIDGE}" >"${WORK}/PROVISIONING"
fi

# Bootstrap VM static addressing and optional OS image
: >"${WORK}/BOOTSTRAP"
if [[ -n "${BOOTSTRAP_STATIC_IP}" ]]; then
  [[ -n "${BOOTSTRAP_STATIC_GATEWAY}" && -n "${BOOTSTRAP_STATIC_DNS}" ]] || die "set BOOTSTRAP_STATIC_GATEWAY and BOOTSTRAP_STATIC_DNS with BOOTSTRAP_STATIC_IP"
  printf '    bootstrapExternalStaticIP: %s\n    bootstrapExternalStaticGateway: %s\n    bootstrapExternalStaticDNS: %s\n' \
    "${BOOTSTRAP_STATIC_IP}" "${BOOTSTRAP_STATIC_GATEWAY}" "${BOOTSTRAP_STATIC_DNS}" >>"${WORK}/BOOTSTRAP"
fi
if [[ -n "${BOOTSTRAP_OS_IMAGE}" ]]; then
  [[ "${BOOTSTRAP_OS_IMAGE}" == *"sha256="* ]] || die "BOOTSTRAP_OS_IMAGE must include ?sha256=<uncompressed_sha256>"
  printf '    bootstrapOSImage: %s\n' "${BOOTSTRAP_OS_IMAGE}" >>"${WORK}/BOOTSTRAP"
fi

# Pre-install clock sync
{ echo "    additionalNTPServers:"; for s in ${NTP_SERVERS}; do echo "      - ${s}"; done; } >"${WORK}/NTP"

# BMC CA. Red Hat's 4.22 text shows the field as "bmcCACert" in examples and
# "bmcVerifyCA" in the parameter table; the 4.22 installer source accepts
# "bmcVerifyCA". Check with: openshift-install-fips explain installconfig.platform.baremetal
if [[ -n "${BMC_CA_BUNDLE}" ]]; then
  { echo "    bmcVerifyCA: |"; indent 6 <"${BMC_CA_BUNDLE}"; } >"${WORK}/BMC_CA"
else
  : >"${WORK}/BMC_CA"
fi

# Hosts with credentials injected (python keeps the YAML structure intact)
python3 - "${HOSTS_FILE}" "${PROVISIONING_METHOD}" >"${WORK}/HOSTS" <<'PY'
import os, re, sys, yaml
hosts = yaml.safe_load(open(sys.argv[1]))
method = sys.argv[2]
if not isinstance(hosts, list) or not hosts:
    sys.exit("hosts file must be a non-empty YAML list")
masters = [h for h in hosts if h.get("role") == "master"]
if len(masters) != 3:
    sys.exit(f"expected 3 hosts with role master, found {len(masters)}")
names, macs = set(), set()
for h in hosts:
    name = h.get("name") or sys.exit("a host has no name")
    if name in names: sys.exit(f"duplicate host name {name}")
    names.add(name)
    if h.get("role") not in ("master", "worker"): sys.exit(f"{name}: role must be master or worker")
    mac = (h.get("bootMACAddress") or "").lower()
    if not re.fullmatch(r"([0-9a-f]{2}:){5}[0-9a-f]{2}", mac): sys.exit(f"{name}: invalid bootMACAddress")
    if mac in macs: sys.exit(f"{name}: duplicate bootMACAddress {mac}")
    macs.add(mac)
    bmc = h.setdefault("bmc", {})
    addr = bmc.get("address") or sys.exit(f"{name}: bmc.address missing")
    scheme = addr.split("://", 1)[0]
    if method == "virtualmedia" and not scheme.endswith("virtualmedia"):
        sys.exit(f"{name}: {scheme}:// needs a provisioning network; use redfish-virtualmedia:// or idrac-virtualmedia://")
    if scheme in ("redfish+http",):
        sys.exit(f"{name}: redfish+http:// disables TLS to the BMC")
    if bmc.get("disableCertificateVerification") is True:
        sys.exit(f"{name}: disableCertificateVerification: true is not allowed; provide BMC_CA_BUNDLE instead")
    if method == "pxe" and h.get("networkConfig"):
        print(f"warning: {name}: networkConfig with a provisioning network; Red Hat says a fully static deployment requires virtual media", file=sys.stderr)
    if not h.get("rootDeviceHints"):
        print(f"warning: {name}: no rootDeviceHints; the installer will pick the first disk it finds", file=sys.stderr)
    var = re.sub(r"[^A-Z0-9]", "_", name.upper())
    user, pw = os.environ.get(f"BMC_USERNAME_{var}"), os.environ.get(f"BMC_PASSWORD_{var}")
    if not user or not pw:
        sys.exit(f"{name}: BMC_USERNAME_{var} / BMC_PASSWORD_{var} not set in the credentials file")
    bmc["username"], bmc["password"] = user, pw
out = yaml.safe_dump(hosts, default_flow_style=False, sort_keys=False)
print("\n".join("      " + l if l else l for l in out.splitlines()))
PY

# imageDigestSources from the oc-mirror IDMS: same mirrors/source structure
python3 - "${IDMS_FILE}" >"${WORK}/IMAGE_DIGEST_SOURCES" <<'PY'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
entries = []
for d in docs:
    if d.get("kind") != "ImageDigestMirrorSet":
        continue
    for m in d["spec"]["imageDigestMirrors"]:
        entries.append({"mirrors": m["mirrors"], "source": m["source"]})
if not any(e["source"].startswith("quay.io/openshift-release-dev/") for e in entries):
    sys.exit("IDMS has no quay.io/openshift-release-dev mirrors; was the release imported?")
print(yaml.safe_dump({"imageDigestSources": entries}, default_flow_style=False, sort_keys=False).rstrip())
PY

{ echo "additionalTrustBundle: |"; indent 2 <"${CA_BUNDLE_FILE}"; } >"${WORK}/ADDITIONAL_TRUST_BUNDLE"
jq -c . "${PULL_SECRET_FILE}" >"${WORK}/PULL_SECRET"
tr -d '\n' <"${SSH_PUBLIC_KEY_FILE}" >"${WORK}/SSH_KEY"

# --- Render ----------------------------------------------------------------------------
export_vars=(BASE_DOMAIN CLUSTER_NAME FIPS MACHINE_NETWORK_CIDR CLUSTER_NETWORK_CIDR
  CLUSTER_NETWORK_HOST_PREFIX SERVICE_NETWORK_CIDR COMPUTE_REPLICAS API_VIP INGRESS_VIP
  LOAD_BALANCER_TYPE EXTERNAL_BRIDGE)
for v in "${export_vars[@]}"; do export "${v?}"; done

python3 - "${INSTALL_SRC}/install-config.yaml.tmpl" "${WORK}" "${export_vars[@]}" >"${WORK}/out.yaml" <<'PY'
import os, re, sys
tmpl, work, names = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3:]
def block(m):
    text = open(os.path.join(work, m.group(1))).read().rstrip("\n")
    return text
# whole-line blocks ({{@X}} alone on a line) vs inline ('{{@X}}')
tmpl = re.sub(r"^\{\{@([A-Z_]+)\}\}$", block, tmpl, flags=re.M)
tmpl = re.sub(r"\{\{@([A-Z_]+)\}\}", lambda m: open(os.path.join(work, m.group(1))).read().strip().replace("'", "''"), tmpl)
for n in names:
    tmpl = tmpl.replace("{{%s}}" % n, os.environ[n])
left = re.findall(r"\{\{[@A-Z_]+\}\}", tmpl)
if left: sys.exit(f"unresolved placeholders: {left}")
tmpl = re.sub(r"\n{3,}", "\n\n", re.sub(r"^\s*\n(?=\s*\n)", "", tmpl, flags=re.M))
# Replace the template's header comment with a provenance header.
body = re.sub(r"\A(#[^\n]*\n)+", "", tmpl)
print("# Rendered by 03-install/03-render-install-config.sh - contains secrets, do not commit.\n" + body, end="")
PY
for v in $(compgen -A variable | grep -E '^BMC_(USERNAME|PASSWORD)_'); do unset "${v}"; done

# --- Validate --------------------------------------------------------------------------------
python3 - "${WORK}/out.yaml" <<'PY'
import sys, yaml, ipaddress
c = yaml.safe_load(open(sys.argv[1]))
bm = c["platform"]["baremetal"]
net = ipaddress.ip_network(c["networking"]["machineNetwork"][0]["cidr"])
for vip in bm["apiVIPs"] + bm["ingressVIPs"] + [bm[k] for k in ("clusterProvisioningIP", "bootstrapProvisioningIP") if k in bm and bm.get("provisioningNetwork") == "Disabled"]:
    if ipaddress.ip_address(vip) not in net:
        sys.exit(f"address {vip} is not in the machine network {net}")
if bm["apiVIPs"][0] == bm["ingressVIPs"][0]:
    sys.exit("API and ingress VIPs must differ")
assert c["fips"] in (True, False)
print("install-config.yaml parses; VIPs are in the machine network", file=sys.stderr)
PY

if command -v nmstatectl >/dev/null 2>&1; then
  python3 - "${HOSTS_FILE}" "${WORK}" <<'PY'
import sys, yaml, os
for h in yaml.safe_load(open(sys.argv[1])):
    if h.get("networkConfig"):
        open(os.path.join(sys.argv[2], "nmstate-" + h["name"] + ".yaml"), "w").write(yaml.safe_dump(h["networkConfig"]))
PY
  for f in "${WORK}"/nmstate-*.yaml; do
    [[ -e "${f}" ]] || continue
    nmstatectl gc "${f}" >/dev/null || die "nmstatectl gc rejected $(basename "${f}")"
  done
  log "networkConfig blocks pass 'nmstatectl gc'"
else
  warn "nmstatectl not found; networkConfig syntax not checked (the installer does not check it)"
fi

( umask 077; cp "${WORK}/out.yaml" "${OUT}"; cp "${WORK}/out.yaml" "${INSTALL_BASE}/install-config.${CLUSTER_NAME}.yaml.bak" )

# Redacted evidence copy: BMC passwords, pull secret auths removed.
python3 - "${OUT}" >"${WORK}/redacted.yaml" <<'PY'
import sys, yaml
c = yaml.safe_load(open(sys.argv[1]))
for h in c["platform"]["baremetal"]["hosts"]:
    h["bmc"]["password"] = "REDACTED"
c["pullSecret"] = "REDACTED"
print(yaml.safe_dump(c, default_flow_style=False, sort_keys=False), end="")
PY
keep_evidence "${WORK}/redacted.yaml" install-config.redacted.yaml
chmod 0600 "${EVIDENCE_DIR}/install-config.redacted.yaml"

log "wrote ${OUT} (contains secrets; mode 0600)"
log "redacted copy: ${EVIDENCE_DIR}/install-config.redacted.yaml"
log "next: 04-create-manifests.sh"
