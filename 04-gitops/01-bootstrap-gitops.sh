#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 01-bootstrap-gitops.sh: install OpenShift GitOps from the mirrored catalog and
# hand the cluster over to Git (CM-2, CM-3, CM-5, AC-6).
#
#   1. Checks: cluster-admin, the mirrored catalog source, the package, the
#      Git CA and token files, and that root-app.yaml points at GIT_REMOTE_URL.
#   2. --apply: server-side apply 04-gitops/bootstrap (operator subscription,
#      manual approval) and approve the first install plan (recorded, CM-3).
#   3. Wait for the operator and the default Argo CD instance.
#   4. Trust the Git server CA (argocd-tls-certs-cm) and add the read-only
#      repository credential (Secret, label argocd.argoproj.io/secret-type).
#   5. Apply overlays/<cluster>/root-app.yaml. From here on, Git is the source.
#
# Without --apply, only the checks run.
# Usage: CHANGE_ID=<ticket> 01-bootstrap-gitops.sh [--apply]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

use_cluster_oc
require_cluster_admin

# --- 1. Checks ------------------------------------------------------------------------
[[ -d "${OVERLAY_DIR}" ]] || die "no overlay for ${CLUSTER_NAME}: ${OVERLAY_DIR}"
oc get catalogsource "${CATALOG_SOURCE}" -n openshift-marketplace >/dev/null 2>&1 \
  || die "catalog source ${CATALOG_SOURCE} not found (Phase 3 06-post-install.sh --configure)"
oc get packagemanifest openshift-gitops-operator -n openshift-marketplace >/dev/null 2>&1 \
  || die "openshift-gitops-operator is not in the mirrored catalogs"
grep -q "value: ${CATALOG_SOURCE}\$" "${GITOPS_DIR}/bootstrap/kustomization.yaml" \
  || die "bootstrap/kustomization.yaml does not use catalog source ${CATALOG_SOURCE}"
grep -q "repoURL: ${GIT_REMOTE_URL}\$" "${OVERLAY_DIR}/root-app.yaml" \
  || die "root-app.yaml repoURL is not ${GIT_REMOTE_URL} (GIT_REMOTE_URL)"
[[ -r "${GIT_CA_FILE}" ]] || die "Git CA bundle not readable: ${GIT_CA_FILE}"
[[ -r "${GIT_TOKEN_FILE}" ]] || die "Git token file not readable: ${GIT_TOKEN_FILE}"
[[ "$(stat -c %a "${GIT_TOKEN_FILE}")" == "600" ]] || die "${GIT_TOKEN_FILE} must be mode 0600"
git_host="$(sed -E 's#^https://([^/:]+).*#\1#' <<<"${GIT_REMOTE_URL}")"
[[ "${GIT_REMOTE_URL}" == https://* ]] || die "GIT_REMOTE_URL must be https:// (SC-8)"
log "checks passed (Git ${git_host}, catalog ${CATALOG_SOURCE})"

if [[ "${APPLY}" != true ]]; then
  log "dry run: re-run with --apply to install OpenShift GitOps and apply the root application"
  exit 0
fi
require_change_id

# --- 2. Operator subscription -------------------------------------------------------------
oc kustomize "${GITOPS_DIR}/bootstrap" \
  | oc apply --server-side --field-manager=itsg33-bootstrap -f -
record_change bootstrap-applied "04-gitops/bootstrap @ $(git_state)"

ns=openshift-gitops-operator
wait_for "install plan in ${ns}" 600 \
  oc get subscription.operators.coreos.com openshift-gitops-operator -n "${ns}" \
  -o jsonpath='{.status.installPlanRef.name}' --allow-missing-template-keys=false
ip="$(oc get subscription.operators.coreos.com openshift-gitops-operator -n "${ns}" \
  -o jsonpath='{.status.installPlanRef.name}')"
if [[ "$(oc get installplan.operators.coreos.com "${ip}" -n "${ns}" -o jsonpath='{.spec.approved}')" != true ]]; then
  approve_installplan "${ns}" "${ip}"
fi

# --- 3. Operator and Argo CD ready -------------------------------------------------------
csv_ok() {
  [[ "$(oc get subscription.operators.coreos.com openshift-gitops-operator -n "${ns}" \
    -o jsonpath='{.status.installedCSV}')" != "" ]] \
  && [[ "$(oc get csv "$(oc get subscription.operators.coreos.com openshift-gitops-operator \
    -n "${ns}" -o jsonpath='{.status.installedCSV}')" -n "${ns}" -o jsonpath='{.status.phase}')" == Succeeded ]]
}
wait_for "OpenShift GitOps operator" 900 csv_ok
wait_for "Argo CD instance ${GITOPS_NAMESPACE}" 900 \
  oc wait argocd.argoproj.io/openshift-gitops -n "${GITOPS_NAMESPACE}" \
  --for=jsonpath='{.status.phase}'=Available --timeout=5s

# --- 4. Git trust and repository credential ---------------------------------------------
# The operator reads spec.tls.initialCerts only when it creates the instance,
# so the CA goes straight into the ConfigMap that Argo CD uses for Git TLS.
oc create configmap argocd-tls-certs-cm -n "${GITOPS_NAMESPACE}" \
  --from-file="${git_host}=${GIT_CA_FILE}" --dry-run=client -o json \
  | jq '{data: .data}' \
  | oc patch configmap argocd-tls-certs-cm -n "${GITOPS_NAMESPACE}" --type merge --patch-file /dev/stdin
# Strip the trailing newline from the token without putting it on a command line.
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
tr -d '\r\n' <"${GIT_TOKEN_FILE}" >"${tmp}/password"
oc create secret generic itsg33-gitops-repo -n "${GITOPS_NAMESPACE}" \
  --from-literal=type=git \
  --from-literal=url="${GIT_REMOTE_URL}" \
  --from-literal=username="${GIT_USERNAME}" \
  --from-file=password="${tmp}/password" \
  --dry-run=client -o yaml \
  | oc label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
  | oc apply -f -
record_change gitops-repo-credentials "${GIT_REMOTE_URL} as ${GIT_USERNAME} (CA ${git_host})"

# --- 5. Root application ----------------------------------------------------------------------
oc apply -f "${OVERLAY_DIR}/root-app.yaml"
record_change root-app-applied "overlays/${CLUSTER_NAME}/root-app.yaml @ $(git_state)"
log "root application applied. Next: approve operator install plans with 02-approve-installplans.sh"
log "Argo CD: https://$(oc get route openshift-gitops-server -n "${GITOPS_NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null)"
