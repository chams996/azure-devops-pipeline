param(
    [Parameter(Mandatory = $true)][string]$TenantId,
    [Parameter(Mandatory = $true)][string]$ClientId,
    [Parameter(Mandatory = $true)][string]$CertificatePath,
    [Parameter(Mandatory = $true)][string]$CertificatePassword,
    [Parameter(Mandatory = $true)][string]$SitePairsFile,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [Parameter(Mandatory = $true)][string[]]$Lists # ex: @("VacationRequests","Employees","Projects")
)

# Ensure PnP module
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Install-Module -Name PnP.PowerShell -Force -Scope CurrentUser
}
Import-Module PnP.PowerShell -Force

# Load site pairs
$sitePairs = Get-Content $SitePairsFile | ConvertFrom-Json
$result = @{ }

foreach ($pair in $sitePairs) {
    Write-Host "`n--- Connecting to $($pair.Destination) ---"

    $conn = Connect-PnPOnline -Url $pair.Destination `
        -ClientId $ClientId `
        -Tenant $TenantId `
        -CertificatePath $CertificatePath `
        -CertificatePassword (ConvertTo-SecureString $CertificatePassword -AsPlainText -Force) `
        -ReturnConnection

    $web = Get-PnPWeb -Connection $conn
    $webId = $web.Id.ToString()

    $siteResult = @{ }

    foreach ($listName in $Lists) {
        try {
            $list = Get-PnPList -Identity $listName -Connection $conn -ErrorAction Stop
            $listId = $list.Id.ToString()
            $listUrl = "$($pair.Destination)/Lists/$listName/AllItems.aspx"

            $siteResult[$listName] = @{
                siteId  = $webId
                listId  = $listId
                listUrl = $listUrl
            }

            Write-Host "Found: $listName ($listId)"
        }
        catch {
            Write-Warning " List not found: $listName in $($pair.Destination)"
        }
    }

    $result[$pair.Destination] = $siteResult
}

# Save mapping JSON
$result | ConvertTo-Json -Depth 10 | Out-File $OutputFile -Encoding utf8
Write-Host "`n🎉 Mapping saved to $OutputFile"
