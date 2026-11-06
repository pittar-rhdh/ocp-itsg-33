#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 08-publish-repo.sh: publish the copy of this repository that arrived in an
# accepted transfer to the departmental Git server (AD-12).
#
#   1. Check that the bundle's branch head is the commit recorded in MANIFEST.json.
#   2. Fetch it into a local clone (GIT_LOCAL_CLONE).
#   3. Fast-forward GIT_BRANCH and push to GIT_REMOTE_URL.
#
# Only fast-forwards are allowed: the high-side history must never diverge from
# the reviewed low-side history (CM-3, CM-5). High-side-only changes (for
# example, cluster overlays) belong on a separate branch.
#
# Credentials for GIT_REMOTE_URL come from your normal Git credential helper or
# SSH agent; nothing is stored by this script.
#
# Usage: 08-publish-repo.sh <transfer-id> [--no-push]
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd git jq

ID="${1:-}"
[[ -n "${ID}" ]] || die "usage: $(basename "$0") <transfer-id> [--no-push]"
PUSH=true
[[ "${2:-}" == "--no-push" ]] && PUSH=false

T="$(accepted_transfer "${ID}")"
BUNDLE="${T}/repo/ocp-itsg-33.bundle"
[[ -f "${BUNDLE}" ]] || die "transfer ${ID} has no repository bundle"
git bundle verify "${BUNDLE}" >/dev/null 2>&1 || die "bundle failed git verification (it may need history the clone doesn't have)"

want_commit="$(jq -r .repository.commit "${T}/MANIFEST.json")"
[[ "${want_commit}" != *-dirty ]] || die "transfer was built from a dirty working tree; refusing to publish"
src_branch="$(jq -r .repository.branch "${T}/MANIFEST.json")"
head="$(git bundle list-heads "${BUNDLE}" "refs/heads/${src_branch}" | awk '{print $1}')"
[[ "${head}" == "${want_commit}" ]] || die "bundle head ${head:-<none>} != manifest commit ${want_commit}"

if [[ ! -d "${GIT_LOCAL_CLONE}/.git" ]]; then
  log "creating ${GIT_LOCAL_CLONE}"
  mkdir -p "$(dirname "${GIT_LOCAL_CLONE}")"
  if git ls-remote "${GIT_REMOTE_URL}" >/dev/null 2>&1; then
    git clone --quiet "${GIT_REMOTE_URL}" "${GIT_LOCAL_CLONE}"
  else
    warn "cannot reach ${GIT_REMOTE_URL}; starting from the bundle"
    git clone --quiet --branch "${src_branch}" "${BUNDLE}" "${GIT_LOCAL_CLONE}"
    git -C "${GIT_LOCAL_CLONE}" remote set-url origin "${GIT_REMOTE_URL}"
  fi
fi

G=(git -C "${GIT_LOCAL_CLONE}")
"${G[@]}" fetch --quiet "${BUNDLE}" "refs/heads/${src_branch}:refs/remotes/transfer/${src_branch}"
if "${G[@]}" rev-parse --verify --quiet "refs/heads/${GIT_BRANCH}" >/dev/null; then
  "${G[@]}" checkout --quiet "${GIT_BRANCH}"
  "${G[@]}" merge --quiet --ff-only "${want_commit}" \
    || die "${GIT_BRANCH} has diverged from the low-side history; investigate before publishing"
else
  "${G[@]}" checkout --quiet -b "${GIT_BRANCH}" "${want_commit}"
fi
log "${GIT_BRANCH} is at ${want_commit}"

# Tag the import so the high side can always find which transfer delivered what.
"${G[@]}" tag -f "transfer/${ID}" "${want_commit}" >/dev/null

if ${PUSH}; then
  "${G[@]}" push --quiet origin "${GIT_BRANCH}" "refs/tags/transfer/${ID}"
  log "pushed ${GIT_BRANCH} and tag transfer/${ID} to ${GIT_REMOTE_URL}"
fi
