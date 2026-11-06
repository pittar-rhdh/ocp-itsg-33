#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 05-lock-down-access.sh: finish the access-control baseline once the identity
# provider works (AC-2, AC-6, IA-2, IA-5).
#
#   1. Checks that YOU are logged in through the identity provider (not
#      kube:admin, not the installer kubeconfig) and are cluster-admin through
#      the ocp-platform-admins group binding from Git.
#   2. Removes project self-provisioning (projects come through Git or a
#      ticket) and stops the API server from restoring it.
#   3. Deletes the kubeadmin secret.
#
# The installer kubeconfig (system:admin certificate) still works afterwards:
# keep it offline as the break-glass credential, under dual control.
# Without --confirm, only the checks run.
# Usage: CHANGE_ID=<ticket> 05-lock-down-access.sh [--confirm]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

CONFIRM=false
[[ "${1:-}" == "--confirm" ]] && CONFIRM=true

use_cluster_oc
require_cluster_admin

me="$(oc whoami)"
case "${me}" in
  kube:admin|system:admin|system:*) die "log in as an identity-provider user (now: ${me})" ;;
esac
groups="$(oc get groups -o json | jq -r --arg u "${me}" \
  '.items[] | select((.users // []) | index($u)) | .metadata.name')"
grep -qx ocp-platform-admins <<<"${groups}" \
  || die "${me} is not in group ocp-platform-admins (check the IdP groups claim and the rbac component)"
oc get clusterrolebinding itsg33-platform-admins >/dev/null 2>&1 \
  || die "ClusterRoleBinding itsg33-platform-admins not found (sync the itsg33-config application)"
[[ "$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].type}')" == *OpenID* ]] \
  || die "no OpenID identity provider in oauth/cluster"
log "checks passed: ${me} is a platform admin through the identity provider"

if [[ "${CONFIRM}" != true ]]; then
  log "dry run: re-run with --confirm to remove self-provisioning and kubeadmin"
  exit 0
fi
require_change_id

oc patch clusterrolebinding.rbac self-provisioners -p '{"subjects": null}' >/dev/null
oc annotate clusterrolebinding.rbac self-provisioners \
  'rbac.authorization.kubernetes.io/autoupdate=false' --overwrite >/dev/null
record_change self-provisioning-removed "clusterrolebinding/self-provisioners"
log "self-provisioning removed"

if oc get secret kubeadmin -n kube-system >/dev/null 2>&1; then
  oc delete secret kubeadmin -n kube-system
  record_change kubeadmin-removed "kube-system/kubeadmin"
  log "kubeadmin removed"
else
  log "kubeadmin already removed"
fi
