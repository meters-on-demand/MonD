[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]
    $Command = "version",
    [Parameter(Position = 1)]
    [string]
    $Parameter
)

. .env.ps1

# Constants
$self = "reisir/mond"
$version = "v1.0"
$updateable = @{}
$updatesAvailable = $false

# URLs
$githubAPI = "https://api.github.com/"
$rainmeterSkinsTopic = "$($githubAPI)search/repositories?q=topic:rainmeter-skin&per_page=50"
$github = "https://github.com/"

# Directories
$baseDirectory = $PSScriptRoot
if (-not($PSScriptRoot)) { $baseDirectory = $RmApi.VariableStr('ROOTCONFIGPATH') }
$includeFilesDirectory = "$($baseDirectory)\@Resources\Generated"

# Files
$installedFile = "$baseDirectory\installed.json"
$packageListFile = "$baseDirectory\skins.json"
$skinFile = "$baseDirectory\skin.rmskin"

# Rainmeter update function
function Update {
    return "MonD $version"
}

function Main {
    param (
        [Parameter(Position = 0)]
        [string]
        $Command = "help",
        [Parameter(Position = 1)]
        [string]
        $Parameter
    )

    switch ($Command) {
        "help" { 
            Show-AvailableCommands
        }
        "update" {
            if (-not($TOKEN)) { throw "`$TOKEN must be set in `".env.ps1`" to use update" }
            Update-PackageList
            Export
        }
        "install" {
            Install $Parameter
        }
        "export" {
            Export
        }
        "search" {
            Search $Parameter
        }
        "version" {
            Write-Host "MonD $version"
        }
        Default {
            Write-Host "$Command" -ForegroundColor Red -NoNewline
            Write-Host " is not a command! Use" -NoNewline 
            Write-Host " mond help " -ForegroundColor Blue -NoNewline
            Write-Host "to see available commands!"
        }
    }
}

function Show-AvailableCommands {
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
        }, @{
            Name        = "search"
            Description = "searches the package list"
        }, @{
            Name        = "version"
            Description = "prints the MonD version"
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

function Update-PackageList {

    $allSkins = @()
    Get-RainmeterRepositories | ForEach-Object {
        $skin = @{
            name          = $_.name
            full_name     = $_.full_name
            skin_name     = ""
            has_downloads = $_.has_downloads
            topics        = $_.topics
            owner         = @{
                name       = $_.owner.login
                avatar_url = $_.owner.avatar_url
            }
        }
        $allSkins += $skin
    }

    $Skins = @()
    $allSkins | ForEach-Object {
        $hasRMskin = Get-LatestReleaseAsset $_
        if ($hasRMskin) {
            $_.latest_release = $hasRMskin
            $Skins += $_
        }
    }

    $Skins = Get-AllSkinNames -Skins $Skins

    Save-PackageList $Skins

}

function Get-AllSkinNames {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [array]
        $Skins
    )

    foreach ($Skin in $Skins) {
        Download -FullName $Skin.full_name -Skins $Skins
        $Skins = Set-SkinName -Skin $Skin -Skins $Skins
    }

    return $Skins

}

function Download {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string]
        $FullName,
        [Parameter()]
        [array]
        $Skins
    )

    $skin = Find-Skins -Query $FullName -Skins $Skins

    if (-not($skin)) { throw "No skin named $($FullName) found" }

    Write-Host "Downloading $($skin.full_name)"

    Invoke-WebRequest -Uri $skin.latest_release.browser_download_url -UseBasicParsing -OutFile $skinFile
    
}

function Install {
    param (
        [Parameter(ValueFromPipeline, Position = 0)]
        [string]
        $FullName
    )

    Download -FullName $FullName

    Save-SkinName -Skin $skin

    Start-Process -FilePath $skinFile

}

function Find-Skins {
    param (
        [Parameter(ValueFromPipeline, Position = 0)]
        [string]
        $Query,
        [Parameter()]
        [string]
        $Property = "full_name",
        [Parameter()]
        [array]
        $Skins,
        # Should the query return multiple results in an array?
        [Parameter()]
        [switch]
        $Multiple
    )
    if (-not($Skins)) { $Skins = Get-PackageList }
    $Results = @()
    foreach ($Skin in $Skins) {
        $prop = $Skin | Select-Object -ExpandProperty $Property
        # Write-Host $prop
        if ($prop -match $Query) {
            if ($Multiple) {
                $Results += $Skin
            }
            else { return $Skin }
        }
    }
    return $Results
}

function Save-SkinName {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [System.Object]
        $Skin
    )
    $Skins = Get-PackageList
    $Skins = Set-SkinName -Skin $Skin -Skins $Skins 
    Save-PackageList -Skins $Skins
}

function Set-SkinName {
    [CmdletBinding()]
    param (
        [Parameter()]
        [System.Object]
        $Skin,
        [Parameter()]
        [array]
        $Skins
    )
    for ($i = 0; $i -lt $Skins.Count; $i++) {
        if ($Skins[$i].full_name -like $Skin.full_name) {
            $Skins[$i].skin_name = Get-SkinNameFromZip
            return $Skins
        }
    }
    return $Skins
}

function Export {
    [CmdletBinding()]
    param (
        [Parameter()]
        [array]
        $Skins,
        # File to export meters to
        [Parameter()]
        [string]
        $MetersFile = "$includeFilesDirectory\Meters.inc",
        # File to export meters to
        [Parameter()]
        [string]
        $VariablesFile = "$includeFilesDirectory\SkinVariables.inc"
    )
    if ( -not($Skins)) { $Skins = Get-PackageList }

    # Write VariablesFile
    @"    
[Variables]
Skins=$($Skins.Count)
"@ | Out-File -FilePath $VariablesFile -Force -Encoding unicode

    # Empty MetersFile
    "" | Out-File -FilePath $MetersFile -Force -Encoding unicode
    # Generate MetersFile
    for ($i = 0; $i -lt $Skins.Count; $i++) {
        Meter -Skin $Skins[$i] -Index $i | Out-File -FilePath $MetersFile -Append -Encoding unicode
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
[SkinHidden$i]
Hidden=(($index < ([#Index] + [#ItemsShown])) && ($index >= [#Index]) ? 0 : 1)

[SkinContainer$i]
Meter=Shape
MeterStyle=Containers | SkinHidden$i
Group=Skins | Containers

[SkinBackground$i]
Meter=Shape
MeterStyle=Skins | Backgrounds | SkinHidden$i
Group=Skins | Backgrounds
Container=SkinContainer$i
MouseOverAction=[!ShowMeterGroup Hovers$i]
MouseLeaveAction=[!HideMeterGroup Hovers$i]

[SkinName$i]
Meter=String
Text=$(if($Skin.skin_name) { $Skin.skin_name } else { $Skin.name })
MeterStyle=Skins | Text | Names | SkinHidden$i
Group=Skins | Names
Container=SkinContainer$i

[SkinVersion$i]
Meter=String
Text=$($Skin.latest_release.tag_name)
MeterStyle=Skins | Text | Versions | SkinHidden$i
Group=Skins | Versions
Container=SkinContainer$i

[SkinFullName$i]
Meter=String
Text=$($Skin.full_name)
MeterStyle=Skins | Text | FullNames | SkinHidden$i
Group=Skins | FullNames
Container=SkinContainer$i

[SkinHoverBackground$i]
Meter=Shape
MeterStyle=Skins | Backgrounds | SkinHidden$i | Hovers | HoverBackgrounds
Group=Skins | Hovers$i
Container=SkinContainer$i

[SkinActionIcon$i]
Meter=String
MeterStyle=Skins | Hovers | Icons | Actions | fa
Group=Skins | Hovers$i
Container=SkinContainer$i
LeftMouseUpAction=[!CommandMeasure MonD "install $($Skin.full_name)"]

[SkinGithubIcon$i]
Meter=String
MeterStyle=Skins | Hovers | Icons | Githubs | fa
Group=Skins | Hovers$i
Container=SkinContainer$i
LeftMouseUpAction=["$github$($Skin.full_name)"]

"@
}

function Save-PackageList {
    param (
        [Parameter(Position = 0)]
        [array]
        $Skins
    )
    $Skins | ConvertTo-Json | Out-File -FilePath $packageListFile
}

function Get-PackageList {
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

function Get-LatestReleaseAsset {
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

function Get-SkinNameFromZip {
    $skinNamePattern = "Skins\/(.*?)\/"
    foreach ($sourceFile in (Get-ChildItem -filter $skinFile)) {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($sourceFile)
        $entries = $zip.Entries
        $zip.Dispose()
        foreach ($entry in $entries) {
            if ("$($entry)" -match $skinNamePattern) {
                return $Matches[1]
            }
        }
    }
}

function Search {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Keyword
    )
    $Results = Find-Skins -Multiple -Query $Keyword 
    if (-not($Results.Count)) { return "No results" }
    Export -Skins $Results
    if ($RmApi) { $RmApi.Bang('!Refresh') }
}

function Get-InstalledSkins {
    $skinsPath = $RmApi.VariableStr("SKINSPATH")
    $Skins = Get-PackageList
    $installedSkins = @()
    Get-ChildItem -Path "$skinsPath" -Directory | ForEach-Object {
        $dir = $_.Name
        $Skin = Find-Skins -Query "^$dir`$" -Property "skin_name" -Skins $Skins
        if ($Skin) {
            $installedSkins += $Skin
        }
    }
    
    $installed = @{}
    (Get-Content $installedFile | ConvertFrom-Json).psobject.properties | ForEach-Object { $installed[$_.Name] = $_.Value }

    if (-not($installed[$self])) {
        $installed[$self] = $version
    }
    foreach ($skin in $installedSkins) {
        $v = $skin.latest_release.tag_name
        if (-not($installed[$skin.full_name])) {
            $installed[$skin.full_name] = $v
        }
        if ($installed[$skin.full_name] -ne $v) {
            $updateable[$skin.full_name] = $v
        }
        if ($updateable.Count) { $updatesAvailable = $true }
    }
    Write-Host "Found $($installed.Count) installed skins!"
    $installed | ConvertTo-Json | Out-File -FilePath $installedFile -Force

    if ($updatesAvailable) {
        $RmApi.Bang("!SetVariable UpdatesAvailable $($updateable.Keys.Count)")
        $RmApi.Bang("!UpdateMeter *")
        $RmApi.Bang("!Redraw")
    }
}

if ($RmApi) { Get-InstalledSkins }
else { Main -Command $Command -Parameter $Parameter }
