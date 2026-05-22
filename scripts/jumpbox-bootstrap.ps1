# jumpbox-bootstrap.ps1
# Runs ON THE JUMPBOX VM via `az vm run-command invoke`. Installs Python,
# downloads the repo zip, and runs scripts/setup_aisearch_index.py using the
# VM's system-assigned managed identity to auth to AI Search + Foundry.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $RepoUrl,
    [Parameter(Mandatory = $true)] [string] $RepoBranch,
    [Parameter(Mandatory = $true)] [string] $AiSearchEndpoint,
    [Parameter(Mandatory = $true)] [string] $AiFoundryEndpoint,
    [string] $AiSearchIndexName = 'documents-index',
    [string] $EmbeddingModel = 'text-embedding-3-large',
    [string] $EmbeddingDimensions = '3072'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step($msg) { Write-Host "==> $msg" }

# 1) Install Python silently if missing.
# Check known install locations first; the current process's PATH won't reflect
# an install done in a previous run-command session, so Get-Command can miss it.
$knownPythons = @(
    'C:\Python312\python.exe',
    'C:\Program Files\Python312\python.exe',
    "$env:LocalAppData\Programs\Python\Python312\python.exe"
)
$pythonExe = $knownPythons | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $pythonExe) {
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pyCmd) { $pythonExe = $pyCmd.Source }
}
if (-not $pythonExe) {
    Write-Step "Installing Python 3.12 (silent)..."
    $installer = "$env:TEMP\python-installer.exe"
    Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe' -OutFile $installer -UseBasicParsing

    $targetDir = 'C:\Python312'
    $logPath = "$env:TEMP\python-install.log"
    $installArgs = @(
        '/quiet',
        '/log', $logPath,
        'InstallAllUsers=1',
        'PrependPath=1',
        'Include_pip=1',
        'Include_launcher=0',
        "TargetDir=$targetDir"
    )
    $proc = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru
    Write-Step "Python installer exit code: $($proc.ExitCode)"
    if ($proc.ExitCode -ne 0) {
        if (Test-Path $logPath) {
            Write-Host '--- python-install.log (tail) ---'
            Get-Content $logPath -Tail 60 | ForEach-Object { Write-Host $_ }
        }
        throw "Python installer failed with exit code $($proc.ExitCode)"
    }

    $pythonExe = Join-Path $targetDir 'python.exe'
    if (-not (Test-Path $pythonExe)) {
        # Fallback: scan common locations in case TargetDir was ignored.
        $candidates = @(
            'C:\Program Files\Python312\python.exe',
            "$env:LocalAppData\Programs\Python\Python312\python.exe",
            'C:\Python312\python.exe'
        )
        $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) {
            $pythonExe = $found
        } else {
            if (Test-Path $logPath) {
                Write-Host '--- python-install.log (tail) ---'
                Get-Content $logPath -Tail 60 | ForEach-Object { Write-Host $_ }
            }
            throw "Python install reported success but python.exe not found in: $($candidates -join ', ')"
        }
    }
}
Write-Step "Python: $pythonExe"

# Force PYTHONHOME so Python doesn't try to derive sys.prefix from cwd
# (which causes "ModuleNotFoundError: No module named 'encodings'" when run
# from a directory that doesn't contain the Python stdlib).
$pythonHome = Split-Path -Parent $pythonExe
$env:PYTHONHOME = $pythonHome
$env:PYTHONPATH = ''
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'
Write-Step "PYTHONHOME=$pythonHome"

# 2) Download repo archive.
$workDir = "$env:TEMP\foundry-private-byo-vnet"
if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir }
New-Item -ItemType Directory -Path $workDir | Out-Null

$archiveUrl = "$($RepoUrl -replace '\.git$','')/archive/refs/heads/$RepoBranch.zip"
$zipPath = "$env:TEMP\repo.zip"
Write-Step "Downloading $archiveUrl"
Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing
Expand-Archive -Path $zipPath -DestinationPath $workDir -Force
$repoRoot = (Get-ChildItem $workDir -Directory | Select-Object -First 1).FullName
Write-Step "Repo extracted to $repoRoot"

# 3) Install python deps.
Push-Location $repoRoot
try {
    Write-Step "Installing python dependencies..."
    & $pythonExe -m pip install --quiet --upgrade pip
    & $pythonExe -m pip install --quiet -r scripts/requirements.txt

    # 4) Set env vars for the script (DefaultAzureCredential will use the VM MI).
    $env:AI_SEARCH_ENDPOINT      = $AiSearchEndpoint
    $env:AI_FOUNDRY_ENDPOINT     = $AiFoundryEndpoint
    $env:AI_SEARCH_INDEX_NAME    = $AiSearchIndexName
    $env:EMBEDDING_MODEL         = $EmbeddingModel
    $env:EMBEDDING_DIMENSIONS    = $EmbeddingDimensions

    Write-Step "Running setup_aisearch_index.py"
    & $pythonExe scripts/setup_aisearch_index.py
    if ($LASTEXITCODE -ne 0) { throw "setup_aisearch_index.py exited with $LASTEXITCODE" }
    Write-Step "Indexing complete."
}
finally {
    Pop-Location
}
