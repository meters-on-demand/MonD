[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]
    $Command = "help"
)

. .env.ps1

$githubAPI = "https://api.github.com/"
$rainmeterSkinsTopic = "$($githubAPI)search/repositories?q=topic:rainmeter-skin&per_page=50"

function Main {
    param (
        [Parameter(Position = 0)]
        [string]
        $Command = "help"
    )
    switch ($Command) {
        "help" { 
            List-Commands
        }
        "update" {
            if (-not($TOKEN)) { throw "`$TOKEN must be set to use update" }
            Update
        }
        Default { }
    }
}

function Update {

    $allSkins = @()
    Get-RainmeterRepositories | ForEach-Object {
        $skin = @{
            id            = $_.id
            name          = $_.name
            full_name     = $_.full_name
            has_downloads = $_.has_downloads
            owner         = @{
                name       = $_.owner.login
                avatar_url = $_.owner.avatar_url
            }
        }
        $allSkins += $skin
    }

    $skins = @()
    $allSkins | ForEach-Object {
        $hasRMskin = Latest-RMskin $_
        if ($hasRMskin) {
            $_.latest_release = $hasRMskin
            $skins += $_
        }
    }

    $skins | ConvertTo-Json | Out-File -FilePath "skins.json"

}

function Get-RainmeterRepositories { 
    param (
        [Parameter(Position = 0)]
        [string]
        $Uri = $rainmeterSkinsTopic,
        [Parameter(Position = 1)]
        [array]
        $Items = @()
    )

    $response = Get-Request $Uri
    $data = $response | ConvertFrom-Json

    $Items = $Items + $data.items

    if ([string]$($response.Headers['Link']) -match '<(.*?)>;\s*?rel="next"') {
        if ($Matches[1]) {
            Get-RainmeterRepositories $Matches[1] $Items
        }
    }
    else {
        return $Items
    }

}

function Latest-RMskin {
    param (
        [Parameter(Position = 0)]
        [hashtable]
        $Skin
    )
    if (-not($Skin.has_downloads)) { return $false }

    try {
        $releaseResponse = Get-Request "$($githubAPI)repos/$($Skin.full_name)/releases/latest" | ConvertFrom-Json
    }
    catch {
        return $false
    }

    foreach ($asset in $releaseResponse.assets) {
        if ($asset.name -match '(?i).*?\.rmskin') {
            $assetHashtable = @{
                browser_download_url = $asset.browser_download_url
                tag_name             = $releaseResponse.tag_name
                name                 = $releaseResponse.name
                body                 = $releaseResponse.body
            }
            return $assetHashtable
        }
    }

    return $false
}

function Get-Request {
    param(
        [Parameter(Position = 0)]
        [string]
        $Uri
    )

    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing `
        -Authentication Bearer `
        -Token $TOKEN 

    Write-Host "-Uri $($Uri)"
    Write-Host "X-RateLimit-Remaining: $($response.Headers['X-RateLimit-Remaining'])"

    return $response
}

Main -Command $Command
