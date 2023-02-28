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
$githubAPI = "https://api.github.com"
$rainmeterSkinsTopic = "$githubAPI/search/repositories?q=topic:rainmeter-skin&per_page=50"
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
    if ($RmApi) {
        Update-InstalledSkinsTable
        if ($RmApi.Variable('Export')) { 
            $RmApi.Bang('!WriteKeyValue Variables Export 0')
            Export
            return "Exporting!"
        }
        Get-UpdateableSkins
    }

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
            if ($Parameter) {
                Update-Skin -FullName $Parameter
            }
            else {
                if (-not($TOKEN)) { throw "`$TOKEN must be set in `".env.ps1`" to use update" }
                Update-Skins
            }
            Export
        }
        "install" {
            Install $Parameter
        }
        "upgrade" {
            Install $Parameter
        }
        "uninstall" {
            Uninstall $Parameter
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

function Sort-Skins {
    param (
        [Parameter(Position = 0)]
        [array]
        $Skins,
        [Parameter()]
        [string]
        $Property = "full_name"
    )
    return $Skins | Sort-Object -Property $Property
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
        $Skin = Set-PackageInformation -Skin $_ -Skins $localPackageList
        if ($Skin) { $Skins += $Skin }
    }

    # Sort skins alphabetically
    $Skins = Sort-Skins $Skins -Property "full_name"

    # Save skins to file
    Save-SkinsList $Skins
}

function Update-Skin {
    param (
        [Parameter(Position = 0)]
        [string]
        $FullName,
        [Parameter()]
        [switch]
        $ForceDownload
    )

    # Existing skins
    $Skins = Get-Skins

    # Get repository information from GitHub
    $Uri = "$githubAPI/repos/$FullName"
    $response = Get-Request $Uri | ConvertFrom-Json 
    $repo = ConvertTo-Skin -InputObject $response

    # Get package information
    $Skin = Set-PackageInformation -Skin $repo -Skins $Skins -ForceDownload:$ForceDownload
    if (-not($Skin)) { return }

    # Check if skin exists
    $skinExists = Find-Skins -Query $Skin.full_name -Skins $Skins
    
    # Handle skin update or addition
    if ($skinExists) {
        $Skins = $Skins | ForEach-Object {
            if ($_.full_name -like $Skin.full_name) { $Skin } else { $_ }
        }
    }
    else {
        $Skins += $Skin
        $Skins = Sort-Skins $Skins 
    }

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
        $Skins,
        [Parameter()]
        [switch]
        $ForceDownload
    )
    $latestRelease = Get-LatestRelease $Skin
    if (-not($latestRelease)) { return $false }
    $Skin.latest_release = $latestRelease

    # Get existing information
    $oldSkin = Find-Skins -Query $Skin.full_name -Skins $Skins -Exact
    $Skin["skin_name"] = $oldSkin.skin_name
    $Skin["skin_name_tag"] = $oldSkin.skin_name_tag

    $SkipDownload = $false
    if ($ForceDownload) {
        Download $Skin
        $SkipDownload = $true
    }
    if (($Skin.skin_name_tag -ne $Skin.latest_release.tag_name) -or ($ForceDownload)) {
        $Skin.skin_name = Get-SkinName -Skin $Skin -SkipDownload:$SkipDownload
        $Skin.skin_name_tag = $Skin.latest_release.tag_name
    }

    return $Skin
}

function Download {
    param (
        [Parameter(Position = 0)]
        [hashtable]
        $Skin,
        [Parameter()]
        [string]
        $FullName,
        [Parameter()]
        [array]
        $Skins
    )
    if (-not($Skin)) { $Skin = Find-Skins -Query $FullName -Skins $Skins }
    if (-not($Skin)) { throw "No skin named $($FullName) found" }

    Write-Host "Downloading $($Skin.full_name)"
    Invoke-WebRequest -Uri $Skin.latest_release.browser_download_url -UseBasicParsing -OutFile $skinFile
}

function Install {
    param (
        [Parameter(Position = 0)]
        [string]
        $FullName
    )
    # Update the skin before installing
    Update-Skin -FullName $FullName -ForceDownload
    if ($RmApi) {
        $RmApi.Bang('!WriteKeyValue Variables Export 1')
    }
    Start-Process -FilePath $skinFile
}

function Uninstall {
    param (
        [Parameter(Position = 0)]
        [string]
        $FullName
    )
    $installed = Get-InstalledSkinsTable
    if (-not($installed[$FullName])) { 
        Write-Host "Skin $FullName is not installed"
        return 
    }

    # Get the skin object
    $Skin = Find-Skins -Query $FullName -Exact

    # Remove the skin folder
    $skinsPath = $RmApi.VariableStr("SKINSPATH")
    Remove-Item -Path "$($skinsPath)$($Skin.skin_name)" -Recurse

    # Report results
    Write-Host "Uninstalled $($Skin.full_name)"
    Update-InstalledSkinsTable
    Export
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
        }
        else {
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
        $Skin,
        [Parameter()]
        [switch]
        $SkipDownload
    )
    if (-not($SkipDownload)) { 
        Download $Skin
    }
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

    # Get installed skins
    $installed = Get-InstalledSkinsTable

    # Generate MetersFile
    for ($i = 0; $i -lt $Skins.Count; $i++) {
        Meter -Skin $Skins[$i] -Index $i -Installed $installed | Out-File -FilePath $MetersFile -Append -Encoding unicode
    }

    Refresh
}

function Meter {
    param (
        [Parameter(Position = 0)]
        [hashtable]
        $Skin,
        [Parameter(Position = 1)]
        [int]
        $Index,
        [Parameter()]
        [hashtable]
        $Installed
    )

    $isInstalled = $Installed[$Skin.full_name]
    $action = if ($isInstalled) { "uninstall" } else { "install" }
    $actionStyle = if ($isInstalled) { "Uninstalls" } else { "Installs" }
    $canUpgrade = (($isInstalled) -and ($installed[$Skin.full_name] -ne $Skin.latest_release.tag_name))

    function Status {
        if ($canUpgrade) { return "Updateable" }
        elseif ( $isInstalled ) { return "Installed" }
        else { return "Available" }
    }

    $upgrade = @"
[SkinUpgradeIcon$i]
Meter=String
MeterStyle=Skins | Hovers | Icons | Upgrades | fa
Group=Skins | Hovers$i
Container=SkinContainer$i
LeftMouseUpAction=[!CommandMeasure MonD "upgrade $($Skin.full_name)"]
"@

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
MeterStyle=Skins | Text | Names | $(Status) | SkinHidden$i
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
MeterStyle=Skins | Hovers | Icons | Actions | $actionStyle | fa
Group=Skins | Hovers$i
Container=SkinContainer$i
LeftMouseUpAction=[!CommandMeasure MonD "$action $($Skin.full_name)"]

$(if( $canUpgrade ) { $upgrade })

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
        $releaseResponse = Get-Request "$($githubAPI)/repos/$($Skin.full_name)/releases/latest" | ConvertFrom-Json
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
    $response = ""
    if ($TOKEN) {
        $response = Invoke-WebRequest -Uri $Uri -Headers @{Authentication = "Bearer $TOKEN" }
    }
    else {
        Write-Host "X-RateLimit-Remaining: $($response.Headers['X-RateLimit-Remaining'])"
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing 
    }
    return $response
}

function Get-ZipEntries {
    # PowerShell 5.0 moment
    [Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem')
    $zip = [IO.Compression.ZipFile]::OpenRead($skinFile)
    $entries = $zip.Entries
    $zip.Dispose()
    return $entries
}

function Get-SkinNameFromZip {
    $entries = Get-ZipEntries
    $skinNamePattern = "Skins\/(.*?)\/"
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
        return
    }

    $Results = Find-Skins -Multiple -Query $Keyword 
    if (-not($Results.Count)) { return "No results" }
    Export -Skins $Results
}

function Refresh {
    if ($RmApi) { $RmApi.Bang('!Refresh') }
}

function Get-InstalledSkinsTable {
    try {
        $installed = Get-Content $installedFile | ConvertFrom-Json
        return ConvertTo-Hashtable $installed
    }
    catch {
        return @{}
    }
}

function Get-InstalledSkins {
    $skinsPath = $RmApi.VariableStr("SKINSPATH")
    $Skins = Get-Skins

    $installedSkins = @()
    Get-ChildItem -Path "$skinsPath" -Directory | ForEach-Object {
        $dir = $_.Name
        $Skin = Find-Skins -Query "^$dir`$" -Property "skin_name" -Skins $Skins
        if ($Skin) { $installedSkins += $Skin }
    }
    return $installedSkins
}

function Get-UpdateableSkins {
    param (
        [Parameter()]
        [switch]
        $SkipRefresh
    )
    $Skins = Get-Skins
    $installed = Get-InstalledSkinsTable

    # Check for updates
    $updateable = @{}
    $updatesAvailable = $false
    foreach ($FullName in $installed.Keys) {
        $Skin = Find-Skins -Query $FullName -Skins $Skins -Exact
        if (-not($Skin)) { continue }
        $v = $Skin.latest_release.tag_name
        if ($installed[$Skin.full_name] -ne $v) { $updateable[$Skin.full_name] = $v } 
    }
    if ($updateable.Count) { $updatesAvailable = $true }

    # Log results
    Write-Host "$($updateable.Count) updates available!"
    if ($SkipRefresh) { return $updateable }
    if ($updatesAvailable) {
        $RmApi.Bang("!SetVariable UpdatesAvailable $($updateable.Keys.Count)")
        $RmApi.Bang("!UpdateMeter *")
        $RmApi.Bang("!Redraw")
    }
}

function Update-InstalledSkinsTable {    
    $installedSkins = Get-InstalledSkins
    $installed = @{}

    # Add self to installed
    if (-not($installed[$self])) {
        $installed[$self] = $version
    }
    # Add skins to installed
    foreach ($skin in $installedSkins) {
        if (-not($installed[$skin.full_name])) {
            $installed[$skin.full_name] = $skin.latest_release.tag_name
        }
    }
    # Log installed skins to rainmeter
    Write-Host "Found $($installed.Count) installed skins!"
    # Save installed.json
    $installed | ConvertTo-Json | Out-File -FilePath $installedFile -Force
}

function ConvertTo-Hashtable {
    param (
        [Parameter(Position = 0)]
        [object]
        $InputObject
    )
    $OutputHashtable = @{}
    $InputObject.psobject.properties | ForEach-Object { $OutputHashtable[$_.Name] = $_.Value }
    return $OutputHashtable
}

Main -Command $Command -Parameter $Parameter
