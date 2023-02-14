[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $URL
)

$url -match "github.com\/(.*?)\/(.*?)$"

$user = $Matches[1]
$repository = $Matches[2]

# Get latest release assets url from github api
$releaseURL = "https://api.github.com/repos/$user/$repository/releases/latest"
$releaseResponse = Invoke-WebRequest -UseBasicParsing $releaseURL | ConvertFrom-Json
$assetsURL = $releaseResponse.assets_url
$assetsResponse = Invoke-WebRequest -UseBasicParsing $assetsURL | ConvertFrom-Json

# Find .rmskin package from latest releases assets
$downloadUrl = ""
foreach ($asset in $assetsResponse) {
    if ($asset.name -match '(?i).*?\.rmskin') {
        $assetName = $asset.name
        $downloadUrl = $asset.browser_download_url
        break
    }
}
if (-not($downloadUrl)) { 
    Write-Host "No .rmskin package found" -ForegroundColor Red
    Exit
}

# Download and run the skin installer
$file = "$($PSScriptRoot)\skin.rmskin"
Invoke-WebRequest -Uri $downloadUrl -UseBasicParsing -OutFile $file
Start-Process -FilePath $file
