#!/usr/bin/env pwsh
# predown hook: delete the project's capabilityHost BEFORE azd tears down
# the Foundry account.
#
# Why: the capabilityHost (kind=Agents) provisions a Microsoft-managed
# Container Apps environment in an internal subscription. That environment
# attaches a `legionservicelink` serviceAssociationLink to the agent subnet.
# If the Foundry account is deleted while the capabilityHost still exists,
# the managed env becomes orphaned in the internal sub — only Microsoft can
# clean it up — and the SAL blocks vnet/NSG/NAT/PIP deletion forever.
#
# Deleting the capabilityHost first triggers the managed env teardown,
# which releases the SAL, which lets `azd down` (and any later RG delete)
# complete cleanly.

$ErrorActionPreference = 'Stop'

Write-Host "=== predown: releasing Foundry capabilityHost before teardown ===" -ForegroundColor Cyan

$rg      = $env:AZURE_RESOURCE_GROUP
$account = $env:AI_FOUNDRY_NAME
$project = $env:AI_FOUNDRY_PROJECT_NAME

if (-not $rg -or -not $account -or -not $project) {
    Write-Host "  AZURE_RESOURCE_GROUP / AI_FOUNDRY_NAME / AI_FOUNDRY_PROJECT_NAME not set — nothing to release. Skipping." -ForegroundColor Yellow
    exit 0
}

$exists = az cognitiveservices account show -g $rg -n $account --query "name" -o tsv 2>$null
if (-not $exists) {
    Write-Host "  Foundry account '$account' not found in '$rg' — skipping." -ForegroundColor Yellow
    exit 0
}

$apiVersion = '2025-10-01-preview'
$base       = "/subscriptions/$($env:AZURE_SUBSCRIPTION_ID)/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account/projects/$project/capabilityHosts"

$caphosts = az rest --method get --url "https://management.azure.com$base`?api-version=$apiVersion" --query "value[].name" -o tsv 2>$null
if (-not $caphosts) {
    Write-Host "  No capabilityHosts on project '$project' — nothing to release." -ForegroundColor Green
    exit 0
}

foreach ($name in ($caphosts -split "`n" | Where-Object { $_ })) {
    Write-Host "  Deleting capabilityHost '$name' (this triggers managed-env cleanup; ~1-3 min)..." -ForegroundColor Yellow
    az rest --method delete --url "https://management.azure.com$base/$name`?api-version=$apiVersion" 2>&1 | Out-Null
    # Poll until the resource is gone (delete is async).
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 10
        $still = az rest --method get --url "https://management.azure.com$base/$name`?api-version=$apiVersion" --query "name" -o tsv 2>$null
        if (-not $still) { Write-Host "    capabilityHost '$name' deleted." -ForegroundColor Green; break }
    }
}

Write-Host "=== predown: done. azd down will now proceed. ===" -ForegroundColor Cyan
