#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 07-validate.sh: checks every change to 04-gitops before it is merged (CM-3,
# CM-4, SA-11). Run it in CI on the low side and before every merge on the
# high side. No cluster access is needed (except with --server).
#
#   1. Render bootstrap/ and every overlay layer with kustomize.
#   2. Repository rules (python3 with PyYAML):
#        - every object carries an itsg33/controls annotation
#        - no Secret objects in Git (IA-5, SC-28)
#        - every Subscription: installPlanApproval Manual, one catalog source
#        - one Git URL for the root app, the child apps, and the AppProject
#        - no CHACHA20 ciphers (not FIPS-approved), no insecureSkipVerify
#   3. yamllint, kubeconform and shellcheck, when they are installed.
#   4. --server: also `oc apply --dry-run=server` each layer (needs a cluster;
#      resources whose CRDs are not installed yet are reported, not fatal).
#
# Usage: 07-validate.sh [--server]
# -----------------------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Only the generic helpers: CI does not need the high-side settings.
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "${HERE}/../lib/common.sh"
load_settings "${HERE}/settings.env"

SERVER=false
[[ "${1:-}" == "--server" ]] && SERVER=true

if command -v kustomize >/dev/null 2>&1; then KUSTOMIZE=(kustomize build)
elif command -v oc >/dev/null 2>&1; then KUSTOMIZE=(oc kustomize)
else die "need kustomize or oc"; fi
require_cmd python3
python3 -c 'import yaml' 2>/dev/null || die "python3 needs PyYAML (dnf install python3-pyyaml)"

OUT="$(mktemp -d)"
trap 'rm -rf "${OUT}"' EXIT
fail=0

# --- 1. Render ------------------------------------------------------------------------------
layers=("${HERE}/bootstrap")
for o in "${HERE}"/overlays/*/; do
  for l in apps gitops operators config policies; do
    [[ -d "${o}${l}" ]] && layers+=("${o}${l}")
  done
done
for l in "${layers[@]}"; do
  rel="${l#"${HERE}/"}"
  out="${OUT}/${rel//\//_}.yaml"
  if "${KUSTOMIZE[@]}" "${l}" >"${out}" 2>"${OUT}/err"; then
    log "rendered ${rel} ($(grep -c '^kind:' "${out}") objects)"
  else
    warn "kustomize failed for ${rel}: $(cat "${OUT}/err")"; fail=1
  fi
done

# --- 2. Repository rules -------------------------------------------------------------------
python3 - "${OUT}" "${HERE}" <<'PY' || fail=1
import glob, os, sys, yaml
out, here = sys.argv[1], sys.argv[2]
errors = []
sources, urls = set(), set()
for path in sorted(glob.glob(os.path.join(out, "*.yaml"))):
    layer = os.path.basename(path)[:-5]
    for doc in yaml.safe_load_all(open(path)):
        if not doc:
            continue
        kind, meta = doc.get("kind"), doc.get("metadata", {})
        ref = f"{layer}: {kind}/{meta.get('namespace', '-')}/{meta.get('name')}"
        if not (meta.get("annotations") or {}).get("itsg33/controls"):
            errors.append(f"{ref}: no itsg33/controls annotation")
        if kind == "Secret":
            errors.append(f"{ref}: Secrets must not be stored in Git")
        if kind == "Subscription":
            spec = doc.get("spec", {})
            if spec.get("installPlanApproval") != "Manual":
                errors.append(f"{ref}: installPlanApproval must be Manual (CM-3)")
            sources.add(spec.get("source"))
        if kind == "Application":
            urls.add(doc["spec"]["source"]["repoURL"])
        if kind == "AppProject":
            urls.update(doc["spec"].get("sourceRepos", []))
        text = yaml.safe_dump(doc)
        if "CHACHA20" in text.upper():
            errors.append(f"{ref}: CHACHA20 cipher (not FIPS-approved)")
        if "insecureSkipVerify: true" in text:
            errors.append(f"{ref}: insecureSkipVerify is not allowed (SC-8)")
for root in glob.glob(os.path.join(here, "overlays", "*", "root-app.yaml")):
    urls.add(yaml.safe_load(open(root))["spec"]["source"]["repoURL"])
if len(sources) > 1:
    errors.append(f"Subscriptions use more than one catalog source: {sorted(sources)}")
if len(urls) > 1:
    errors.append(f"more than one Git URL: {sorted(urls)}")
for e in errors:
    print(f"RULE  {e}")
print(f"repository rules: {len(errors)} problem(s)")
sys.exit(1 if errors else 0)
PY

# --- 3. Linters (optional) ---------------------------------------------------------------------
if command -v yamllint >/dev/null 2>&1; then
  yamllint -s -d '{extends: default, rules: {line-length: disable, document-start: disable,
    comments: {min-spaces-from-content: 1}, comments-indentation: disable,
    braces: {max-spaces-inside: 1}, truthy: {check-keys: false}}}' "${HERE}" || fail=1
else warn "yamllint not installed; skipped"; fi

if command -v kubeconform >/dev/null 2>&1; then
  schema_args=(-schema-location "${KUBECONFORM_K8S_SCHEMAS}")
  [[ -z "${KUBECONFORM_LOCAL_SCHEMAS}" ]] || schema_args+=(-schema-location \
    "${KUBECONFORM_LOCAL_SCHEMAS}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json")
  [[ -z "${KUBECONFORM_CRD_CATALOG}" ]] || schema_args+=(-schema-location \
    "${KUBECONFORM_CRD_CATALOG}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json")
  kubeconform -strict -summary -ignore-missing-schemas "${schema_args[@]}" "${OUT}"/*.yaml || fail=1
else warn "kubeconform not installed; skipped"; fi

if command -v shellcheck >/dev/null 2>&1; then
  (cd "${HERE}/.." && shellcheck -x 04-gitops/*.sh 04-gitops/lib/*.sh) || fail=1
else warn "shellcheck not installed; skipped"; fi

# --- 4. Server-side dry run (optional) ----------------------------------------------------------
if [[ "${SERVER}" == true ]]; then
  for f in "${OUT}"/*.yaml; do
    log "server dry run: $(basename "${f}")"
    oc apply --server-side --dry-run=server -f "${f}" >/dev/null 2>"${OUT}/err" \
      || warn "$(grep -c . "${OUT}/err") error(s) (missing CRDs are expected before the operators are installed):
$(cat "${OUT}/err")"
  done
fi

((fail == 0)) || die "validation failed"
log "validation passed"
