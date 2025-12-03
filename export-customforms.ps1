param(
    [Parameter(Mandatory=$true)][string]$SolutionsJson,
    [Parameter(Mandatory=$true)][string]$TenantId,
    [Parameter(Mandatory=$true)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$CertificatePath,
    [Parameter(Mandatory=$true)][string]$CertificatePassword,
    [string]$OutputFolder,
    [Parameter(Mandatory=$true)][string]$PacPath
)

# --- 1️ Set default output folder ---
if (-not $OutputFolder) {
    if ($env:BUILD_ARTIFACTSTAGINGDIRECTORY) {
        $OutputFolder = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "PowerPlatformSolutions"
    } else {
        $OutputFolder = Join-Path $PSScriptRoot "PowerPlatformSolutions"
    }
}

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}
Write-Host " Output folder: $OutputFolder"

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

# --- 3️⃣ Loop through each solution ---
foreach ($sol in $solutions) {
    $solutionName = $sol.Name
    $envUrl = $sol.Environment.TrimEnd('/')
    $safeName = $solutionName -replace '[^a-zA-Z0-9_-]', '_'
    $exportPath = Join-Path $OutputFolder "$safeName.zip"

    Write-Host "`n Exporting solution '$solutionName' from $envUrl"

    # --- 3a. PAC authentication ---
    Write-Host " Authenticating to environment..."
    $authArgs = @(
        "auth", "create",
        "--name", "ExportConnection",
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
    Write-Host " Authenticated successfully."

    # --- 3b. Export the solution ---
    Write-Host " Exporting solution '$solutionName'..."
    $exportArgs = @(
        "solution", "export",
        "--name", $solutionName,
        "--path", $exportPath,
        "--environment", $envUrl,
        "--overwrite"
    )
    & $PacPath @exportArgs

    # --- 3c. Verify export ---
    if (Test-Path $exportPath) {
        Write-Host " Export completed: $exportPath"
    } else {
        Write-Error " PAC solution export failed for solution $solutionName"
        exit 1
    }
}

# --- 4️ List exported files ---
Write-Host "`n Exported solution files in ${OutputFolder}:"
Get-ChildItem $OutputFolder -Recurse -File | ForEach-Object { Write-Host $_.FullName }

Write-Host "`n All solution exports completed successfully!"

