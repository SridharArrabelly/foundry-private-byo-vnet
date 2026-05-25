#!/usr/bin/env bash
# postprovision hook: invoke the indexer ON THE JUMPBOX VM via
# `az vm run-command`, since Cloud Shell / local machines cannot reach the
# private endpoints.

set -euo pipefail

echo "=== postprovision: running indexer on jumpbox via az vm run-command ==="

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP must be set by azd}"
: "${JUMPBOX_VM_NAME:?JUMPBOX_VM_NAME must be set by azd}"
: "${AI_SEARCH_ENDPOINT:?AI_SEARCH_ENDPOINT must be set by azd}"
: "${AI_FOUNDRY_ENDPOINT:?AI_FOUNDRY_ENDPOINT must be set by azd}"

# Determine repo URL + branch (this hook runs from inside the user's clone).
REPO_URL="$(git config --get remote.origin.url)"
REPO_BRANCH="${REPO_BRANCH:-$(git symbolic-ref --quiet --short HEAD || echo master)}"
INDEX_NAME="${AI_SEARCH_INDEX_NAME:-documents-index}"
EMBED_MODEL="${EMBEDDING_MODEL:-text-embedding-3-large}"
EMBED_DIMS="${EMBEDDING_DIMENSIONS:-3072}"

echo "  Repo:     $REPO_URL @ $REPO_BRANCH"
echo "  VM:      $JUMPBOX_VM_NAME (rg: $AZURE_RESOURCE_GROUP)"
echo "  Search:  $AI_SEARCH_ENDPOINT"
echo "  Foundry: $AI_FOUNDRY_ENDPOINT"

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

# Parse stdout / stderr emitted by the run-command extension on the VM.
# az vm run-command exits 0 as long as the agent ran, even if the inner script failed,
# so we have to inspect the output ourselves.
STDOUT="$(echo "$RC_OUTPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next((v["message"] for v in d.get("value",[]) if "StdOut" in v.get("code","")), ""))')"
STDERR="$(echo "$RC_OUTPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next((v["message"] for v in d.get("value",[]) if "StdErr" in v.get("code","")), ""))')"

echo "--- jumpbox stdout ---"
echo "$STDOUT"
if [[ -n "${STDERR// /}" ]]; then
    echo "--- jumpbox stderr ---" >&2
    echo "$STDERR" >&2
fi

# pip and other tools emit warnings to stderr (e.g. "WARNING: The scripts pip.exe ... not on PATH"),
# so non-empty stderr alone does not indicate failure. Treat the run as successful only if
# jumpbox-bootstrap.ps1 printed its terminal success marker.
if ! echo "$STDOUT" | grep -q '==> Indexing complete\.'; then
    echo "Indexer failed on jumpbox: success marker '==> Indexing complete.' not found in stdout." >&2
    exit 1
fi

echo "==> Indexer completed successfully on jumpbox."
