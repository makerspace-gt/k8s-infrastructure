#!/usr/bin/env bash
# Validate every Kubernetes manifest in this repo the way CI does.
#
# Single source of truth for both .github/workflows/validate.yaml and the local
# pre-commit hook, so local checks and CI can never drift. Three stages:
#   1. kustomize build  — every kustomization.yaml dir renders without error
#   2. kubeconform      — schema-validate the rendered output (CRD schemas pulled
#                         from the datreeio catalog; unknown CRDs are skipped)
#   3. kyverno apply    — check the repo's own manifests against policies/ so we
#                         see Enforce-mode violations while they're still Audit
#
# Requires: kustomize, kubeconform, kyverno on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

kubeconform() {
  command kubeconform \
    -strict \
    -summary \
    -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    "$@"
}

# Directories that are a kustomize build unit (have a kustomization.yaml).
# Skip Talos and the Flux-managed gotk components.
mapfile -t kustomize_dirs < <(
  find . -name kustomization.yaml \
    -not -path './talos/*' \
    -not -path './cluster/flux-system/*' \
    -printf '%h\n' | sort -u
)

fail=0

echo "== Stage 1+2: kustomize build + kubeconform =="
for dir in "${kustomize_dirs[@]}"; do
  echo ">> $dir"
  if ! kustomize build "$dir" | kubeconform; then
    echo "   FAILED: $dir"
    fail=1
  fi
done

echo
echo "== Stage 3: kyverno policy pre-flight (informational) =="
# Render every workload manifest into one stream and test it against the repo's
# Kyverno policies. Informational while policies are Audit in-cluster; flip the
# '|| true' below to make CI block once the PolicyReports are clean.
# NOTE: kyverno only treats a policy file as a policy if it ends in .yaml/.yml;
# a bare mktemp path loads 0 policies silently. Hence the explicit suffix.
rendered="$(mktemp --suffix=.yaml)"
policies="$(mktemp --suffix=.yaml)"
trap 'rm -f "$rendered" "$policies"' EXIT
while IFS= read -r dir; do
  { kustomize build "$dir"; printf '\n---\n'; } >> "$rendered" 2>/dev/null || true
done < <(find ./apps ./infrastructure ./monitoring -name kustomization.yaml -printf '%h\n' | sort -u)

# Render only the ClusterPolicies (kustomize build drops kustomization.yaml itself,
# which kyverno can't parse as a policy).
kustomize build ./policies > "$policies"

# validate.failureAction needs kyverno CLI >= 1.13; older CLIs reject it as an
# unknown field. Skip the pre-flight (with a clear hint) rather than erroring out
# on an old local binary — CI always installs the latest CLI.
kyverno_ver="$(kyverno version 2>/dev/null | awk '/Version:/{print $2}' | tr -d 'v')"
if [ -n "$kyverno_ver" ] && \
   [ "$(printf '1.13.0\n%s\n' "$kyverno_ver" | sort -V | head -1)" != "1.13.0" ]; then
  echo "SKIP: kyverno CLI $kyverno_ver is too old for validate.failureAction (need >= 1.13)."
  echo "      Upgrade the CLI to run the policy pre-flight locally; CI runs it regardless."
else
  kyverno apply "$policies" --resource "$rendered" || true
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "RESULT: schema validation FAILED (see above)"
  exit 1
fi
echo "RESULT: schema validation passed"
