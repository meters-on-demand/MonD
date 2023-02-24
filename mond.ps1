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

# URLs
$githubAPI = "https://api.github.com/"
$rainmeterSkinsTopic = "$($githubAPI)search/repositories?q=topic:rainmeter-skin&per_page=50"

# Files
$packageListFile = "skins.json"
$skinFile = "skin.rmskin"

# Directories
$includeFilesDirectory = "$($PSScriptRoot)\@Resources\Generated"

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
            if (-not($TOKEN)) { throw "`$TOKEN must be set in `".env.ps1`" to use update" }
            Update
            Export
        }
        "install" {
            Install $Parameter
        }
        "export" {
            Export
        }
        Default {
            Write-Host "$Command" -ForegroundColor Red -NoNewline
            Write-Host " is not a command! Use" -NoNewline 
            Write-Host " mond help " -ForegroundColor Blue -NoNewline
            Write-Host "to see available commands!"
        }
    }
}

function List-Commands {
    $commands = @(@{
            Name        = "help"
            Description = "show this help"
        }, @{
            Name        = "update"
            Description = "update the package list"
        }, @{
            Name        = "install"
            Description = "installs the specified package"
            Parameters  = @(@{
                    Name        = "package" 
                    Description = "the full name of the package to install"
                })
        },
        @{
            Name        = "export"
            Description = "exports skins to meters"
        }
    )

    Write-Host "List of MonD commands"

    foreach ($command in $commands) {
        Write-Host "$($command.name)" -ForegroundColor Blue
        Write-Host "$($command.Description)"
        if ($command.Parameters) {
            Write-Host "parameters:" -ForegroundColor Yellow
            foreach ($parameter in $command.Parameters) {
                Write-Host "$($parameter.name)" -ForegroundColor Blue
                Write-Host "$($parameter.Description)"
            }
        }
        Write-Host ""
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

function Export {
    $skins = Package-List
    $metersFile = "$includeFilesDirectory\Meters.inc"
    $variablesFile = "$includeFilesDirectory\SkinVariables.inc"

    # Empty metersFile
    "" | Out-File -FilePath $metersFile -Force -Encoding unicode

    # Empty variablesFile
    @"
[Variables]
Skins=$($skins.Count)
"@ | Out-File -FilePath $variablesFile -Force -Encoding unicode

    # Separate loops to not have two files open? idk
    for ($i = 0; $i -lt $skins.Count; $i++) {
        Meter -Skin $skins[$i] -Index $i | Out-File -FilePath $metersFile -Append -Encoding unicode
    }

    for ($i = 0; $i -lt $skins.Count; $i++) {
        Variables -Skin $skins[$i] -Index $i | Out-File -FilePath $variablesFile -Append -Encoding unicode
    }
}

function Meter {
    param (
        [Parameter(Position = 0)]
        [System.Object]
        $Skin,
        [Parameter(Position = 1)]
        [int]
        $Index
    )

    return @"
[SkinName$i]
Meter=String
Text=$($Skin.name)
MeterStyle=Skins | Names
Group=Skins | Names
Hidden=(($index < ([#Index] + [#ItemsShown])) && ($index >= [#Index]) ? 0 : 1)

[SkinAuthor$i]
Meter=String
Text=$($Skin.owner.name)
MeterStyle=Skins | Authors
Group=Skins | Authors
Hidden=(($index < ([#Index] + [#ItemsShown])) && ($index >= [#Index]) ? 0 : 1)

[SkinFullName$i]
Meter=String
Text=$($Skin.full_name)
MeterStyle=Skins | FullNames
Group=Skins | FullNames
Hidden=(($index < ([#Index] + [#ItemsShown])) && ($index >= [#Index]) ? 0 : 1)

"@
}

function Variables {
    param (
        [Parameter(Position = 0)]
        [System.Object]
        $Skin,
        [Parameter(Position = 1)]
        [int]
        $Index
    )

    return @"
Link$i=$($Skin.latest_release.browser_download_url)
Version$i=$($Skin.latest_release.tag_name)
"@
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
