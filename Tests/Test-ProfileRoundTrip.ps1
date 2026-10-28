$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'Modules\Storage.psm1') -Force
Import-Module (Join-Path $root 'Modules\Workspace.psm1') -Force
Import-Module (Join-Path $root 'Modules\Startup.psm1') -Force
Initialize-HaySpaceStorage | Out-Null
$name = 'HaySpace-Test-' + [guid]::NewGuid().ToString('N')
$profile = [pscustomobject]@{
    ProfileName = $name
    ProfileType = 'Workspace Layout'
    Version = '1.0'
    BrowserMode = 'Ignore'
    Applications = @(
        [pscustomobject]@{
            ProcessName = 'notepad'
            ProcessPath = 'C:\Windows\System32\notepad.exe'
            Arguments = ''
            Launch = $true
            LaunchOrder = 0
        }
    )
    Windows = @()
    Urls = @()
    ExplorerFolders = @()
    Displays = @()
}
try {
    $displayLayout = @(
        [pscustomobject]@{ DisplayName = 'Left'; DeviceName = '\\.\DISPLAY2'; X = -1920; Y = 0; Width = 1920; Height = 1080; Primary = $false }
        [pscustomobject]@{ DisplayName = 'Main'; DeviceName = '\\.\DISPLAY1'; X = 0; Y = 0; Width = 2560; Height = 1440; Primary = $true }
    )
    $reorderedDisplayLayout = @($displayLayout[1], $displayLayout[0])
    $differentDisplayLayout = @(
        [pscustomobject]@{ DisplayName = 'Left'; DeviceName = '\\.\DISPLAY2'; X = -1920; Y = 0; Width = 1920; Height = 1080; Primary = $false }
        [pscustomobject]@{ DisplayName = 'Main'; DeviceName = '\\.\DISPLAY1'; X = 0; Y = 0; Width = 1920; Height = 1080; Primary = $true }
    )
    $displayKey = Get-HaySpaceDisplayConfigurationKey -Displays $displayLayout
    if ($displayKey -ne (Get-HaySpaceDisplayConfigurationKey -Displays $reorderedDisplayLayout) -or $displayKey -eq (Get-HaySpaceDisplayConfigurationKey -Displays $differentDisplayLayout)) {
        throw 'Display configuration identity was not stable or did not distinguish a resolution change.'
    }
    $startupCommand = Get-HaySpaceStartupCommand -ScriptPath (Join-Path $root 'HaySpace.ps1')
    if ($startupCommand -notmatch '-AutoLoadProfile -Tray' -or $startupCommand -notmatch [regex]::Escape((Join-Path $root 'HaySpace.ps1'))) {
        throw 'The user-logon command did not include display-based startup or the HaySpace script path.'
    }
    Save-HaySpaceProfile -Profile $profile | Out-Null
    $loaded = Get-HaySpaceProfiles | Where-Object ProfileName -eq $name | Select-Object -First 1
    if (-not $loaded -or $loaded.ProfileType -ne 'Workspace Layout' -or @($loaded.Applications).Count -ne 1 -or $loaded.Applications[0].Arguments -ne '' -or -not $loaded.Applications[0].Launch) {
        throw 'Profile JSON round-trip did not preserve profile and application defaults.'
    }
    $legacyProfile = [pscustomobject]@{
        ProfileName = 'Legacy profile'
        ProfileType = 'Quick Layout'
        Applications = @()
        Windows = @()
        BrowserMode = 'Ignore'
    }
    $restoreResult = Restore-HaySpaceWorkspace -Profile $legacyProfile
    if ($restoreResult.RequestedWindows -ne 0 -or $restoreResult.RestoredExplorerFolders -ne 0) {
        throw 'Restoring a legacy profile without optional collections returned unexpected results.'
    }
    Write-Output 'Profile round-trip, legacy restore, and display startup identity passed.'
}
finally {
    Remove-HaySpaceProfile -ProfileName $name
}
