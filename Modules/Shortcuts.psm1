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
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace((Split-Path -Parent $shortcutPath))
    $item = $folder.ParseName((Split-Path -Leaf $shortcutPath))
    if (-not $item) {
        throw "Windows could not read the generated shortcut '$shortcutPath'."
    }

    $pinVerb = @($item.Verbs()) |
        Where-Object { ($_.Name -replace '&', '') -match '^\s*Pin to taskbar\s*$' } |
        Select-Object -First 1
    if ($pinVerb) {
        $pinVerb.DoIt()
        Write-HaySpaceLog -Message "Pinned shortcut for '$ProfileName' to the taskbar."
        return [pscustomobject]@{ Pinned = $true; ShortcutPath = $shortcutPath }
    }

    Write-HaySpaceLog -Level Warning -Message "Windows does not expose a taskbar pin command for '$ProfileName'."
    return [pscustomobject]@{ Pinned = $false; ShortcutPath = $shortcutPath }
}

function Remove-HaySpaceShortcut {
    param([Parameter(Mandatory)][string]$ProfileName)
    $safeName = [IO.Path]::GetFileNameWithoutExtension($ProfileName) + '.lnk'
    $paths = Get-HaySpacePaths
    foreach ($path in @(
        (Join-Path $paths.Shortcuts $safeName),
        (Join-Path (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar') $safeName)
    )) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}

Export-ModuleMember -Function New-HaySpaceShortcut, Add-HaySpaceTaskbarShortcut, Remove-HaySpaceShortcut
