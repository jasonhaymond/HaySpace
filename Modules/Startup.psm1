function Get-HaySpaceStartupRegistryPath {
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
}

function Get-HaySpaceStartupCommand {
    param([Parameter(Mandatory)][string]$ScriptPath)
    $powerShellPath = Join-Path $PSHOME 'powershell.exe'
    $resolvedScriptPath = [IO.Path]::GetFullPath($ScriptPath)
    return '"{0}" -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{1}" -AutoLoadProfile -Tray' -f $powerShellPath, $resolvedScriptPath
}

function Get-HaySpaceRestartCommand {
    param([Parameter(Mandatory)][string]$ScriptPath, [switch]$Tray)
    $powerShellPath = Join-Path $PSHOME 'powershell.exe'
    $resolvedScriptPath = [IO.Path]::GetFullPath($ScriptPath)
    $command = '"{0}" -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{1}"' -f $powerShellPath, $resolvedScriptPath
    if ($Tray) { $command += ' -Tray' }
    return $command
}

function Set-HaySpaceDisplayProfileAssignment {
    param(
        [Parameter(Mandatory)][object[]]$Displays,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProfileName
    )
    $configurationKey = Get-HaySpaceDisplayConfigurationKey -Displays $Displays
    $settings = Get-HaySpaceSettings
    $settings.DisplayProfileAssignments[$configurationKey] = $ProfileName
    Save-HaySpaceSettings $settings
    return $configurationKey
}

function Test-HaySpaceRunAtLogon {
    $runPath = Get-HaySpaceStartupRegistryPath
    if (-not (Test-Path -LiteralPath $runPath)) { return $false }
    $value = Get-ItemProperty -LiteralPath $runPath -Name 'HaySpace' -ErrorAction SilentlyContinue
    return [bool]($value -and $value.HaySpace)
}

function Set-HaySpaceRunAtLogon {
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    $runPath = Get-HaySpaceStartupRegistryPath
    if ($Enabled) {
        $null = New-Item -Path $runPath -Force
        $command = Get-HaySpaceStartupCommand -ScriptPath $ScriptPath
        New-ItemProperty -LiteralPath $runPath -Name 'HaySpace' -Value $command -PropertyType String -Force | Out-Null
    }
    elseif (Test-Path -LiteralPath $runPath) {
        $existing = Get-ItemProperty -LiteralPath $runPath -Name 'HaySpace' -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-ItemProperty -LiteralPath $runPath -Name 'HaySpace'
        }
    }
}

Export-ModuleMember -Function Test-HaySpaceRunAtLogon, Set-HaySpaceRunAtLogon, Get-HaySpaceStartupCommand, Get-HaySpaceRestartCommand, Set-HaySpaceDisplayProfileAssignment
