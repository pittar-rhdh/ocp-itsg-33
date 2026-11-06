#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 02-approve-installplans.sh: list and approve Operator install plans (CM-3,
# SI-2). Every Subscription in this repository uses manual approval, so an
# operator is installed or updated only when a person approves the plan under
# a change ticket. Each approval is recorded in EVIDENCE_DIR/changes.tsv.
#
# Usage:
#   02-approve-installplans.sh                       list pending install plans
#   CHANGE_ID=<ticket> 02-approve-installplans.sh <namespace>/<installplan> [...]
#   CHANGE_ID=<ticket> 02-approve-installplans.sh --all-in-repo
#       approve every pending plan in a namespace that has a Subscription
#       from this repository (initial install only; review the list first)
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

use_cluster_oc
require_cluster_admin

pending="$(pending_installplans)"
if [[ $# -eq 0 ]]; then
  if [[ -z "${pending}" ]]; then log "no pending install plans"; exit 0; fi
  printf '%-45s %-16s %s\n' NAMESPACE INSTALLPLAN CSVS
  while IFS=$'\t' read -r ns name csvs; do
    printf '%-45s %-16s %s\n' "${ns}" "${name}" "${csvs}"
  done <<<"${pending}"
  log "review the CSV versions against the change ticket, then approve with <namespace>/<installplan>"
  exit 0
fi

require_change_id
targets=()
if [[ "$1" == "--all-in-repo" ]]; then
  # Namespaces of the Subscriptions in this cluster's overlay.
  mapfile -t repo_ns < <(oc kustomize "${OVERLAY_DIR}/operators" \
    | awk '/^kind: Subscription/{s=1} s && /^  namespace:/{print $2; s=0}' | sort -u)
  while IFS=$'\t' read -r ns name _; do
    [[ -n "${ns}" ]] || continue
    for r in "${repo_ns[@]}"; do [[ "${r}" == "${ns}" ]] && targets+=("${ns}/${name}"); done
  done <<<"${pending}"
  ((${#targets[@]} > 0)) || { log "nothing to approve"; exit 0; }
else
  targets=("$@")
fi

for t in "${targets[@]}"; do
  [[ "${t}" == */* ]] || die "expected <namespace>/<installplan>, got ${t}"
  ns="${t%%/*}" name="${t#*/}"
  grep -q "^${ns}"$'\t'"${name}"$'\t' <<<"${pending}" || die "${t} is not a pending install plan"
  approve_installplan "${ns}" "${name}"
done
