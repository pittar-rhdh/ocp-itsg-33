#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 04-rhacs-register-cluster.sh: connect the SecuredCluster to Central on the
# same cluster (RA-5, SI-4). Generates a cluster registration secret (CRS) with
# `roxctl central crs generate` and applies it to RHACS_NAMESPACE without
# writing it to disk (it contains credentials, IA-5).
#
# Run once, after Central (from Git) is available. The CRS has an expiry
# date; record it, and generate a new one before it expires for any cluster
# that still has to be registered.
#
# Authentication: ROX_API_TOKEN_FILE (Admin role), or the Central admin
# password from the central-htpasswd secret (initial setup only).
# TLS: Central's CA (secret central-tls, key ca.pem) is used to verify the
# endpoint; no TLS verification is skipped.
#
# Usage: CHANGE_ID=<ticket> 04-rhacs-register-cluster.sh
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=SCRIPTDIR/lib/rhacs.sh
source "${GITOPS_DIR}/lib/rhacs.sh"

use_cluster_oc
require_cluster_admin
require_change_id
rhacs_init

if oc get secret cluster-registration-secret -n "${RHACS_NAMESPACE}" >/dev/null 2>&1; then
  log "cluster-registration-secret already exists in ${RHACS_NAMESPACE}; nothing to do"
  exit 0
fi

log "generating CRS ${RHACS_CRS_NAME} on ${ROX_ENDPOINT}"
roxctl_central central crs generate "${RHACS_CRS_NAME}" --output - \
  | oc apply -n "${RHACS_NAMESPACE}" -f -
record_change rhacs-crs-applied "${RHACS_CRS_NAME} -> ${RHACS_NAMESPACE}"
expiry="$(oc get secret cluster-registration-secret -n "${RHACS_NAMESPACE}" \
  -o jsonpath='{.metadata.annotations.crs\.platform\.stackrox\.io/expires-at}' 2>/dev/null || true)"
log "CRS applied (expires ${expiry:-unknown}). The SecuredCluster now connects to Central."
