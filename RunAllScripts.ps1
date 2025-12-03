[CmdletBinding()]
param (
    [string]$Path, # Path where the script and subfolders are located
    [string]$SettingsFile = "param.json" # Use the unified automated settings file
)

$ErrorActionPreference = "Stop"

$host.UI.RawUI.WindowTitle = "Flow & Power Apps Migrator - AUTOMATED MODE"

# --- 1. Setup and Initialization ---

if (-not $Path) {
    # If path is not supplied as parameter, use the current script directory
    $Path = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
Set-Location $Path

Write-Host "--- Flow & Power Apps Migrator (Certificate Automated Mode via Thumbprint) ---" -ForegroundColor Green

# ❌ REMOVED: Artistic Header for simplicity in automation mode
# ❌ REMOVED: . .\MISC\PS-Forms.ps1 (No interactive forms needed)

Get-ChildItem -Recurse | Unblock-File
# Import PnP Module
Import-Module (Get-ChildItem -Recurse -Filter "*.psd1").FullName -DisableNameChecking

Set-PnPTraceLog -On -LogFile traceoutput.txt -Level Debug

# --- 2. Load Configuration (from param.json) ---

$SettingsPath = Join-Path -Path $Path -ChildPath $SettingsFile
Write-Host "Reading automated settings from $SettingsPath" -ForegroundColor Cyan

# Check if the settings file exists
if (-not (Test-Path $SettingsPath)) {
    Write-Error "Settings file not found at $SettingsPath. Ensure 'param.json' is present."
    throw "Configuration file missing."
}

$Config = Get-Content -Raw -Path $SettingsPath | ConvertFrom-Json

# Assign common authentication variables
$APP_ID = $Config.ApplicationId
$TENANT_ID = $Config.TenantId
# ✅ استخدام بصمة الشهادة (Thumbprint) وتجريدها من المسافات
$CERT_THUMBPRINT = $Config.CertificateThumbprint.Replace(" ", "").ToUpper()

# Assign site and list variables
$SOURCE_SITE_URL = $Config.SourceSiteUrl.TrimEnd('/')
$TARGET_SITE_URL = $Config.TargetSiteUrl.TrimEnd('/')     
$MIGRATE_LISTS = $true # Hardcoded to true as this is an automated process

# Prepare the final list names for migration (including Form Templates if specified)
$LISTS_TO_MIGRATE = @()
if ($Config.ListsToMigrate) {
    $LISTS_TO_MIGRATE += $Config.ListsToMigrate
}
if ($Config.IncludeFormTemplates -eq $true) {
    # This must be the internal name or title of the list/library
    $LISTS_TO_MIGRATE += "Form Templates"
}

# Check if required authentication details are present
if (-not $APP_ID -or -not $TENANT_ID -or -not $CERT_THUMBPRINT) {
    Write-Error "Certificate authentication details (ApplicationId, TenantId, or CertificateThumbprint) missing in param.json."
    throw "Authentication failure: Required Certificate data missing."
}


# --- 3. Phase 1: Export (Source Site) ---

Write-Host "`n--- STARTING EXPORT PHASE (Source: $SOURCE_SITE_URL) ---" -ForegroundColor Yellow

# Connect to Source Site using Certificate Thumbprint Authentication (100% Automated)
Write-Host "Connecting to Source Site using Thumbprint: $CERT_THUMBPRINT" -ForegroundColor Cyan
Connect-PnPOnline -Url $SOURCE_SITE_URL `
                     -ClientId $APP_ID `
                     -Thumbprint $CERT_THUMBPRINT ` # ✅ FIXED: Removed -Tenant to match common parameter set
                     -WarningAction Ignore 

Write-Host "Connected successfully to Source Site." -ForegroundColor Green 

# Generate initial mapping files (User/Group/Flow/App IDs)
. .\GenerateInitialMapping.ps1

if ($MIGRATE_LISTS) {
    Write-Host "Exporting lists configuration..." -ForegroundColor Cyan
    # Call the updated Move-Lists.ps1 script, passing the list names automatically
    . .\MISC\Move-Lists.ps1 -Path $Path -MigrationType Export -SourceSite $SOURCE_SITE_URL -ListsToMigrate $LISTS_TO_MIGRATE
}

# Disconnect from Source Site after export is complete
Disconnect-PnPOnline -Url $SOURCE_SITE_URL


# --- 4. Phase 2: Import (Target Site) ---

Write-Host "`n--- STARTING IMPORT PHASE (Target: $TARGET_SITE_URL) ---" -ForegroundColor Yellow

# Connect to Target Site using Certificate Thumbprint Authentication (100% Automated)
# A new connection is required because PnP keeps only one active connection context.
Write-Host "Connecting to Target Site using Thumbprint: $CERT_THUMBPRINT" -ForegroundColor Cyan

Connect-PnPOnline -Url $TARGET_SITE_URL `
                     -ClientId $APP_ID `
                     -Thumbprint $CERT_THUMBPRINT ` # ✅ FIXED: Removed -Tenant to match common parameter set
                     -WarningAction Ignore 

Write-Host "Connected successfully to Target Site." -ForegroundColor Green

if ($MIGRATE_LISTS) {    
    Write-Host "Applying PnP Template to $TARGET_SITE_URL" -ForegroundColor Cyan
    # Call the updated Move-Lists.ps1 script for import
    . .\MISC\Move-Lists.ps1 -Path $Path -MigrationType Import -TargetSite $TARGET_SITE_URL -ListsToMigrate $LISTS_TO_MIGRATE
}

# Complete resource mapping and package conversion (final steps)
. .\CompleteResourceMapping.ps1 -DoNotReconnect
. .\ConvertPackage.ps1

# Final Disconnect
Disconnect-PnPOnline -Url $TARGET_SITE_URL

Write-Host "`n--- MIGRATION PROCESS COMPLETE ---" -ForegroundColor Green
