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

function Remove-HaySpaceShortcut {
    param([Parameter(Mandatory)][string]$ProfileName)
    $path = Join-Path (Get-HaySpacePaths).Shortcuts ([IO.Path]::GetFileNameWithoutExtension($ProfileName) + '.lnk')
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

Export-ModuleMember -Function New-HaySpaceShortcut, Remove-HaySpaceShortcut
