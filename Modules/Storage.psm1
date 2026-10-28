Set-StrictMode -Version Latest

function Get-HaySpaceRoot {
    if ((Get-Variable -Name HaySpaceRoot -Scope Script -ErrorAction SilentlyContinue) -and $script:HaySpaceRoot) {
        return $script:HaySpaceRoot
    }

    return (Split-Path -Parent $PSScriptRoot)
}

function Get-HaySpacePaths {
    $root = Get-HaySpaceRoot
    return @{
        Root = $root
        Profiles = Join-Path $root 'Profiles'
        Settings = Join-Path $root 'Settings'
        Backups = Join-Path $root 'Backups'
        Logs = Join-Path $root 'Logs'
        Shortcuts = Join-Path $root 'Shortcuts'
    }
}

function Initialize-HaySpaceStorage {
    $paths = Get-HaySpacePaths
    foreach ($path in @($paths.Profiles, $paths.Settings, $paths.Backups, $paths.Logs, $paths.Shortcuts)) {
        if (-not (Test-Path -LiteralPath $path)) {
            $null = New-Item -ItemType Directory -Path $path -Force
        }
    }

    $settingsPath = Join-Path $paths.Settings 'settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        $settings = [pscustomobject]@{
            Version = '1.0'
            DisplayNames = @{}
            DisplayMappings = @{}
            Hotkeys = @()
            StartMinimized = $false
        }
        Save-HaySpaceSettings $settings
    }

    $script:HaySpaceRoot = $paths.Root
    return $paths
}

function Get-HaySpaceSettings {
    $path = Join-Path (Get-HaySpacePaths).Settings 'settings.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ Version = '1.0'; DisplayNames = @{}; DisplayMappings = @{}; Hotkeys = @(); StartMinimized = $false }
    }

    try {
        $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-HaySpaceLog -Level Error -Message "Unable to read settings file '$path': $($_.Exception.Message)"
        throw
    }

    foreach ($mappingName in @('DisplayNames', 'DisplayMappings')) {
        if (-not $settings.PSObject.Properties[$mappingName] -or -not $settings.$mappingName) {
            $settings | Add-Member -NotePropertyName $mappingName -NotePropertyValue @{} -Force
        }
        elseif ($settings.$mappingName -isnot [System.Collections.IDictionary]) {
            $mapping = @{}
            foreach ($property in $settings.$mappingName.PSObject.Properties) {
                $mapping[$property.Name] = [string]$property.Value
            }
            $settings.$mappingName = $mapping
        }
    }
    if (-not $settings.Hotkeys) {
        $settings | Add-Member -NotePropertyName Hotkeys -NotePropertyValue @() -Force
    }
    if (-not $settings.PSObject.Properties['MigrationComputer']) {
        $settings | Add-Member -NotePropertyName MigrationComputer -NotePropertyValue ''
    }
    return $settings
}

function Save-HaySpaceSettings {
    param([Parameter(Mandatory)]$Settings)
    $path = Join-Path (Get-HaySpacePaths).Settings 'settings.json'
    if ($Settings.PSObject.Properties['Version']) {
        $Settings.Version = '1.0'
    }
    else {
        $Settings | Add-Member -NotePropertyName Version -NotePropertyValue '1.0'
    }
    $json = ConvertTo-Json -InputObject $Settings -Depth 20
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Write-HaySpaceLog {
    param(
        [ValidateSet('Debug', 'Information', 'Warning', 'Error')]
        [string]$Level = 'Information',
        [Parameter(Mandatory)][string]$Message
    )
    $paths = Get-HaySpacePaths
    if (-not (Test-Path -LiteralPath $paths.Logs)) {
        $null = New-Item -ItemType Directory -Path $paths.Logs -Force
    }
    $file = Join-Path $paths.Logs ("HaySpace-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
    $line = '{0:u} [{1}] {2}' -f (Get-Date), $Level.ToUpperInvariant(), $Message
    Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    Remove-OldHaySpaceLogs -LogDirectory $paths.Logs
}

function Remove-OldHaySpaceLogs {
    param([Parameter(Mandatory)][string]$LogDirectory)
    $cutoff = (Get-Date).AddDays(-30)
    Get-ChildItem -LiteralPath $LogDirectory -Filter 'HaySpace-*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Get-HaySpaceProfiles {
    $path = (Get-HaySpacePaths).Profiles
    Get-ChildItem -LiteralPath $path -Filter '*.json' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $profile = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($profile.ProfileName -and $profile.Version) {
                    $profile
                }
                else {
                    Write-HaySpaceLog -Level Warning -Message "Skipping invalid profile file '$($_.FullName)'."
                }
            }
            catch {
                Write-HaySpaceLog -Level Warning -Message "Skipping unreadable profile file '$($_.FullName)': $($_.Exception.Message)"
            }
        } | Sort-Object ProfileName
}

function Get-HaySpaceProfilePath {
    param([Parameter(Mandatory)][string]$ProfileName)
    $safeName = $ProfileName.Trim()
    if ([string]::IsNullOrWhiteSpace($safeName) -or $safeName -match '[<>:"/\\|?*]' -or $safeName -match '[\. ]$' -or $safeName -in @('.', '..')) {
        throw "Invalid profile name '$ProfileName'."
    }
    return Join-Path (Get-HaySpacePaths).Profiles ($safeName + '.json')
}

function Save-HaySpaceProfile {
    param([Parameter(Mandatory)]$Profile)
    if ([string]::IsNullOrWhiteSpace([string]$Profile.ProfileName)) {
        throw 'A profile name is required.'
    }
    $Profile.ProfileName = ([string]$Profile.ProfileName).Trim()
    if ($Profile.PSObject.Properties['Version']) { $Profile.Version = '1.0' } else { $Profile | Add-Member -NotePropertyName Version -NotePropertyValue '1.0' }
    if ($Profile.PSObject.Properties['UpdatedAt']) { $Profile.UpdatedAt = (Get-Date).ToString('o') } else { $Profile | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue (Get-Date).ToString('o') }
    $path = Get-HaySpaceProfilePath -ProfileName ([string]$Profile.ProfileName)
    $json = ConvertTo-Json -InputObject $Profile -Depth 30
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
    Write-HaySpaceLog -Message "Saved profile '$($Profile.ProfileName)'."
    return $path
}

function Remove-HaySpaceProfile {
    param([Parameter(Mandatory)][string]$ProfileName)
    $path = Get-HaySpaceProfilePath -ProfileName $ProfileName
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        Write-HaySpaceLog -Message "Deleted profile '$ProfileName'."
    }
}

function Export-HaySpaceBackup {
    param([Parameter(Mandatory)][string]$DestinationPath)
    $paths = Get-HaySpacePaths
    $stage = Join-Path $env:TEMP ('HaySpaceBackup-' + [guid]::NewGuid().ToString('N'))
    $fullDestinationPath = [IO.Path]::GetFullPath($DestinationPath)
    $destinationDirectory = [IO.Path]::GetDirectoryName($fullDestinationPath)
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        $null = New-Item -ItemType Directory -Path $destinationDirectory -Force
    }
    $temporaryArchive = Join-Path $destinationDirectory ('.HaySpaceBackup-' + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        $null = New-Item -ItemType Directory -Path $stage -Force
        foreach ($name in @('Profiles', 'Settings', 'Shortcuts')) {
            $source = Join-Path $paths.Root $name
            if (Test-Path -LiteralPath $source) {
                Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
            }
        }
        $manifest = [pscustomobject]@{ Product = 'HaySpace'; Version = '1.0'; CreatedAt = (Get-Date).ToString('o'); Contents = @('Profiles', 'Settings', 'Shortcuts') }
        $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding UTF8
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $temporaryArchive -CompressionLevel Optimal
        Move-Item -LiteralPath $temporaryArchive -Destination $fullDestinationPath -Force
        Write-HaySpaceLog -Message "Created backup '$fullDestinationPath'."
    }
    finally {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath $stage -Recurse -Force
        }
        if (Test-Path -LiteralPath $temporaryArchive) {
            Remove-Item -LiteralPath $temporaryArchive -Force
        }
    }
}

function Import-HaySpaceBackup {
    param([Parameter(Mandatory)][string]$ArchivePath)
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Backup archive not found: $ArchivePath"
    }
    $stage = Join-Path $env:TEMP ('HaySpaceRestore-' + [guid]::NewGuid().ToString('N'))
    $rollback = Join-Path $env:TEMP ('HaySpaceRollback-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $stage -Force
        $manifestPath = Join-Path $stage 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            throw 'The selected archive is not a HaySpace backup (manifest.json is missing).'
        }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($manifest.Product -ne 'HaySpace') {
            throw 'The selected archive is not a HaySpace backup.'
        }
        $paths = Get-HaySpacePaths
        $allowedFolders = @('Profiles', 'Settings', 'Shortcuts')
        $folders = if ($manifest.PSObject.Properties['Contents'] -and $manifest.Contents) { @($manifest.Contents) } else { @($allowedFolders | Where-Object { Test-Path -LiteralPath (Join-Path $stage $_) }) }
        if (@($folders | Where-Object { $_ -notin $allowedFolders }).Count -gt 0) {
            throw 'The backup manifest contains an unsupported data folder.'
        }
        $null = New-Item -ItemType Directory -Path $rollback -Force
        $replaced = @()
        try {
            foreach ($name in $folders) {
                $destination = Join-Path $paths.Root $name
                $previous = Join-Path $rollback $name
                if (Test-Path -LiteralPath $destination) {
                    Move-Item -LiteralPath $destination -Destination $previous
                }
                $replaced += $name
                $source = Join-Path $stage $name
                if (Test-Path -LiteralPath $source) {
                    Copy-Item -LiteralPath $source -Destination $paths.Root -Recurse -Force
                }
                else {
                    $null = New-Item -ItemType Directory -Path $destination -Force
                }
            }
        }
        catch {
            for ($index = $replaced.Count - 1; $index -ge 0; $index--) {
                $name = $replaced[$index]
                $destination = Join-Path $paths.Root $name
                $previous = Join-Path $rollback $name
                if (Test-Path -LiteralPath $destination) {
                    Remove-Item -LiteralPath $destination -Recurse -Force
                }
                if (Test-Path -LiteralPath $previous) {
                    Move-Item -LiteralPath $previous -Destination $destination
                }
            }
            throw
        }
        Write-HaySpaceLog -Message "Restored backup '$ArchivePath'."
    }
    finally {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath $stage -Recurse -Force
        }
        if (Test-Path -LiteralPath $rollback) {
            Remove-Item -LiteralPath $rollback -Recurse -Force
        }
    }
}

Export-ModuleMember -Function Get-HaySpaceRoot, Get-HaySpacePaths, Initialize-HaySpaceStorage, Get-HaySpaceSettings, Save-HaySpaceSettings, Write-HaySpaceLog, Get-HaySpaceProfiles, Get-HaySpaceProfilePath, Save-HaySpaceProfile, Remove-HaySpaceProfile, Export-HaySpaceBackup, Import-HaySpaceBackup
