#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 06-post-install.sh: verify the new cluster and apply the first Day-1 settings.
# EXAMPLE, not validated.
#
# Verify (default):
#   cluster version and operators, nodes, FIPS on every node, boot disk
#   encryption, IPsec mode, chrony sources, mirror configuration, BareMetalHosts
# --configure (then verify):
#   - disable the default (internet) OperatorHub sources            (CM-7)
#   - apply mirrored catalogs, ITMS, and release signatures from
#     INPUTS_DIR/cluster-resources (oc-mirror output; UpdateService is
#     left for Phase 6, because its CRD needs the OSUS operator)    (CM-11, SI-7)
#   - etcd encryption (aesgcm)                                      (SC-28)
#   - API server audit profile WriteRequestBodies                   (AU-2, AU-12)
# Phase 4 (GitOps) takes ownership of these settings later.
#
# Usage: KUBECONFIG=<install-dir>/auth/kubeconfig 06-post-install.sh [--configure]
# -----------------------------------------------------------------------------
# pass/wrn/fail only print (and count), so "test && pass || fail" is safe here.
# shellcheck disable=SC2015
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd oc jq

CONFIGURE=false
[[ "${1:-}" == "--configure" ]] && CONFIGURE=true
: "${KUBECONFIG:=${INSTALL_DIR}/auth/kubeconfig}"
export KUBECONFIG
oc whoami >/dev/null 2>&1 || die "cannot reach the cluster with KUBECONFIG=${KUBECONFIG}"
CR_DIR="${INPUTS_DIR}/cluster-resources"

if ${CONFIGURE}; then
  log "disabling the default OperatorHub sources"
  oc patch operatorhub cluster --type merge -p '{"spec":{"disableAllDefaultSources":true}}'

  [[ -d "${CR_DIR}" ]] || die "no ${CR_DIR}; copy the current cluster-resources directory from the registry host"
  for f in "${CR_DIR}"/*.yaml; do
    [[ -e "${f}" ]] || continue
    if [[ "$(basename "${f}")" == "updateService.yaml" ]]; then
      log "skipping updateService.yaml (Phase 6, needs the OSUS operator)"
      continue
    fi
    log "applying $(basename "${f}")"
    oc apply -f "${f}"
  done

  log "enabling etcd encryption (aesgcm) and the WriteRequestBodies audit profile"
  oc patch apiserver cluster --type merge \
    -p '{"spec":{"encryption":{"type":"aesgcm"},"audit":{"profile":"WriteRequestBodies"}}}'
  log "etcd encryption runs in the background; it can take some time to finish"
fi

FAILS=0
pass() { printf '  [PASS] %s\n' "$*"; }
wrn()  { printf '  [WARN] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }
REPORT="${EVIDENCE_DIR}/post-install-$(stamp).txt"
mkdir -p "${EVIDENCE_DIR}"

{
echo "Post-install verification of $(oc whoami --show-server) at $(date -u +%FT%TZ)"

echo "Cluster version and operators"
cv="$(oc get clusterversion version -o json)"
ver="$(jq -r '.status.desired.version' <<<"${cv}")"
img="$(jq -r '.status.desired.image' <<<"${cv}")"
avail="$(jq -r '.status.conditions[] | select(.type=="Available") | .status' <<<"${cv}")"
[[ "${avail}" == "True" ]] && pass "ClusterVersion ${ver} Available" || fail "ClusterVersion not Available"
load_release
[[ "${img}" == *"${OCP_RELEASE_DIGEST}" ]] && pass "running the transferred release digest" || fail "release image ${img} is not ${OCP_RELEASE_DIGEST}"
bad="$(oc get clusteroperators -o json | jq -r '.items[] | select(any(.status.conditions[]; (.type=="Available" and .status!="True") or (.type=="Degraded" and .status=="True"))) | .metadata.name')"
[[ -z "${bad}" ]] && pass "all cluster operators Available and not Degraded" || fail "operators not healthy: $(tr '\n' ' ' <<<"${bad}")"

echo "Nodes"
notready="$(oc get nodes -o json | jq -r '.items[] | select(any(.status.conditions[]; .type=="Ready" and .status!="True")) | .metadata.name')"
[[ -z "${notready}" ]] && pass "$(oc get nodes --no-headers | wc -l) nodes Ready" || fail "nodes not Ready: ${notready}"
bmh="$(oc get baremetalhosts -n openshift-machine-api -o json | jq -r '.items[] | "\(.metadata.name) \(.status.provisioning.state)"')"
grep -qv ' provisioned$\| externally provisioned$' <<<"${bmh}" && wrn "BareMetalHosts not provisioned: $(grep -v ' provisioned$' <<<"${bmh}" | tr '\n' ';')" || pass "all BareMetalHosts provisioned"

echo "Install-time security settings (per node, via oc debug)"
for n in $(oc get nodes -o name); do
  out="$(oc debug "${n}" --quiet -- chroot /host sh -c \
    'cat /proc/sys/crypto/fips_enabled; lsblk -nr -o TYPE | grep -c "^crypt$"; chronyc -n sources | grep -c "^\^\*"' 2>/dev/null || true)"
  read -r fipsv cryptv chronyv <<<"$(tr '\n' ' ' <<<"${out}")"
  [[ "${FIPS}" != "true" || "${fipsv}" == "1" ]] && pass "${n#node/}: FIPS ${fipsv}" || fail "${n#node/}: FIPS not enabled (${fipsv:-unknown})"
  if [[ "${DISK_ENCRYPTION}" == "tpm2" ]]; then
    [[ "${cryptv:-0}" -ge 1 ]] && pass "${n#node/}: LUKS (crypt) device present" || fail "${n#node/}: no LUKS device; boot disk not encrypted"
  fi
  [[ "${chronyv:-0}" -ge 1 ]] && pass "${n#node/}: chrony has a selected source" || fail "${n#node/}: chrony has no selected source"
done

echo "Network"
mode="$(oc get network.operator cluster -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.ipsecConfig.mode}')"
[[ "${mode}" == "${IPSEC_MODE}" ]] && pass "IPsec mode ${mode}" || fail "IPsec mode '${mode}' (expected ${IPSEC_MODE})"

echo "Content sources"
[[ "$(oc get operatorhub cluster -o jsonpath='{.spec.disableAllDefaultSources}')" == "true" ]] \
  && pass "default OperatorHub sources disabled" || wrn "default OperatorHub sources are still enabled (run with --configure)"
idms="$(oc get imagedigestmirrorsets -o name | wc -l)"
((idms > 0)) && pass "${idms} ImageDigestMirrorSet(s)" || fail "no ImageDigestMirrorSet"
cs="$(oc get catalogsource -n openshift-marketplace -o json | jq -r '.items[] | "\(.metadata.name)=\(.status.connectionState.lastObservedState // "unknown")"' | tr '\n' ' ')"
[[ -n "${cs}" ]] && pass "catalog sources: ${cs}" || wrn "no catalog sources yet (run with --configure)"

echo "API server"
enc="$(oc get apiserver cluster -o jsonpath='{.spec.encryption.type}')"
[[ "${enc}" == "aesgcm" || "${enc}" == "aescbc" ]] && pass "etcd encryption ${enc}" || wrn "etcd encryption not enabled (run with --configure)"
encst="$(oc get openshiftapiserver cluster -o jsonpath='{.status.conditions[?(@.type=="Encrypted")].reason}' 2>/dev/null || true)"
[[ -n "${encst}" ]] && echo "  [INFO] OpenShift API server encryption status: ${encst}"
aud="$(oc get apiserver cluster -o jsonpath='{.spec.audit.profile}')"
[[ "${aud}" == "WriteRequestBodies" || "${aud}" == "AllRequestBodies" ]] && pass "audit profile ${aud}" || wrn "audit profile '${aud:-Default}' (run with --configure)"

echo "Accounts"
oc get secret kubeadmin -n kube-system >/dev/null 2>&1 \
  && wrn "kubeadmin still exists: remove it after the identity provider and an admin group work (Phase 4, AC-2)" \
  || pass "kubeadmin removed"
} 2>&1 | tee "${REPORT}"

FAILS="$(grep -c '\[FAIL\]' "${REPORT}" || true)"
( cd "${EVIDENCE_DIR}" && sha256sum "$(basename "${REPORT}")" >>SHA256SUMS )
((FAILS == 0)) || die "${FAILS} check(s) failed; report: ${REPORT}"
log "post-install checks passed; report: ${REPORT}"
