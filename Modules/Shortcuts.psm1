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

function Add-HaySpaceTaskbarShortcut {
    param([Parameter(Mandatory)][string]$ProfileName)
    $shortcutPath = New-HaySpaceShortcut -ProfileName $ProfileName
    $startMenuFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\HaySpace Profiles'
    if (-not (Test-Path -LiteralPath $startMenuFolder)) {
        $null = New-Item -ItemType Directory -Path $startMenuFolder -Force
    }
    $startMenuShortcutPath = Join-Path $startMenuFolder ([IO.Path]::GetFileName($shortcutPath))
    Copy-Item -LiteralPath $shortcutPath -Destination $startMenuShortcutPath -Force

    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($startMenuFolder)
    $item = $folder.ParseName((Split-Path -Leaf $startMenuShortcutPath))
    if (-not $item) {
        throw "Windows could not read the Start menu shortcut '$startMenuShortcutPath'."
    }

    $pinVerb = @($item.Verbs()) |
        Where-Object { ($_.Name -replace '&', '') -match '^\s*Pin to taskbar\s*$' } |
        Select-Object -First 1
    if ($pinVerb) {
        $pinVerb.DoIt()
        Write-HaySpaceLog -Message "Pinned shortcut for '$ProfileName' to the taskbar."
        return [pscustomobject]@{ Pinned = $true; ShortcutPath = $shortcutPath; StartMenuShortcutPath = $startMenuShortcutPath }
    }

    Write-HaySpaceLog -Level Warning -Message "Windows does not expose a taskbar pin command for '$ProfileName'."
    return [pscustomobject]@{ Pinned = $false; ShortcutPath = $shortcutPath; StartMenuShortcutPath = $startMenuShortcutPath }
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

Export-ModuleMember -Function New-HaySpaceShortcut, Add-HaySpaceTaskbarShortcut, Remove-HaySpaceShortcut
