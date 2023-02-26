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
$skinListFile = "$baseDirectory\skins.json"
$skinFile = "$baseDirectory\skin.rmskin"

# Rainmeter update function
function Update {
    return "MonD $version"
}

function Main {
    param (
        [Parameter(Position = 0)]
        [string]
        $Command,
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
            Update-Skins
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
            Description = "update the skins list"
        }, @{
            Name        = "install"
            Description = "installs the specified skin"
            Parameters  = @(@{
                    Name        = "skin" 
                    Description = "the full name of the skin to install"
                })
        }, @{
            Name        = "search"
            Description = "searches the skin list"
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

function Get-Skins {
    if ( -not(Test-Path -Path $skinListFile) ) { return $false }
    $hsh = @()
    $sk = Get-Content $skinListFile | ConvertFrom-Json
    $sk | ForEach-Object { $hsh += ConvertTo-Hashtable -InputObject $_ }
    return $hsh
}

function Update-Skins {
    # Get all repositories from the rainmeter-skin topic on GitHub
    $allPackages = @()
    Get-RainmeterRepositories | ForEach-Object {
        $allPackages += ConvertTo-Skin -InputObject $_
    }

    # Add manually tracked repositories to the repository list
    $localPackageList = Get-Skins
    if ($localPackageList) {
        $localPackageList | ForEach-Object {
            if (-not(Find-Skins -Query $_.full_name -Skins $allPackages)) { 
                $allPackages += $_
            }
        }
    }

    # Filter out repositories with no packages
    $Skins = @()
    $allPackages | ForEach-Object {
        $Skin = Set-PackageInformation -Skin $_ -ExistingSkins $localPackageList
        if ($Skin) { $Skins += $Skin }
    }

    # Sort skins alphabetically
    $Skins = $Skins | Sort-Object -Property "full_name"

    # Save skins to file
    Save-SkinsList $Skins
}

function ConvertTo-Skin {
    param (
        [Parameter()]
        [object]
        $InputObject
    )
    return @{
        name          = $InputObject.name
        full_name     = $InputObject.full_name
        has_downloads = $InputObject.has_downloads
        topics        = $InputObject.topics
        owner         = @{
            name       = $InputObject.owner.login
            avatar_url = $InputObject.owner.avatar_url
        }
    }
}

function Set-PackageInformation {
    param (
        [Parameter(Position = 0, Mandatory)]
        [hashtable]
        $Skin,
        [Parameter(Mandatory)]
        [array]
        $ExistingSkins
    )
    $latestRelease = Get-LatestRelease $Skin
    if (-not($latestRelease)) { return $false }
    $Skin.latest_release = $latestRelease

    # Get existing information
    $oldSkin = Find-Skins -Query $Skin.full_name -Skins $ExistingSkins -Exact
    $Skin["skin_name"] = $oldSkin.skin_name
    $Skin["skin_name_tag"] = $oldSkin.skin_name_tag

    if($Skin.skin_name_tag -ne $Skin.latest_release.tag_name) {
        $Skin.skin_name = Get-SkinName -Skin $Skin
        $Skin.skin_name_tag = $Skin.latest_release.tag_name
    }

    return $Skin
}

function Download {
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

    # TODO: call Update-Skin to set the SkinName

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
        $Multiple,
        # Should the match be exact?
        [Parameter()]
        [switch]
        $Exact
    )
    if (-not($Skins)) { $Skins = Get-Skins }
    $Results = @()
    foreach ($Skin in $Skins) {
        $prop = $Skin[$Property]
        $doesMatch = $false 
        if ($Exact) {
            $doesMatch = ($prop -like $Query)
        } else {
            $doesMatch = ($prop -match $Query)
        }
        if ($doesMatch) {
            if ($Multiple) {
                $Results += $Skin
            }
            else { return $Skin }
        }
    }
    return $Results
}

function Get-SkinName {
    param (
        [Parameter()]
        [hashtable]
        $Skin
    )
    Download -FullName $Skin.full_name
    $SkinName = Get-SkinNameFromZip
    return $SkinName
}

function Export {
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
    if ( -not($Skins)) { $Skins = Get-Skins }

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
        [hashtable]
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

function Save-SkinsList {
    param (
        [Parameter(Position = 0)]
        [array]
        $Skins
    )
    $Skins | ConvertTo-Json | Out-File -FilePath $skinListFile
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

function Get-LatestRelease {
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
    $zip = [System.IO.Compression.ZipFile]::OpenRead($skinFile)
    $entries = $zip.Entries
    $zip.Dispose()
    foreach ($entry in $entries) {
        if ("$($entry)" -match $skinNamePattern) {
            return $Matches[1]
        }
    }
}

function Search {
    param (
        [Parameter(Position = 0, Mandatory = $false)]
        [string]
        $Keyword
    )

    if (-not($Keyword)) {
        Export
        if ($RmApi) { $RmApi.Bang('!Refresh') }
        return
    }

    $Results = Find-Skins -Multiple -Query $Keyword 
    if (-not($Results.Count)) { return "No results" }
    Export -Skins $Results
    if ($RmApi) { $RmApi.Bang('!Refresh') }
}

function Get-InstalledSkins {
    $skinsPath = $RmApi.VariableStr("SKINSPATH")
    $Skins = Get-Skins
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

function ConvertTo-Hashtable {
    param (
        [Parameter()]
        [object]
        $InputObject
    )
    $OutputHashtable = @{}
    $InputObject.psobject.properties | ForEach-Object { $OutputHashtable[$_.Name] = $_.Value }
    return $OutputHashtable
}

if ($RmApi) { Get-InstalledSkins }
else { Main -Command $Command -Parameter $Parameter }
