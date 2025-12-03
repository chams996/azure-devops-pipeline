param (
    [string]$Path
)

$ErrorActionPreference = "Stop"

$host.UI.RawUI.WindowTitle = "Flow & Power Apps Migrator"

Set-Location $Path
. .\MISC\PS-Forms.ps1

Get-ChildItem -Recurse | Unblock-File
# Legacy PowerShell PnP Module is used because the new one has a critical bug
Import-Module (Get-ChildItem -Recurse -Filter "*.psd1").FullName -DisableNameChecking

$Migration = @{
    TARGET_SITE_URL = "https://contoso.sharepoint.com/sites/Site_b"
}

$Migration = Get-FormItemProperties -item $Migration -dialogTitle "Enter target site" -propertiesOrder @("TARGET_SITE_URL") 
$TARGET_SITE_URL = $Migration.TARGET_SITE_URL

if($USE_APP_ONLY_AUTHENTICATION){
    Connect-PnPOnline -Url $TARGET_SITE_URL -ClientId $TARGET_SITE_APP_ID -ClientSecret $TARGET_SITE_APP_SECRET -WarningAction Ignore
}else{
    Connect-PnPOnline -Url $TARGET_SITE_URL -UseWebLogin -WarningAction Ignore
}

$xmlFiles = Get-ChildItem *.xml
if ($xmlFiles.Count -ne 0) {
    Write-Host Convert-Packages 1: $TARGET_SITE_URL Import of XML -ForegroundColor Yellow
    . .\MISC\Move-Lists.ps1 -Path $Path -MigrationType Import -TargetSite $TARGET_SITE_URL
}
. .\CompleteResourceMapping.ps1 -DoNotReconnect
. .\ConvertPackage.ps1
