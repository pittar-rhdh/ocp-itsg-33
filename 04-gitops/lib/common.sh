# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Helpers for the Phase 4 (GitOps) scripts. Source, don't execute.
# Loads the high-side settings (Git remote, tools, ledger) and then
# 04-gitops/settings.env.
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/../../02-high-side/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/02-high-side/lib/common.sh"

GITOPS_DIR="${REPO_ROOT}/04-gitops"
load_settings "${GITOPS_DIR}/settings.env"
# shellcheck disable=SC2034  # used by the scripts that source this file
OVERLAY_DIR="${GITOPS_DIR}/overlays/${CLUSTER_NAME}"

# Use oc from the accepted transfer when it is there (matches the cluster).
use_cluster_oc() {
  local dir="${HS_TOOLS_DIR}/${OCP_MAX_VERSION}/bin"
  if [[ -x "${dir}/oc" ]]; then PATH="${dir}:${PATH}"; export PATH; fi
  require_cmd oc jq
}

# Fail unless logged in to the cluster with cluster-admin rights.
require_cluster_admin() {
  local who
  who="$(oc whoami 2>/dev/null)" || die "not logged in to a cluster (set KUBECONFIG or oc login)"
  [[ "$(oc auth can-i '*' '*' --all-namespaces 2>/dev/null)" == "yes" ]] \
    || die "${who} is not cluster-admin"
  log "cluster: $(oc whoami --show-server)  user: ${who}"
}

# A change ticket is required for actions that change the cluster (CM-3).
require_change_id() {
  [[ -n "${CHANGE_ID}" ]] || die "set CHANGE_ID to the approved change ticket (CM-3)"
}

# Append a record to the Phase 4 change log (tab-separated, append-only):
#   time  change-id  user(oc)  user(host)  action  detail
record_change() {
  local action="$1" detail="${2:--}" file="${EVIDENCE_DIR}/changes.tsv"
  mkdir -p "${EVIDENCE_DIR}"
  if [[ ! -f "${file}" ]]; then
    printf 'time\tchange_id\tcluster_user\thost_user\taction\tdetail\n' >"${file}"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "${CHANGE_ID:--}" \
    "$(oc whoami 2>/dev/null || echo -)" "$(id -un)" "${action}" "${detail}" >>"${file}"
}

# wait_for <description> <timeout-seconds> <command...>: poll every 10 s.
wait_for() {
  local what="$1" timeout="$2" start
  shift 2
  start="$(date +%s)"
  until "$@" >/dev/null 2>&1; do
    (( $(date +%s) - start < timeout )) || die "timed out after ${timeout}s waiting for ${what}"
    sleep 10
  done
  log "ready: ${what}"
}

# Pending (unapproved) install plans: "namespace<TAB>name<TAB>csv,csv".
pending_installplans() {
  oc get installplans.operators.coreos.com -A -o json \
    | jq -r '.items[] | select(.spec.approved == false)
             | [.metadata.namespace, .metadata.name, (.spec.clusterServiceVersionNames | join(","))]
             | @tsv'
}

# approve_installplan <namespace> <name>: approve and record it.
approve_installplan() {
  local ns="$1" name="$2" csvs
  csvs="$(oc get installplan.operators.coreos.com "${name}" -n "${ns}" \
    -o jsonpath='{.spec.clusterServiceVersionNames}')"
  oc patch installplan.operators.coreos.com "${name}" -n "${ns}" --type merge \
    -p '{"spec":{"approved":true}}' >/dev/null
  record_change installplan-approved "${ns}/${name} ${csvs}"
  log "approved ${ns}/${name}: ${csvs}"
}
