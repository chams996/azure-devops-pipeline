param(
    [Parameter(Mandatory = $true)][string]$SolutionRoot,
    [Parameter(Mandatory = $true)][string]$SitePairsFile,
    [Parameter(Mandatory = $true)][string]$TableNamesFile
)

Write-Host " Starting DataSources update..."
Write-Host " Solution root: $SolutionRoot"

# --- Load mappings ---
if (-not (Test-Path $SitePairsFile)) {
    Write-Error " SitePairs file not found: $SitePairsFile"
    exit 1
}
if (-not (Test-Path $TableNamesFile)) {
    Write-Error " TableNames file not found: $TableNamesFile"
    exit 1
}

$sitePairs  = Get-Content $SitePairsFile  | ConvertFrom-Json
$tableNames = Get-Content $TableNamesFile | ConvertFrom-Json

# --- Find all files (skip Content_Types right away) ---
$files = Get-ChildItem -Path $SolutionRoot -File -Recurse |
    Where-Object { $_.Name -ne "[Content_Types].xml" }

foreach ($file in $files) {
    try {
        $originalText = Get-Content $file.FullName -Raw -ErrorAction Stop
        $text = $originalText

        # 1️⃣ Replace site URLs
        foreach ($pair in $sitePairs) {
            if ($pair.Source -and $pair.Destination) {
                $text = $text -replace [Regex]::Escape($pair.Source), $pair.Destination
            }
        }

        # 2️⃣ Replace list IDs (contextual: based on tableNames.json)
        foreach ($listName in $tableNames.PSObject.Properties.Name) {
            $newGuid = $tableNames.$listName
            $pattern = "(?<=${listName}.*?)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
            $text = [regex]::Replace($text, $pattern, $newGuid)
        }

        # --- Write changes only if different ---
        if ($text -ne $originalText) {
            $text | Out-File $file.FullName -Encoding utf8
            Write-Host " Updated: $($file.FullName)"
        }
    }
    catch {
        Write-Warning " Skipped (cannot read as text): $($file.FullName)"
    }
}

# --- Final check for leftover GUIDs ---
Write-Host "`n🔍 Vérification finale des GUID restants..."

$pattern = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
$remainingGuids = @()

foreach ($file in $files) {
    try {
        #  Skip Content_Types explicitly (extra safety)
        if ($file.Name -eq "[Content_Types].xml") { continue }

        $content = Get-Content $file.FullName -Raw
        $matches = [regex]::matches($content, $pattern) | ForEach-Object { $_.Value } | Sort-Object -Unique
        foreach ($guid in $matches) {
            $listName = ($content | Select-String -Pattern '"Title"\s*:\s*"([^"]+)"').Matches.Groups[1].Value
            if (-not $listName) { $listName = "❓ Nom de liste introuvable" }

            $remainingGuids += [PSCustomObject]@{
                File     = $file.FullName
                GUID     = $guid
                ListName = $listName
            }
        }
    }
    catch { }
}

if ($remainingGuids.Count -gt 0) {
    Write-Host " Des GUID SharePoint non remplacés ont été détectés :"
    foreach ($item in $remainingGuids) {
        Write-Host "   → $($item.File)"
        Write-Host "      GUID: $($item.GUID)"
        Write-Host "      ListName détecté: $($item.ListName)"
    }
    Write-Error " Corrige les GUID manquants dans tablenames.json avant l’import."
    exit 1
}
else {
    Write-Host " Aucun GUID résiduel trouvé, prêt pour l’import."
}

Write-Host "`n DataSources update completed!"
