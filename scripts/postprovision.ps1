#!/usr/bin/env pwsh
# postprovision hook: invoke the indexer ON THE JUMPBOX VM via
# `az vm run-command`, since Cloud Shell / local machines cannot reach the
# private endpoints.

$ErrorActionPreference = 'Stop'

Write-Host "=== postprovision: running indexer on jumpbox via az vm run-command ===" -ForegroundColor Cyan

foreach ($v in 'AZURE_RESOURCE_GROUP','JUMPBOX_VM_NAME','AI_SEARCH_ENDPOINT','AI_FOUNDRY_ENDPOINT') {
    if (-not (Get-Item env:$v -ErrorAction SilentlyContinue)) { throw "$v must be set by azd" }
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

# pip and other tools emit warnings to stderr (e.g. "WARNING: The scripts pip.exe ... not on PATH"),
# so non-empty stderr alone does not indicate failure. Treat the run as successful only if
# jumpbox-bootstrap.ps1 printed its terminal success marker.
if ($stdout -notmatch '==> Indexing complete\.') {
    throw "Indexer failed on jumpbox: success marker '==> Indexing complete.' not found in stdout."
}

Write-Host "==> Indexer completed successfully on jumpbox." -ForegroundColor Green
