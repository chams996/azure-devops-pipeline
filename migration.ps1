param(
    [Parameter(Mandatory=$true)][string]$TenantId,
    [Parameter(Mandatory=$true)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$CertificatePath,
    [Parameter(Mandatory=$true)][string]$CertificatePassword,  # NEW
    [Parameter(Mandatory=$true)][string]$SitePairsFile
)

# --- 0. Convert plain text password to SecureString ---
$CertPwdSecure = ConvertTo-SecureString $CertificatePassword -AsPlainText -Force

# Optional: test the certificate
try {
    $x = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath, $CertificatePassword)
    Write-Host " PFX loaded OK. Thumbprint: $($x.Thumbprint)" -ForegroundColor Green
} catch {
    Write-Error " Failed to load PFX: $($_.Exception.Message)"
    exit 1
}

# --- 1. Import PnP.PowerShell ---
try { Import-Module PnP.PowerShell -Force } 
catch { Write-Error " Cannot import PnP.PowerShell. Install in PS7."; exit 1 }

# --- 2. Verify JSON ---
if (-not (Test-Path $SitePairsFile)) {
    Write-Error " Site pairs file '$SitePairsFile' not found."
    exit 1
}
$sitePairs = Get-Content $SitePairsFile | ConvertFrom-Json

# --- 3. Loop through each migration pair ---
foreach ($pair in $sitePairs) {
    Write-Host " Migration Pair: $($pair.Name)" -ForegroundColor Cyan

    # Connect to Source
    Write-Host " Connecting to Source: $($pair.Source)"
    try {
        $src = Connect-PnPOnline -Url $pair.Source `
                                 -Tenant $TenantId `
                                 -ClientId $ClientId `
                                 -CertificatePath $CertificatePath `
                                 -CertificatePassword $CertPwdSecure `
                                 -ReturnConnection
        Write-Host " Connected to Source" -ForegroundColor Green
    } catch {
        Write-Error " Source connection error: $($_.Exception.Message)"; exit 1
    }

    # Connect to Destination
    Write-Host " Connecting to Destination: $($pair.Destination)"
    try {
        $dst = Connect-PnPOnline -Url $pair.Destination `
                                 -Tenant $TenantId `
                                 -ClientId $ClientId `
                                 -CertificatePath $CertificatePath `
                                 -CertificatePassword $CertPwdSecure `
                                 -ReturnConnection
        Write-Host " Connected to Destination" -ForegroundColor Green
    } catch {
        Write-Error " Destination connection error: $($_.Exception.Message)"; exit 1
    }

    # Export Site Template
    $templatePath = Join-Path $env:BUILD_SOURCESDIRECTORY "$($pair.Name)-template.pnp"
    Write-Host " Exporting site template to $templatePath"
    try {
        Get-PnPSiteTemplate -Connection $src `
                            -Out $templatePath `
                            -Handlers @("Lists","Fields","ContentTypes","Pages","ComposedLook") `
                            -IncludeAllPages `
                            -PersistBrandingFiles
        Write-Host " Template exported" -ForegroundColor Green
    } catch {
        Write-Error " Template export error: $($_.Exception.Message)"; exit 1
    }

    # Apply Template
    Write-Host " Applying template to destination..."
    try {
        Invoke-PnPSiteTemplate -Connection $dst -Path $templatePath
        Write-Host " Template applied" -ForegroundColor Green
    } catch {
        Write-Error " Template apply error: $($_.Exception.Message)"; exit 1
    }

    # Migrate list items
    Write-Host " Migrating list items..."
    $lists = Get-PnPList -Connection $src | Where-Object { -not $_.Hidden -and $_.BaseTemplate -eq 100 }
    foreach ($list in $lists) {
        Write-Host " Copying items from list: $($list.Title)"
        $items = Get-PnPListItem -Connection $src -List $list.Title -PageSize 500
        foreach ($item in $items) {
            try { Add-PnPListItem -Connection $dst -List $list.Title -Values $item.FieldValues }
            catch { Write-Error " Failed to copy item $($item.Id) in list $($list.Title): $($_.Exception.Message)" }
        }
    }
}

Write-Host " Migration script completed." -ForegroundColor Green

