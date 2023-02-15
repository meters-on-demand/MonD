[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]
    $Command = "help",
    [Parameter(Position = 1)]
    [string]
    $Parameter
)

. .env.ps1

$githubAPI = "https://api.github.com/"
$rainmeterSkinsTopic = "$($githubAPI)search/repositories?q=topic:rainmeter-skin&per_page=50"
$packageListFile = "skins.json"
$skinFile = "skin.rmskin"

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
            Paginate
        }
        "install" {
            Install $Parameter
        }
        "paginate" {
            Paginate $Parameter
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

    $skins | ConvertTo-Json | Out-File -FilePath $packageListFile

}

function Install {
    param (
        [Parameter()]
        [string]
        $SkinName
    )

    $skin = Find-Skin $SkinName

    if (-not($skin)) { throw "No skins named $($SkinName) found" }

    Invoke-WebRequest -Uri $skin.latest_release.browser_download_url -UseBasicParsing -OutFile $skinFile
    Start-Process -FilePath $skinFile

}

function Paginate {
    param (
        [Parameter(Position = 0)]
        [int]
        $ItemsOnPage
    )
    if ($ItemsOnPage -eq 0) { $ItemsOnPage = 10 }

    $emptyPage = @()
    for ($i = 0; $i -lt $ItemsOnPage; $i++) {
        $emptyPage += @{
            name = "" 
            repo = "" 
        }
    }

    $skins = Package-List
    for ($i = 0; $i -lt $skins.Count / $ItemsOnPage; $i++) {
        $page = $emptyPage
        for ($j = 0; $j -lt $page.Count; $j++) {
            $item = $skins[($i * $ItemsOnPage) + $j]
            if ($item) {
                $page[$j % $ItemsOnPage] = $item
            }
        }
        $page | ConvertTo-Json | Out-File -FilePath "pages\$($i).json" -Force
    }
}

function Find-Skin {
    param (
        [Parameter()]
        [string]
        $SkinName
    )
    $skins = Package-List
    foreach ($skin in $skins) {
        if ($skin.full_name -like $SkinName) {
            return $skin
        }
    }
    return $false
}

function Package-List {
    return Get-Content $packageListFile | ConvertFrom-Json
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
