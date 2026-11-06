#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 08-verify-transfer.sh: verify a transfer package before and after it moves.
#
# Run it on the low side against the copy on the transfer media, and again on
# the high side when the media arrives (SI-7, SA-12, MP-5).
#
# Checks:
#   1. SHA256SUMS.asc is a valid signature of SHA256SUMS by the transfer key
#   2. every file listed in SHA256SUMS is present and matches its checksum
#   3. no file is present that SHA256SUMS doesn't list (nothing was added)
#   4. the git bundle is readable
#
# Usage: 08-verify-transfer.sh <transfer-dir> [--key <armored-public-key>]
#   The key defaults to TRANSFER_VERIFY_KEY. Provision it on the high side out of
#   band; never trust a key that arrived inside the transfer it verifies.
#
# Manual equivalent (for the first transfer, before this script is on the high side):
#   gpg --dearmor <transfer-key.asc >transfer-key.gpg
#   gpgv --keyring ./transfer-key.gpg SHA256SUMS.asc SHA256SUMS
#   sha256sum --check --strict SHA256SUMS
# -----------------------------------------------------------------------------
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_cmd sha256sum gpg gpgv find git comm

DIR="${1:-}"
[[ -n "${DIR}" && -d "${DIR}" ]] || die "usage: $(basename "$0") <transfer-dir> [--key <public-key>]"
shift
while (($# > 0)); do
  case "$1" in
    --key) [[ -n "${2:-}" ]] || die "--key needs a file"; TRANSFER_VERIFY_KEY="$2"; shift ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done
DIR="$(cd "${DIR}" && pwd)"
[[ -f "${DIR}/SHA256SUMS" ]] || die "no SHA256SUMS in ${DIR}"

# 1. Signature
if [[ -f "${DIR}/SHA256SUMS.asc" ]]; then
  [[ -n "${TRANSFER_VERIFY_KEY}" && -r "${TRANSFER_VERIFY_KEY}" ]] \
    || die "SHA256SUMS.asc present but no verification key (set TRANSFER_VERIFY_KEY or use --key)"
  keyring="$(mktemp)"
  trap 'rm -f "${keyring}"' EXIT
  gpg --dearmor <"${TRANSFER_VERIFY_KEY}" >"${keyring}"
  gpgv --keyring "${keyring}" "${DIR}/SHA256SUMS.asc" "${DIR}/SHA256SUMS" \
    || die "SIGNATURE VERIFICATION FAILED; do not import this transfer"
  log "signature on SHA256SUMS is valid"
elif [[ "${REQUIRE_TRANSFER_SIGNATURE}" == "true" ]]; then
  die "SHA256SUMS.asc is missing and REQUIRE_TRANSFER_SIGNATURE=true"
else
  warn "transfer is not signed"
fi

# 2. Checksums
log "checking $(wc -l <"${DIR}/SHA256SUMS") file(s); this can take a while for large archives"
( cd "${DIR}" && sha256sum --check --strict --quiet SHA256SUMS ) \
  || die "CHECKSUM VERIFICATION FAILED; do not import this transfer"
log "all checksums match"

# 3. Unexpected files
unexpected="$(
  cd "${DIR}" &&
  comm -13 \
    <(sed -E 's/^[0-9a-f]{64}  //' SHA256SUMS | LC_ALL=C sort) \
    <(find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.asc ! -name transfer-record.md \
        -printf '%P\n' | LC_ALL=C sort)
)"
[[ -z "${unexpected}" ]] || die "files not listed in SHA256SUMS were found:
${unexpected}"
log "no unexpected files"

# 4. Repository bundle
if [[ -f "${DIR}/repo/ocp-itsg-33.bundle" ]]; then
  git bundle list-heads "${DIR}/repo/ocp-itsg-33.bundle" >/dev/null 2>&1 \
    || die "git bundle is not readable"
  log "git bundle: $(git bundle list-heads "${DIR}/repo/ocp-itsg-33.bundle" | head -1)"
fi

log "transfer $(basename "${DIR}") VERIFIED; SHA256SUMS digest $(sha256sum "${DIR}/SHA256SUMS" | cut -d' ' -f1)"
