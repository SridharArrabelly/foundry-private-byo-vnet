#!/usr/bin/env bash
# bootstrap-jumpbox.sh
#
# Run this script ON YOUR DEV BOX **AFTER** `azd up` if you want the sample
# AI Search index populated for testing. It is **NOT** invoked by `azd up`
# — the deployment intentionally provisions infrastructure only.
#
# What it does:
#   1. Reads endpoints + VM name from `azd env get-values` (your active azd env)
#   2. Calls `az vm run-command invoke` to push scripts/jumpbox-bootstrap.ps1
#      to the jumpbox over the Azure backplane (no Bastion / RDP needed).
#   3. The jumpbox script then: installs Python, downloads the repo zip,
#      runs scripts/setup_aisearch_index.py (uses the VM MI to auth against
#      AI Search + Foundry over private endpoints).
#
# Usage:
#   ./scripts/bootstrap-jumpbox.sh
#
# Optional env overrides (otherwise sourced from azd):
#   AZURE_RESOURCE_GROUP, JUMPBOX_VM_NAME, AI_SEARCH_ENDPOINT, AI_FOUNDRY_ENDPOINT,
#   AI_SEARCH_INDEX_NAME (default: documents-index),
#   EMBEDDING_MODEL      (default: text-embedding-3-large),
#   EMBEDDING_DIMENSIONS (default: 3072),
#   REPO_BRANCH          (default: current branch, or master).

set -euo pipefail

echo "=== bootstrap-jumpbox: indexing sample data on the jumpbox ==="

# Auto-load values from the active azd environment if not already set.
needed=(AZURE_RESOURCE_GROUP JUMPBOX_VM_NAME AI_SEARCH_ENDPOINT AI_FOUNDRY_ENDPOINT)
missing=0
for v in "${needed[@]}"; do [[ -z "${!v:-}" ]] && missing=1; done
if [[ $missing -eq 1 ]] && command -v azd &>/dev/null; then
    echo "Loading missing env vars from 'azd env get-values'..."
    while IFS='=' read -r key value; do
        for n in "${needed[@]}"; do
            if [[ "$key" == "$n" && -z "${!key:-}" ]]; then
                val="${value%\"}"; val="${val#\"}"
                export "$key=$val"
            fi
        done
    done < <(azd env get-values 2>/dev/null)
fi

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP not set and could not be loaded from azd}"
: "${JUMPBOX_VM_NAME:?JUMPBOX_VM_NAME not set and could not be loaded from azd}"
: "${AI_SEARCH_ENDPOINT:?AI_SEARCH_ENDPOINT not set and could not be loaded from azd}"
: "${AI_FOUNDRY_ENDPOINT:?AI_FOUNDRY_ENDPOINT not set and could not be loaded from azd}"

REPO_URL="$(git config --get remote.origin.url)"
REPO_BRANCH="${REPO_BRANCH:-$(git symbolic-ref --quiet --short HEAD || echo master)}"
INDEX_NAME="${AI_SEARCH_INDEX_NAME:-documents-index}"
EMBED_MODEL="${EMBEDDING_MODEL:-text-embedding-3-large}"
EMBED_DIMS="${EMBEDDING_DIMENSIONS:-3072}"

echo "  Repo:     $REPO_URL @ $REPO_BRANCH"
echo "  VM:       $JUMPBOX_VM_NAME (rg: $AZURE_RESOURCE_GROUP)"
echo "  Search:   $AI_SEARCH_ENDPOINT"
echo "  Foundry:  $AI_FOUNDRY_ENDPOINT"
echo "  Index:    $INDEX_NAME"

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jumpbox-bootstrap.ps1"

echo "==> Invoking jumpbox bootstrap (this can take 5-10 min on first run)..."
RC_OUTPUT="$(az vm run-command invoke \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$JUMPBOX_VM_NAME" \
  --command-id RunPowerShellScript \
  --scripts "@${SCRIPT_PATH}" \
  --parameters \
      "RepoUrl=$REPO_URL" \
      "RepoBranch=$REPO_BRANCH" \
      "AiSearchEndpoint=$AI_SEARCH_ENDPOINT" \
      "AiFoundryEndpoint=$AI_FOUNDRY_ENDPOINT" \
      "AiSearchIndexName=$INDEX_NAME" \
      "EmbeddingModel=$EMBED_MODEL" \
      "EmbeddingDimensions=$EMBED_DIMS" \
  --output json)"

STDOUT="$(echo "$RC_OUTPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next((v["message"] for v in d.get("value",[]) if "StdOut" in v.get("code","")), ""))')"
STDERR="$(echo "$RC_OUTPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next((v["message"] for v in d.get("value",[]) if "StdErr" in v.get("code","")), ""))')"

echo "--- jumpbox stdout ---"
echo "$STDOUT"
if [[ -n "${STDERR// /}" ]]; then
    echo "--- jumpbox stderr ---" >&2
    echo "$STDERR" >&2
fi

if ! echo "$STDOUT" | grep -q '==> Indexing complete\.'; then
    echo "Indexer failed on jumpbox: success marker '==> Indexing complete.' not found in stdout." >&2
    exit 1
fi

echo "==> Indexer completed successfully on jumpbox."