param(
    [Parameter(Mandatory=$true)][string]$SolutionsJson,
    [Parameter(Mandatory=$true)][string]$TenantId,
    [Parameter(Mandatory=$true)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$CertificatePath,
    [Parameter(Mandatory=$true)][string]$CertificatePassword,
    [Parameter(Mandatory=$true)][string]$PacPath,
    [string]$SolutionsFolder
)

# --- 1️ Default solutions folder ---
if (-not $SolutionsFolder) {
    if ($env:BUILD_ARTIFACTSTAGINGDIRECTORY) {
        $SolutionsFolder = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "Final-Solutions"
    } else {
        $SolutionsFolder = Join-Path $PSScriptRoot "Final-Solutions"
    }
}
Write-Host " Solutions folder: $SolutionsFolder"

# --- 2️ Read solutions JSON ---
if (-not (Test-Path $SolutionsJson)) {
    Write-Error " Solutions JSON not found: $SolutionsJson"
    exit 1
}
$solutions = Get-Content $SolutionsJson | ConvertFrom-Json
if (-not $solutions -or $solutions.Count -eq 0) {
    Write-Error " No solutions defined in $SolutionsJson"
    exit 1
}

# --- 3️ Loop each solution ---
foreach ($sol in $solutions) {
    $solutionName = $sol.Name
    $envUrl = $sol.TargetEnvironment.TrimEnd('/')
    $safeName = $solutionName -replace '[^a-zA-Z0-9_-]', '_'
    $zipPath = Join-Path $SolutionsFolder "$safeName`_Final.zip"

    if (-not (Test-Path $zipPath)) {
        Write-Error " Final solution package not found: $zipPath"
        exit 1
    }

    Write-Host "`n Importing FINAL solution '$solutionName' into $envUrl"

    # --- 3a. PAC authentication ---
    Write-Host " Authenticating to target environment..."
    $authArgs = @(
        "auth", "create",
        "--name", "ImportConnection",
        "--environment", $envUrl,
        "--applicationId", $ClientId,
        "--certificateDiskPath", $CertificatePath,
        "--certificatePassword", $CertificatePassword,
        "--tenant", $TenantId
    )
    & $PacPath @authArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error " PAC auth failed for environment $envUrl"
        exit 1
    }
    Write-Host "✅ Authenticated successfully."

    # --- 3b. Import solution ---
    $importArgs = @(
        "solution", "import",
        "--path", $zipPath,
        "--environment", $envUrl,
        "--async",
        "--max-async-wait-time", "60",
        "--publish-changes",
        "--force-overwrite"
    )
    & $PacPath @importArgs

    if ($LASTEXITCODE -eq 0) {
        Write-Host " Imported FINAL solution: $solutionName"
    } else {
        Write-Error " Failed to import solution $solutionName"
        exit 1
    }
}

Write-Host "`n All FINAL solution imports completed successfully!"
