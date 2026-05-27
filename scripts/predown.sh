#!/usr/bin/env bash
# predown hook: delete the project's capabilityHost BEFORE azd tears down
# the Foundry account. See predown.ps1 for the full rationale.
set -euo pipefail

echo "=== predown: releasing Foundry capabilityHost before teardown ==="

rg="${AZURE_RESOURCE_GROUP:-}"
account="${AI_FOUNDRY_NAME:-}"
project="${AI_FOUNDRY_PROJECT_NAME:-}"
sub="${AZURE_SUBSCRIPTION_ID:-}"

if [[ -z "$rg" || -z "$account" || -z "$project" || -z "$sub" ]]; then
  echo "  AZURE_RESOURCE_GROUP / AI_FOUNDRY_NAME / AI_FOUNDRY_PROJECT_NAME / AZURE_SUBSCRIPTION_ID not set — skipping."
  exit 0
fi

if ! az cognitiveservices account show -g "$rg" -n "$account" --query name -o tsv >/dev/null 2>&1; then
  echo "  Foundry account '$account' not found in '$rg' — skipping."
  exit 0
fi

api='2025-10-01-preview'
base="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account/projects/$project/capabilityHosts"

names=$(az rest --method get --url "https://management.azure.com${base}?api-version=${api}" --query "value[].name" -o tsv 2>/dev/null || true)
if [[ -z "$names" ]]; then
  echo "  No capabilityHosts on project '$project' — nothing to release."
  exit 0
fi

while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  echo "  Deleting capabilityHost '$name' (this triggers managed-env cleanup; ~1-3 min)..."
  az rest --method delete --url "https://management.azure.com${base}/${name}?api-version=${api}" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    sleep 10
    still=$(az rest --method get --url "https://management.azure.com${base}/${name}?api-version=${api}" --query name -o tsv 2>/dev/null || true)
    if [[ -z "$still" ]]; then echo "    capabilityHost '$name' deleted."; break; fi
  done
done <<< "$names"

echo "=== predown: done. azd down will now proceed. ==="
