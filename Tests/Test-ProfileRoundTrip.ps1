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
            AppUserModelId = 'MSTeams_8weky3d8bbwe!MSTeams'
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
$assignmentKey = $null
$hadPreviousAssignment = $false
$previousAssignment = $null
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
    $windowDetection = & (Get-Module Workspace) {
        param($visibleWindow)
        [pscustomobject]@{
            BackgroundOnly = -not (Test-HaySpaceApplicationWindowOpen -Windows @() -ProcessName 'msedge')
            VisibleWindow = Test-HaySpaceApplicationWindowOpen -Windows @($visibleWindow) -ProcessName 'msedge'
            OtherProcess = -not (Test-HaySpaceApplicationWindowOpen -Windows @($visibleWindow) -ProcessName 'chrome')
        }
    } ([pscustomobject]@{ ProcessName = 'msedge'; Width = 1280; Height = 720 })
    if (-not $windowDetection.BackgroundOnly -or -not $windowDetection.VisibleWindow -or -not $windowDetection.OtherProcess) {
        throw 'Browser window detection did not distinguish visible windows from background processes.'
    }
    $teamsDetection = & (Get-Module Workspace) {
        param($installedApps)
        [pscustomobject]@{
            RunningProcessDetectedWithoutWindow = Test-HaySpaceApplicationProcessRunning -ProcessName (Get-Process -Id $PID).ProcessName
            MissingProcessDetected = Test-HaySpaceApplicationProcessRunning -ProcessName ('HaySpaceMissing-' + [guid]::NewGuid().ToString('N'))
            AppUserModelId = Resolve-HaySpaceApplicationUserModelId -ProcessName 'ms-teams' -InstalledApps $installedApps
        }
    } @(
        [pscustomobject]@{ Name = 'Microsoft Teams'; AppID = 'MSTeams_8wekyb3d8bbwe!MSTeams' }
        [pscustomobject]@{ Name = 'Microsoft Teams'; AppID = 'MicrosoftTeams_legacy!Teams' }
    )
    if (-not $teamsDetection.RunningProcessDetectedWithoutWindow -or $teamsDetection.MissingProcessDetected -or
        $teamsDetection.AppUserModelId -ne 'MSTeams_8wekyb3d8bbwe!MSTeams') {
        throw 'Teams tray-process detection or installed-app identity resolution failed.'
    }
    $targetTracking = & (Get-Module Workspace) {
        $placedTargets = @{}
        $pendingBeforePlacement = Test-HaySpaceWindowTargetPending -TargetKey '0' -PlacedTargets $placedTargets
        $placedTargets['0'] = $true
        $simulatedWindowState = 'Minimized'
        [pscustomobject]@{
            PendingBeforePlacement = $pendingBeforePlacement
            PendingAfterMinimizingArrangedWindow = Test-HaySpaceWindowTargetPending -TargetKey '0' -PlacedTargets $placedTargets
            PendingUnopenedTarget = Test-HaySpaceWindowTargetPending -TargetKey '1' -PlacedTargets $placedTargets
            SimulatedWindowState = $simulatedWindowState
        }
    }
    if (-not $targetTracking.PendingBeforePlacement -or $targetTracking.PendingAfterMinimizingArrangedWindow -or
        -not $targetTracking.PendingUnopenedTarget -or $targetTracking.SimulatedWindowState -ne 'Minimized') {
        throw 'Arranged windows were not removed from restore tracking after placement.'
    }

    $unlaunchedWindowProfile = [pscustomobject]@{
        ProfileName = 'Unlaunched window timing regression'
        ProfileType = 'Workspace Layout'
        BrowserMode = 'Ignore'
        Applications = @([pscustomobject]@{ ProcessName = 'HaySpaceMissingApp'; Launch = $false })
        Windows = @([pscustomobject]@{ ProcessName = 'HaySpaceMissingApp'; Title = 'Unlaunched HaySpace test window'; ProcessPath = '' })
    }
    $restoreTimer = [Diagnostics.Stopwatch]::StartNew()
    $unlaunchedRestore = Restore-HaySpaceWorkspace -Profile $unlaunchedWindowProfile -LaunchApplications
    $restoreTimer.Stop()
    if ($unlaunchedRestore.PositionedWindows -ne 0 -or $restoreTimer.Elapsed.TotalSeconds -ge 5) {
        throw "Restore waited $([math]::Round($restoreTimer.Elapsed.TotalSeconds, 2)) seconds for an application HaySpace did not launch."
    }

    $assignmentDisplays = @(
        [pscustomobject]@{ DisplayName = 'HaySpace test display ' + [guid]::NewGuid().ToString('N'); DeviceName = '\\.\DISPLAY_TEST'; X = 0; Y = 0; Width = 1280; Height = 720; Primary = $true }
    )
    $assignmentKey = Get-HaySpaceDisplayConfigurationKey -Displays $assignmentDisplays
    $settingsBeforeAssignment = Get-HaySpaceSettings
    $hadPreviousAssignment = $settingsBeforeAssignment.DisplayProfileAssignments.ContainsKey($assignmentKey)
    $previousAssignment = if ($hadPreviousAssignment) { [string]$settingsBeforeAssignment.DisplayProfileAssignments[$assignmentKey] } else { $null }
    Set-HaySpaceDisplayProfileAssignment -Displays $assignmentDisplays -ProfileName $name | Out-Null
    $savedAssignment = (Get-HaySpaceSettings).DisplayProfileAssignments[$assignmentKey]
    if ($savedAssignment -ne $name) {
        throw 'The selected default profile was not saved for the display configuration.'
    }
    $startupCommand = Get-HaySpaceStartupCommand -ScriptPath (Join-Path $root 'HaySpace.ps1')
    $startupLauncher = Get-Content -LiteralPath (Join-Path $root 'Start-HaySpace.vbs') -Raw
    if ($startupCommand -notmatch [regex]::Escape((Join-Path $root 'Start-HaySpace.vbs')) -or
        $startupCommand -notmatch 'wscript\.exe.*//B //NoLogo' -or
        $startupLauncher -notmatch 'shell\.Run command, 0, False' -or
        $startupLauncher -notmatch '-AutoLoadProfile -Tray') {
        throw 'The user-logon command did not launch HaySpace invisibly through its VBScript launcher.'
    }
    $trayRestartCommand = Get-HaySpaceRestartCommand -ScriptPath (Join-Path $root 'HaySpace.ps1') -Tray
    $guiRestartCommand = Get-HaySpaceRestartCommand -ScriptPath (Join-Path $root 'HaySpace.ps1')
    if ($trayRestartCommand -notmatch '-Tray' -or $trayRestartCommand -match '-AutoLoadProfile' -or
        $guiRestartCommand -match '-Tray|-AutoLoadProfile' -or
        $trayRestartCommand -notmatch [regex]::Escape((Join-Path $root 'HaySpace.ps1'))) {
        throw 'Restart commands did not preserve the tray mode without repeating automatic profile loading.'
    }
    $launcherContents = Get-Content -LiteralPath (Join-Path $root 'Start-HaySpace.cmd') -Raw
    if ($launcherContents -notmatch '(?s)if.*?start "" powershell\.exe.*?-WindowStyle Hidden.*?else.*?start "" powershell\.exe.*?-WindowStyle Hidden') {
        throw 'The command launcher must start both normal and argument-bearing HaySpace instances hidden and detached.'
    }
    Save-HaySpaceProfile -Profile $profile | Out-Null
    $loaded = Get-HaySpaceProfiles | Where-Object ProfileName -eq $name | Select-Object -First 1
    if (-not $loaded -or $loaded.ProfileType -ne 'Workspace Layout' -or @($loaded.Applications).Count -ne 1 -or $loaded.Applications[0].Arguments -ne '' -or -not $loaded.Applications[0].Launch -or $loaded.Applications[0].AppUserModelId -ne 'MSTeams_8weky3d8bbwe!MSTeams') {
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
    if ($assignmentKey) {
        $settings = Get-HaySpaceSettings
        if ($hadPreviousAssignment) {
            $settings.DisplayProfileAssignments[$assignmentKey] = $previousAssignment
        }
        else {
            $settings.DisplayProfileAssignments.Remove($assignmentKey)
        }
        Save-HaySpaceSettings $settings
    }
}
