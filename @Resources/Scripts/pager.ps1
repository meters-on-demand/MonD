[CmdletBinding()]
param (
    [Parameter()]
    [int]
    $ItemsOnPage = 5
)

$emptyItem = @{
    name = "" 
    repo = "" 
}

$emptyPage = @()
for ($i = 0; $i -lt $ItemsOnPage; $i++) {
    $emptyPage += $emptyItem
}

Set-Location $PSScriptRoot
Set-Location "..\.."

$full = Get-Content -Path "meters.json" | ConvertFrom-Json
$skins = $full.skins

for ($i = 0; $i -lt $skins.Count / $ItemsOnPage; $i++) {
    $page = $emptyPage
    for ($j = 0; $j -lt $page.Count; $j++) {
        $item = $skins[($i * $ItemsOnPage) + $j]
        if ($item) {
            $page[$j % 5] = $item
        }
    }
    $page | ConvertTo-Json | Out-File -FilePath "pages\$($i).json" -Force
}

Set-Location $PSScriptRoot
