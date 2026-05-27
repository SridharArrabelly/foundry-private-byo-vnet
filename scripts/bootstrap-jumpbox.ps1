#!/usr/bin/env pwsh
# bootstrap-jumpbox.ps1
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
#   ./scripts/bootstrap-jumpbox.ps1
#
# Optional env overrides (otherwise sourced from azd):
#   $env:AZURE_RESOURCE_GROUP, $env:JUMPBOX_VM_NAME,
#   $env:AI_SEARCH_ENDPOINT,   $env:AI_FOUNDRY_ENDPOINT,
#   $env:AI_SEARCH_INDEX_NAME (default: documents-index),
#   $env:EMBEDDING_MODEL      (default: text-embedding-3-large),
#   $env:EMBEDDING_DIMENSIONS (default: 3072),
#   $env:REPO_BRANCH          (default: current branch, or master)

$ErrorActionPreference = 'Stop'

Write-Host "=== bootstrap-jumpbox: indexing sample data on the jumpbox ===" -ForegroundColor Cyan

# Auto-load values from the active azd environment if not already set.
$needed = 'AZURE_RESOURCE_GROUP','JUMPBOX_VM_NAME','AI_SEARCH_ENDPOINT','AI_FOUNDRY_ENDPOINT'
$missing = $needed | Where-Object { -not (Get-Item "env:$_" -ErrorAction SilentlyContinue) }
if ($missing -and (Get-Command azd -ErrorAction SilentlyContinue)) {
    Write-Host "Loading missing env vars from 'azd env get-values'..." -ForegroundColor DarkGray
    $vals = & azd env get-values 2>$null
    foreach ($line in $vals) {
        if ($line -match '^([A-Z0-9_]+)="(.*)"$') {
            $k = $matches[1]
            $v = $matches[2]
            if (($k -in $needed) -and (-not (Get-Item "env:$k" -ErrorAction SilentlyContinue))) {
                Set-Item "env:$k" $v
            }
        }
    }
}

foreach ($v in $needed) {
    if (-not (Get-Item "env:$v" -ErrorAction SilentlyContinue)) {
        throw "$v not set and could not be loaded from azd. Run 'azd env get-values' to verify the env exists."
    }
}

$repoUrl    = (git config --get remote.origin.url).Trim()
$repoBranch = if ($env:REPO_BRANCH) { $env:REPO_BRANCH } else { (git symbolic-ref --quiet --short HEAD) }
if (-not $repoBranch) { $repoBranch = 'master' }
$indexName  = if ($env:AI_SEARCH_INDEX_NAME) { $env:AI_SEARCH_INDEX_NAME } else { 'documents-index' }
$embedModel = if ($env:EMBEDDING_MODEL) { $env:EMBEDDING_MODEL } else { 'text-embedding-3-large' }
$embedDims  = if ($env:EMBEDDING_DIMENSIONS) { $env:EMBEDDING_DIMENSIONS } else { '3072' }

Write-Host "  Repo:     $repoUrl @ $repoBranch"
Write-Host "  VM:       $($env:JUMPBOX_VM_NAME) (rg: $($env:AZURE_RESOURCE_GROUP))"
Write-Host "  Search:   $($env:AI_SEARCH_ENDPOINT)"
Write-Host "  Foundry:  $($env:AI_FOUNDRY_ENDPOINT)"
Write-Host "  Index:    $indexName"

$scriptPath = Join-Path $PSScriptRoot 'jumpbox-bootstrap.ps1'

Write-Host "==> Invoking jumpbox bootstrap (this can take 5-10 min on first run)..." -ForegroundColor Yellow
$rcJson = az vm run-command invoke `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --name $env:JUMPBOX_VM_NAME `
    --command-id RunPowerShellScript `
    --scripts "@$scriptPath" `
    --parameters `
        "RepoUrl=$repoUrl" `
        "RepoBranch=$repoBranch" `
        "AiSearchEndpoint=$($env:AI_SEARCH_ENDPOINT)" `
        "AiFoundryEndpoint=$($env:AI_FOUNDRY_ENDPOINT)" `
        "AiSearchIndexName=$indexName" `
        "EmbeddingModel=$embedModel" `
        "EmbeddingDimensions=$embedDims" `
    --output json | Out-String

$rc = $rcJson | ConvertFrom-Json
$stdout = ($rc.value | Where-Object { $_.code -like '*StdOut*' } | Select-Object -First 1).message
$stderr = ($rc.value | Where-Object { $_.code -like '*StdErr*' } | Select-Object -First 1).message

Write-Host '--- jumpbox stdout ---'
Write-Host $stdout
if ($stderr -and $stderr.Trim()) {
    Write-Host '--- jumpbox stderr ---' -ForegroundColor Yellow
    Write-Host $stderr -ForegroundColor Yellow
}

if ($stdout -notmatch '==> Indexing complete\.') {
    throw "Indexer failed on jumpbox: success marker '==> Indexing complete.' not found in stdout."
}

Write-Host "==> Indexer completed successfully on jumpbox." -ForegroundColor Green