function New-HaySpaceShortcut {
    param([Parameter(Mandatory)][string]$ProfileName)
    $paths = Get-HaySpacePaths
    $safeName = [IO.Path]::GetFileNameWithoutExtension($ProfileName)
    $launcher = Join-Path $paths.Root 'HaySpace.ps1'
    $shortcutPath = Join-Path $paths.Shortcuts ($safeName + '.lnk')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $launcher + '" -LoadProfile "' + $safeName + '"'
    $shortcut.WorkingDirectory = $paths.Root
    $shortcut.Description = 'Load HaySpace profile: ' + $safeName
    $shortcut.Save()
    Write-HaySpaceLog -Message "Created shortcut for '$safeName'."
    return $shortcutPath
}

function New-HaySpaceApplicationShortcut {
    param([Parameter(Mandatory)][string]$DestinationDirectory)
    $paths = Get-HaySpacePaths
    $launcher = Join-Path $paths.Root 'Start-HaySpace.cmd'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw "HaySpace launcher was not found: '$launcher'."
    }
    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        $null = New-Item -ItemType Directory -Path $DestinationDirectory -Force
    }
    $shortcutPath = Join-Path $DestinationDirectory 'HaySpace.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $launcher
    $shortcut.WorkingDirectory = $paths.Root
    $shortcut.Description = 'Start HaySpace'
    $shortcut.Save()
    Write-HaySpaceLog -Message "Created HaySpace application shortcut '$shortcutPath'."
    return $shortcutPath
}

function New-HaySpaceStartMenuProfileShortcut {
    param(
        [Parameter(Mandatory)][string]$ShortcutPath,
        [Parameter(Mandatory)][string]$StartMenuFolder
    )
    if (-not (Test-Path -LiteralPath $StartMenuFolder)) {
        $null = New-Item -ItemType Directory -Path $StartMenuFolder -Force
    }
    $startMenuShortcutPath = Join-Path $StartMenuFolder ([IO.Path]::GetFileName($ShortcutPath))
    Copy-Item -LiteralPath $ShortcutPath -Destination $startMenuShortcutPath -Force
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($StartMenuFolder)
    $item = $folder.ParseName((Split-Path -Leaf $startMenuShortcutPath))
    if (-not $item) {
        throw "Windows could not read the Start menu shortcut '$startMenuShortcutPath'."
    }

    $pinVerb = @($item.Verbs()) |
        Where-Object { ($_.Name -replace '&', '') -match '^\s*Pin to taskbar\s*$' } |
        Select-Object -First 1
    if ($pinVerb) {
        $pinVerb.DoIt()
        return [pscustomobject]@{ Pinned = $true; StartMenuShortcutPath = $startMenuShortcutPath }
    }
    return [pscustomobject]@{ Pinned = $false; StartMenuShortcutPath = $startMenuShortcutPath }
}

function New-HaySpaceDesktopShortcut {
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    return New-HaySpaceApplicationShortcut -DestinationDirectory $desktop
}

function Add-HaySpaceApplicationTaskbarShortcut {
    $paths = Get-HaySpacePaths
    $shortcutPath = New-HaySpaceApplicationShortcut -DestinationDirectory $paths.Shortcuts
    $startMenuFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\HaySpace'
    $pinResult = New-HaySpaceStartMenuProfileShortcut -ShortcutPath $shortcutPath -StartMenuFolder $startMenuFolder
    if ($pinResult.Pinned) {
        Write-HaySpaceLog -Message 'Pinned HaySpace application shortcut to the taskbar.'
    }
    else {
        Write-HaySpaceLog -Level Warning -Message 'Windows does not expose a taskbar pin command for the HaySpace application shortcut.'
    }
    return [pscustomobject]@{
        Pinned = $pinResult.Pinned
        ShortcutPath = $shortcutPath
        StartMenuShortcutPath = $pinResult.StartMenuShortcutPath
    }
}

function Add-HaySpaceTaskbarShortcut {
    param([Parameter(Mandatory)][string]$ProfileName)
    $shortcutPath = New-HaySpaceShortcut -ProfileName $ProfileName
    $startMenuFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\HaySpace Profiles'
    $pinResult = New-HaySpaceStartMenuProfileShortcut -ShortcutPath $shortcutPath -StartMenuFolder $startMenuFolder
    if ($pinResult.Pinned) {
        Write-HaySpaceLog -Message "Pinned shortcut for '$ProfileName' to the taskbar."
    }
    else {
        Write-HaySpaceLog -Level Warning -Message "Windows does not expose a taskbar pin command for '$ProfileName'."
    }
    return [pscustomobject]@{ Pinned = $pinResult.Pinned; ShortcutPath = $shortcutPath; StartMenuShortcutPath = $pinResult.StartMenuShortcutPath }
}

function Remove-HaySpaceShortcut {
    param([Parameter(Mandatory)][string]$ProfileName)
    $safeName = [IO.Path]::GetFileNameWithoutExtension($ProfileName) + '.lnk'
    $paths = Get-HaySpacePaths
    foreach ($path in @(
        (Join-Path $paths.Shortcuts $safeName),
        (Join-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\HaySpace Profiles') $safeName),
        (Join-Path (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar') $safeName)
    )) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}

Export-ModuleMember -Function New-HaySpaceShortcut, New-HaySpaceApplicationShortcut, New-HaySpaceStartMenuProfileShortcut, New-HaySpaceDesktopShortcut, Add-HaySpaceApplicationTaskbarShortcut, Add-HaySpaceTaskbarShortcut, Remove-HaySpaceShortcut
