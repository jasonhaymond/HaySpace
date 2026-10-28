[CmdletBinding()]
param(
    [string]$LoadProfile,
    [switch]$Capture,
    [switch]$Tray,
    [switch]$AutoLoadProfile
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:HaySpaceScriptPath = $PSCommandPath
foreach ($module in @('Storage.psm1', 'Workspace.psm1', 'Shortcuts.psm1', 'Startup.psm1')) {
    Import-Module (Join-Path (Join-Path $root 'Modules') $module) -Force
}
$script:HaySpaceDpiContext = [HaySpace.NativeWindow]::EnterPhysicalCoordinates()
$paths = Initialize-HaySpaceStorage

if ($LoadProfile) {
    $profilePath = Get-HaySpaceProfilePath -ProfileName $LoadProfile
    if (-not (Test-Path -LiteralPath $profilePath)) {
        throw "Profile '$LoadProfile' was not found."
    }
    $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = Restore-HaySpaceWorkspace -Profile $profile -LaunchApplications
    Write-Output "Restored '$LoadProfile': $($result.PositionedWindows) window(s) positioned."
    exit 0
}

if ($Capture) {
    $name = Read-Host 'Profile name'
    $profile = New-HaySpaceCapture -ProfileName $name
    Save-HaySpaceProfile -Profile $profile | Out-Null
    Write-Output "Captured '$name'."
    exit 0
}

$mutexName = 'Local\HaySpace-{0}' -f [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$script:HaySpaceInstanceMutex = [System.Threading.Mutex]::new($false, $mutexName)
try {
    $ownsInstanceMutex = $script:HaySpaceInstanceMutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] {
    $ownsInstanceMutex = $true
}
if (-not $ownsInstanceMutex) {
    Write-HaySpaceLog -Message 'HaySpace is already running for this user; ignoring the duplicate GUI launch.'
    $script:HaySpaceInstanceMutex.Dispose()
    exit 0
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
$xamlPath = Join-Path $root 'UI\MainWindow.xaml'
[xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$window.Title = 'HaySpace'
$window.WindowStartupLocation = 'CenterScreen'

$script:ProfileList = $window.FindName('ProfileList')
$script:ProfileSummary = $window.FindName('ProfileSummary')
$script:StatusText = $window.FindName('StatusText')
$script:DisplayList = $window.FindName('DisplayList')
$script:SettingsRoot = $window.FindName('SettingsRoot')
$script:RunAtLogonCheckBox = $window.FindName('RunAtLogonCheckBox')
$script:ExitRequested = $false
$script:HotkeyIds = @{}
$script:HotkeySource = $null
$script:HotkeyHook = $null

function Set-Status([string]$Text) {
    $script:StatusText.Text = $Text
}

function Minimize-HaySpaceToTray {
    $window.ShowInTaskbar = $false
    $window.WindowState = 'Minimized'
}

function Show-HaySpaceDashboard {
    $window.ShowInTaskbar = $true
    $window.Show()
    $window.WindowState = 'Normal'
    $window.Activate()
}

function Refresh-Profiles {
    $selectedName = if ($script:ProfileList.SelectedItem) { [string]$script:ProfileList.SelectedItem.ProfileName } else { $null }
    $script:ProfileList.ItemsSource = $null
    $script:ProfileList.ItemsSource = @(Get-HaySpaceProfiles)
    if ($selectedName) {
        $script:ProfileList.SelectedItem = $script:ProfileList.ItemsSource | Where-Object ProfileName -eq $selectedName | Select-Object -First 1
    }
    if (-not $script:ProfileList.SelectedItem -and $script:ProfileList.Items.Count -gt 0) {
        $script:ProfileList.SelectedIndex = 0
    }
}

function Refresh-Displays {
    $script:DisplayList.ItemsSource = $null
    $script:DisplayList.ItemsSource = @(Get-HaySpaceDisplays)
}

function Show-HaySpaceDisplayIdentification {
    param([Parameter(Mandatory)]$Display, [int]$DurationMilliseconds = 1400)
    $screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object DeviceName -eq $Display.DeviceName | Select-Object -First 1
    if (-not $screen) { throw "Display '$($Display.DisplayName)' is no longer connected." }

    $overlay = New-Object System.Windows.Forms.Form
    $overlay.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $overlay.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $overlay.Bounds = $screen.Bounds
    $overlay.TopMost = $true
    $overlay.BackColor = [System.Drawing.Color]::FromArgb(35, 92, 232)
    $label = New-Object System.Windows.Forms.Label
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.Text = "{0}`n{1} x {2}`n{3}" -f $Display.DisplayName, $Display.Width, $Display.Height, $Display.DeviceName
    $label.ForeColor = [System.Drawing.Color]::White
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $overlay.Controls.Add($label)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [math]::Max(500, $DurationMilliseconds)
    $overlayToClose = $overlay
    $timer.Add_Tick({
        param($sender, $eventArgs)
        $sender.Stop()
        $overlayToClose.Close()
    }.GetNewClosure())
    try {
        $timer.Start()
        $null = $overlay.ShowDialog()
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        $overlay.Dispose()
    }
}

function Show-StartupProfileChooser {
    param([Parameter(Mandatory)][object[]]$Profiles, [Parameter(Mandatory)][string]$DisplaySummary)
    $dialog = New-Object System.Windows.Window
    $dialog.Title = 'Choose workspace for connected displays'
    $dialog.Width = 560
    $dialog.Height = 430
    $dialog.MinWidth = 460
    $dialog.MinHeight = 340
    $dialog.WindowStartupLocation = 'CenterScreen'
    $dialog.ResizeMode = 'CanResize'
    $layout = New-Object System.Windows.Controls.DockPanel
    $layout.Margin = '18'
    $description = New-Object System.Windows.Controls.TextBlock
    $description.Text = "No exact saved display configuration matched. Choose a profile for this layout:`n$DisplaySummary"
    $description.TextWrapping = 'Wrap'
    $description.Margin = '0,0,0,12'
    [System.Windows.Controls.DockPanel]::SetDock($description, 'Top')
    $layout.Children.Add($description) | Out-Null
    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = '0,12,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($buttons, 'Bottom')
    $loadButton = New-Object System.Windows.Controls.Button
    $loadButton.Content = 'Load selected'
    $loadButton.IsDefault = $true
    $loadButton.MinWidth = 100
    $loadButton.Margin = '4'
    $cancelButton = New-Object System.Windows.Controls.Button
    $cancelButton.Content = 'Cancel'
    $cancelButton.IsCancel = $true
    $cancelButton.MinWidth = 80
    $cancelButton.Margin = '4'
    $buttons.Children.Add($loadButton) | Out-Null
    $buttons.Children.Add($cancelButton) | Out-Null
    $layout.Children.Add($buttons) | Out-Null
    $list = New-Object System.Windows.Controls.ListBox
    $list.DisplayMemberPath = 'ProfileName'
    $list.ItemsSource = $Profiles
    if ($Profiles.Count -gt 0) { $list.SelectedIndex = 0 }
    $layout.Children.Add($list) | Out-Null
    $loadButton.Add_Click({
        if ($list.SelectedItem) { $dialog.DialogResult = $true }
    }.GetNewClosure())
    $dialog.Content = $layout
    if ($dialog.ShowDialog()) { return $list.SelectedItem }
    return $null
}

function Show-InstalledAppPicker {
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)]$Owner)
    $installedApps = @(Get-StartApps | Where-Object { $_.Name -and $_.AppID } | Sort-Object Name, AppID)
    if (-not $installedApps.Count) { throw 'Windows did not return any installed Start-menu apps.' }
    $processNames = @(
        @($Profile.Applications | ForEach-Object ProcessName)
        @($Profile.Windows | ForEach-Object ProcessName)
        @([HaySpace.NativeWindow]::GetWindows() | ForEach-Object ProcessName)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique

    $dialog = New-Object Windows.Window
    $dialog.Title = 'Add installed Windows app'
    $dialog.Width = 560
    $dialog.Height = 520
    $dialog.MinWidth = 480
    $dialog.MinHeight = 400
    $dialog.Owner = $Owner
    $dialog.WindowStartupLocation = 'CenterOwner'
    $panel = New-Object Windows.Controls.DockPanel
    $panel.Margin = '18'
    $buttons = New-Object Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = '0,12,0,0'
    [Windows.Controls.DockPanel]::SetDock($buttons, 'Bottom')
    $addButton = New-Object Windows.Controls.Button
    $addButton.Content = 'Add app'
    $addButton.IsDefault = $true
    $addButton.IsEnabled = $false
    $cancelButton = New-Object Windows.Controls.Button
    $cancelButton.Content = 'Cancel'
    $cancelButton.IsCancel = $true
    $buttons.Children.Add($addButton) | Out-Null
    $buttons.Children.Add($cancelButton) | Out-Null
    $panel.Children.Add($buttons) | Out-Null

    $content = New-Object Windows.Controls.StackPanel
    $description = New-Object Windows.Controls.TextBlock
    $description.Text = 'Choose an installed app. HaySpace opens it through the Windows app catalog, without accessing its protected installation folder.'
    $description.TextWrapping = 'Wrap'
    $description.Margin = '0,0,0,8'
    $content.Children.Add($description) | Out-Null
    $appList = New-Object Windows.Controls.ListBox
    $appList.DisplayMemberPath = 'Name'
    $appList.ItemsSource = $installedApps
    $appList.MinHeight = 250
    $content.Children.Add($appList) | Out-Null
    $appIdLabel = New-Object Windows.Controls.TextBlock
    $appIdLabel.Margin = '0,6,0,2'
    $appIdLabel.Foreground = [Windows.Media.Brushes]::DimGray
    $content.Children.Add($appIdLabel) | Out-Null
    $processNameLabel = New-Object Windows.Controls.TextBlock
    $processNameLabel.Text = 'Window process name (used to match saved placements)'
    $processNameLabel.Margin = '0,8,0,2'
    $content.Children.Add($processNameLabel) | Out-Null
    $processNameControl = New-Object Windows.Controls.ComboBox
    $processNameControl.IsEditable = $true
    $processNameControl.ItemsSource = $processNames
    $content.Children.Add($processNameControl) | Out-Null
    $panel.Children.Add($content) | Out-Null

    $appList.Add_SelectionChanged({
        $selectedApp = $appList.SelectedItem
        $appIdLabel.Text = if ($selectedApp) { [string]$selectedApp.AppID } else { '' }
        if ($selectedApp) {
            $packageFamily = ([string]$selectedApp.AppID -split '!', 2)[0]
            $familySeparator = $packageFamily.LastIndexOf('_')
            $packagePattern = $null
            if ($familySeparator -gt 0) {
                $packageName = $packageFamily.Substring(0, $familySeparator)
                $publisherId = $packageFamily.Substring($familySeparator + 1)
                $packagePattern = '^' + [regex]::Escape($packageName) + '_.*__' + [regex]::Escape($publisherId) + '$'
            }
            $matchedWindow = @(
                @($Profile.Applications) + @($Profile.Windows) |
                    Where-Object {
                        $processPath = if ($_.PSObject.Properties['ProcessPath']) { [string]$_.ProcessPath } else { '' }
                        $packageFolder = if ($processPath) { [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($processPath)) } else { '' }
                        $packagePattern -and $packageFolder -match $packagePattern
                    } |
                    Select-Object -First 1
            )
            if ($matchedWindow.Count) {
                $processNameControl.Text = [string]$matchedWindow[0].ProcessName
            }
            elseif ($processNames.Count -eq 1) {
                $processNameControl.Text = [string]$processNames[0]
            }
            else {
                $processNameControl.Text = ''
            }
        }
        $addButton.IsEnabled = [bool]$selectedApp
    }.GetNewClosure())
    $addButton.Add_Click({
        $app = $appList.SelectedItem
        $processName = $processNameControl.Text.Trim()
        if (-not $app) { return }
        if (-not $processName) {
            [System.Windows.MessageBox]::Show('Enter or select the process name used by this app window.', 'Window process name required', 'OK', 'Warning') | Out-Null
            return
        }
        $dialog.Tag = [pscustomobject]@{
            Name = [string]$app.Name
            AppUserModelId = [string]$app.AppID
            ProcessName = $processName
        }
        $dialog.DialogResult = $true
    }.GetNewClosure())
    $dialog.Content = $panel
    if ($dialog.ShowDialog()) { return $dialog.Tag }
    return $null
}

function Invoke-AutoProfileStartup {
    try {
        $displays = @(Get-HaySpaceDisplays)
        if (-not $displays.Count) { throw 'No connected displays are available for automatic profile selection.' }
        $profiles = @(Get-HaySpaceProfiles)
        if (-not $profiles.Count) {
            Set-Status 'No saved profiles are available for automatic loading.'
            return
        }
        $configurationKey = Get-HaySpaceDisplayConfigurationKey -Displays $displays
        $configurationSummary = (@($displays | Sort-Object DisplayName | ForEach-Object {
            '{0}: {1}x{2} at ({3}, {4}){5}' -f $_.DisplayName, $_.Width, $_.Height, $_.X, $_.Y, $(if ($_.Primary) { ' [primary]' } else { '' })
        }) -join "`n")
        $settings = Get-HaySpaceSettings
        $assignedName = if ($settings.DisplayProfileAssignments.ContainsKey($configurationKey)) { [string]$settings.DisplayProfileAssignments[$configurationKey] } else { '' }
        $profile = $null
        if ($assignedName) {
            $profile = $profiles | Where-Object ProfileName -eq $assignedName | Select-Object -First 1
            if (-not $profile) {
                $settings.DisplayProfileAssignments.Remove($configurationKey)
                Save-HaySpaceSettings $settings
                Write-HaySpaceLog -Level Warning -Message "Remembered profile '$assignedName' for this display layout no longer exists."
            }
        }
        if (-not $profile) {
            $exactMatches = @()
            foreach ($candidate in $profiles) {
                if (-not $candidate.PSObject.Properties['Displays'] -or -not $candidate.Displays) { continue }
                try {
                    if ((Get-HaySpaceDisplayConfigurationKey -Displays @($candidate.Displays)) -eq $configurationKey) {
                        $exactMatches += $candidate
                    }
                }
                catch {
                    Write-HaySpaceLog -Level Warning -Message "Could not compare saved displays for '$($candidate.ProfileName)': $($_.Exception.Message)"
                }
            }
            if ($exactMatches.Count -eq 1) {
                $profile = $exactMatches[0]
            }
            else {
                $profile = Show-StartupProfileChooser -Profiles $profiles -DisplaySummary $configurationSummary
            }
        }
        if (-not $profile) {
            Set-Status 'Automatic profile loading was canceled.'
            return
        }
        Set-HaySpaceDisplayProfileAssignment -Displays $displays -ProfileName ([string]$profile.ProfileName) | Out-Null
        $result = Restore-HaySpaceWorkspace -Profile $profile -LaunchApplications
        Set-Status "Loaded '$($profile.ProfileName)' for this display configuration; positioned $($result.PositionedWindows) window(s)."
    }
    catch {
        Write-HaySpaceLog -Level Error -Message "Automatic profile loading failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Automatic profile loading failed', 'OK', 'Error') | Out-Null
    }
}

function Get-HaySpaceHotkeyVirtualKey {
    param([string]$Hotkey)
    if ($Hotkey -notmatch '^Ctrl\+Alt\+([A-Z]|[0-9]|F(?:[1-9]|1[0-2]))$') { return 0 }
    $keyName = $Matches[1]
    if ($keyName -match '^[0-9]$') { $keyName = 'D' + $keyName }
    try {
        $key = [Windows.Input.Key][Enum]::Parse([Windows.Input.Key], $keyName, $true)
        return [Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
    }
    catch {
        return 0
    }
}

function Sync-ProfileHotkeys {
    if (-not $script:HotkeySource) { return }
    foreach ($id in @($script:HotkeyIds.Keys)) {
        [HaySpace.NativeWindow]::UnregisterHotKey($script:HotkeySource.Handle, [int]$id) | Out-Null
    }
    $script:HotkeyIds = @{}
    $warnings = @()
    $id = 4100
    foreach ($profile in @(Get-HaySpaceProfiles)) {
        if ([string]::IsNullOrWhiteSpace([string]$profile.Hotkey)) { continue }
        $virtualKey = Get-HaySpaceHotkeyVirtualKey -Hotkey ([string]$profile.Hotkey)
        if (-not $virtualKey) {
            $warnings += "Invalid hotkey for '$($profile.ProfileName)': $($profile.Hotkey)"
            continue
        }
        if ([HaySpace.NativeWindow]::RegisterHotKey($script:HotkeySource.Handle, $id, 0x0001 -bor 0x0002, $virtualKey)) {
            $script:HotkeyIds[$id] = [string]$profile.ProfileName
            $id++
        }
        else {
            $warnings += "Could not register $($profile.Hotkey) for '$($profile.ProfileName)'; it may already be in use."
        }
    }
    foreach ($warning in $warnings) {
        Write-HaySpaceLog -Level Warning -Message $warning
    }
    if ($warnings.Count -gt 0 -and $window.IsVisible) {
        Set-Status "$($warnings.Count) profile hotkey(s) could not be registered. See the log."
    }
}

function Show-MigrationAssistant {
    param([Parameter(Mandatory)]$Profile)
    if (-not $Profile.PSObject.Properties['Applications']) { $Profile | Add-Member -NotePropertyName Applications -NotePropertyValue @() }
    if (-not $Profile.PSObject.Properties['ExplorerFolders']) { $Profile | Add-Member -NotePropertyName ExplorerFolders -NotePropertyValue @() }
    if (-not $Profile.PSObject.Properties['RdpFiles']) { $Profile | Add-Member -NotePropertyName RdpFiles -NotePropertyValue @() }
    $currentDisplays = @(Get-HaySpaceDisplays)
    if ($currentDisplays.Count -eq 0) { throw 'No connected displays are available.' }
    $dialog = New-Object Windows.Window
    $dialog.Title = "Migration assistant - $($Profile.ProfileName)"
    $dialog.Width = 680
    $dialog.Height = 650
    $dialog.MinWidth = 540
    $dialog.MinHeight = 450
    $dialog.Owner = $window
    $dialog.WindowStartupLocation = 'CenterOwner'
    $scroll = New-Object Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $content = New-Object Windows.Controls.StackPanel
    $content.Margin = '18'
    $scroll.Content = $content
    $dialog.Content = $scroll
    $intro = New-Object Windows.Controls.TextBlock
    $intro.Text = 'Map saved displays to this computer and update application paths that are missing.'
    $intro.TextWrapping = 'Wrap'
    $intro.Margin = '0,0,0,12'
    $content.Children.Add($intro) | Out-Null
    $mappingRows = @()
    $expectedDisplays = @(@($Profile.Windows | ForEach-Object DisplayName) + @($Profile.Displays | ForEach-Object DisplayName) | Where-Object { $_ } | Select-Object -Unique)
    $settings = Get-HaySpaceSettings
    foreach ($expected in $expectedDisplays) {
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = '0,3'
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = [string]$expected
        $label.Width = 200
        $label.VerticalAlignment = 'Center'
        $combo = New-Object Windows.Controls.ComboBox
        $combo.ItemsSource = $currentDisplays
        $combo.DisplayMemberPath = 'DisplayName'
        $existingDevice = $null
        if ($settings.DisplayMappings -and $settings.DisplayMappings.ContainsKey([string]$expected)) {
            $existingDevice = [string]$settings.DisplayMappings[[string]$expected]
        }
        else {
            $existing = $currentDisplays | Where-Object { $_.DisplayName -eq $expected } | Select-Object -First 1
            if ($existing) { $existingDevice = $existing.DeviceName }
        }
        $combo.SelectedItem = $currentDisplays | Where-Object DeviceName -eq $existingDevice | Select-Object -First 1
        $identify = New-Object Windows.Controls.Button
        $identify.Content = 'Identify'
        $identify.Width = 76
        $identify.Margin = '4,0,0,0'
        $identify.Tag = $combo
        [Windows.Controls.DockPanel]::SetDock($identify, [Windows.Controls.Dock]::Right)
        $identify.Add_Click({
            param($sender, $eventArgs)
            $selectedDisplay = $sender.Tag.SelectedItem
            if (-not $selectedDisplay) {
                [System.Windows.MessageBox]::Show('Select a connected display to identify.', 'Migration assistant') | Out-Null
                return
            }
            try {
                Show-HaySpaceDisplayIdentification -Display $selectedDisplay
            }
            catch {
                [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to identify display', 'OK', 'Error') | Out-Null
            }
        })
        [Windows.Controls.DockPanel]::SetDock($label, [Windows.Controls.Dock]::Left)
        $row.Children.Add($label) | Out-Null
        $row.Children.Add($identify) | Out-Null
        $row.Children.Add($combo) | Out-Null
        $content.Children.Add($row) | Out-Null
        $mappingRows += [pscustomobject]@{ Name = [string]$expected; Control = $combo }
    }

    $appsHeader = New-Object Windows.Controls.TextBlock
    $appsHeader.Text = 'Unavailable applications'
    $appsHeader.FontWeight = 'SemiBold'
    $appsHeader.Margin = '0,16,0,6'
    $content.Children.Add($appsHeader) | Out-Null
    $pathRows = @()
    foreach ($application in @($Profile.Applications)) {
        if ($application.PSObject.Properties['AppUserModelId'] -and $application.AppUserModelId) { continue }
        if ($application.ProcessPath -and (Test-Path -LiteralPath $application.ProcessPath)) { continue }
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = '0,3'
        $choose = New-Object Windows.Controls.Button
        $choose.Content = 'Browse'
        $choose.Width = 72
        [Windows.Controls.DockPanel]::SetDock($choose, [Windows.Controls.Dock]::Right)
        $row.Children.Add($choose) | Out-Null
        $pathBox = New-Object Windows.Controls.TextBox
        $pathBox.Text = [string]$application.ProcessPath
        $pathBox.Margin = '0,0,6,0'
        $pathBox.ToolTip = [string]$application.ProcessName
        $choose.Tag = $pathBox
        $row.Children.Add($pathBox) | Out-Null
        $choose.Add_Click({
            param($sender, $eventArgs)
            $picker = New-Object Microsoft.Win32.OpenFileDialog
            $picker.Filter = 'Applications (*.exe)|*.exe'
            if ($picker.ShowDialog()) {
                $sender.Tag.Text = $picker.FileName
            }
        })

        $content.Children.Add($row) | Out-Null
        $pathRows += [pscustomobject]@{ Application = $application; Control = $pathBox }
    }
    $folderHeader = New-Object Windows.Controls.TextBlock
    $folderHeader.Text = 'Explorer folders'
    $folderHeader.FontWeight = 'SemiBold'
    $folderHeader.Margin = '0,16,0,6'
    $content.Children.Add($folderHeader) | Out-Null
    $folderRows = @()
    foreach ($folder in @($Profile.ExplorerFolders)) {
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = '0,3'
        $browse = New-Object Windows.Controls.Button
        $browse.Content = 'Browse'
        $browse.Width = 72
        [Windows.Controls.DockPanel]::SetDock($browse, [Windows.Controls.Dock]::Right)
        $row.Children.Add($browse) | Out-Null
        $folderBox = New-Object Windows.Controls.TextBox
        $folderBox.Text = [string]$folder.Path
        $browse.Tag = $folderBox
        $row.Children.Add($folderBox) | Out-Null
        $browse.Add_Click({
            param($sender, $eventArgs)
            $picker = New-Object System.Windows.Forms.FolderBrowserDialog
            if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $sender.Tag.Text = $picker.SelectedPath
            }
        })
        $content.Children.Add($row) | Out-Null
        $folderRows += [pscustomobject]@{ Folder = $folder; Control = $folderBox }
    }
    if ($folderRows.Count -eq 0) {
        $none = New-Object Windows.Controls.TextBlock
        $none.Text = 'No captured Explorer folders.'
        $none.Foreground = [Windows.Media.Brushes]::DimGray
        $content.Children.Add($none) | Out-Null
    }
    $rdpHeader = New-Object Windows.Controls.TextBlock
    $rdpHeader.Text = 'Remote Desktop files'
    $rdpHeader.FontWeight = 'SemiBold'
    $rdpHeader.Margin = '0,16,0,6'
    $content.Children.Add($rdpHeader) | Out-Null
    $rdpRows = @()
    foreach ($rdpFile in @($Profile.RdpFiles)) {
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = '0,3'
        $browse = New-Object Windows.Controls.Button
        $browse.Content = 'Browse'
        $browse.Width = 72
        [Windows.Controls.DockPanel]::SetDock($browse, [Windows.Controls.Dock]::Right)
        $row.Children.Add($browse) | Out-Null
        $rdpPathBox = New-Object Windows.Controls.TextBox
        $rdpPathBox.Text = [string]$rdpFile
        $browse.Tag = $rdpPathBox
        $row.Children.Add($rdpPathBox) | Out-Null
        $browse.Add_Click({
            param($sender, $eventArgs)
            $picker = New-Object Microsoft.Win32.OpenFileDialog
            $picker.Filter = 'Remote Desktop files (*.rdp)|*.rdp'
            if ($picker.ShowDialog()) { $sender.Tag.Text = $picker.FileName }
        })
        $content.Children.Add($row) | Out-Null
        $rdpRows += $rdpPathBox
    }
    $addRdpButton = New-Object Windows.Controls.Button
    $addRdpButton.Content = 'Add RDP file'
    $addRdpButton.HorizontalAlignment = 'Left'
    $content.Children.Add($addRdpButton) | Out-Null
    $addRdpButton.Add_Click({
        $picker = New-Object Microsoft.Win32.OpenFileDialog
        $picker.Filter = 'Remote Desktop files (*.rdp)|*.rdp'
        $picker.Multiselect = $true
        if ($picker.ShowDialog()) {
            foreach ($path in $picker.FileNames) {
                $Profile.RdpFiles = @($Profile.RdpFiles) + $path
            }
            $dialog.DialogResult = $false
            $dialog.Tag = 'Refresh'
        }
    })
    if ($pathRows.Count -eq 0) {
        $none = New-Object Windows.Controls.TextBlock
        $none.Text = 'All configured application paths are available.'
        $none.Foreground = [Windows.Media.Brushes]::DimGray
        $content.Children.Add($none) | Out-Null
    }
    $buttons = New-Object Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = '0,16,0,0'
    $save = New-Object Windows.Controls.Button
    $save.Content = 'Save migration settings'
    $cancel = New-Object Windows.Controls.Button
    $cancel.Content = 'Cancel'
    $buttons.Children.Add($save) | Out-Null
    $buttons.Children.Add($cancel) | Out-Null
    $content.Children.Add($buttons) | Out-Null
    $cancel.Add_Click({ $dialog.DialogResult = $false })
    $save.Add_Click({
        try {
            foreach ($mapping in $mappingRows) {
                if (-not $mapping.Control.SelectedItem) { throw "Choose a connected display for '$($mapping.Name)'." }
                $settings.DisplayMappings[$mapping.Name] = [string]$mapping.Control.SelectedItem.DeviceName
            }
            foreach ($path in $pathRows) {
                if (-not $path.Control.Text) { continue }
                if (-not (Test-Path -LiteralPath $path.Control.Text -PathType Leaf)) {
                    throw "Application file not found: $($path.Control.Text)"
                }
                $path.Application.ProcessPath = $path.Control.Text
                $path.Application.ProcessName = [IO.Path]::GetFileNameWithoutExtension($path.Control.Text)
            }
            foreach ($folderRow in $folderRows) {
                if (-not (Test-Path -LiteralPath $folderRow.Control.Text -PathType Container)) {
                    throw "Explorer folder not found: $($folderRow.Control.Text)"
                }
                $folderRow.Folder.Path = $folderRow.Control.Text
            }
            $Profile.RdpFiles = @($rdpRows | ForEach-Object Text)
            if ($Profile.RdpFiles | Where-Object { $_ -and -not (Test-Path -LiteralPath $_ -PathType Leaf) }) {
                throw 'One or more RDP files do not exist. Update or remove those paths.'
            }
            Save-HaySpaceSettings $settings
            Save-HaySpaceProfile -Profile $Profile | Out-Null
            $dialog.DialogResult = $true
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to save migration settings', 'OK', 'Error') | Out-Null
        }
    })
    $result = [bool]$dialog.ShowDialog()
    if ($dialog.Tag -eq 'Refresh') {
        return (Show-MigrationAssistant -Profile $Profile)
    }
    return $result
}

function Show-CaptureOptions {
    $dialog = New-Object Windows.Window
    $dialog.Title = 'Capture workspace'
    $dialog.Width = 430
    $dialog.Height = 300
    $dialog.Owner = $window
    $dialog.WindowStartupLocation = 'CenterOwner'
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = '18'
    $dialog.Content = $panel
    $browserCheck = New-Object Windows.Controls.CheckBox
    $browserCheck.Content = 'Exclude browser windows'
    $browserCheck.Margin = '0,5'
    $explorerCheck = New-Object Windows.Controls.CheckBox
    $explorerCheck.Content = 'Exclude Explorer windows'
    $explorerCheck.Margin = '0,5'
    $panel.Children.Add($browserCheck) | Out-Null
    $panel.Children.Add($explorerCheck) | Out-Null
    $processLabel = New-Object Windows.Controls.TextBlock
    $processLabel.Text = 'Also exclude process names (comma separated)'
    $processLabel.Margin = '0,12,0,4'
    $panel.Children.Add($processLabel) | Out-Null
    $processBox = New-Object Windows.Controls.TextBox
    $panel.Children.Add($processBox) | Out-Null
    $buttons = New-Object Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = '0,18,0,0'
    $captureButton = New-Object Windows.Controls.Button
    $captureButton.Content = 'Capture'
    $cancelButton = New-Object Windows.Controls.Button
    $cancelButton.Content = 'Cancel'
    $buttons.Children.Add($captureButton) | Out-Null
    $buttons.Children.Add($cancelButton) | Out-Null
    $panel.Children.Add($buttons) | Out-Null
    $captureButton.Add_Click({ $dialog.DialogResult = $true })
    $cancelButton.Add_Click({ $dialog.DialogResult = $false })
    if (-not $dialog.ShowDialog()) { return $null }
    return @{
        ExcludeBrowsers = [bool]$browserCheck.IsChecked
        ExcludeExplorer = [bool]$explorerCheck.IsChecked
        ExcludedProcessNames = @($processBox.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
}

function New-VisualDesignerCard {
    param($WindowTarget, [Windows.Controls.Canvas]$Canvas, [double]$Left, [double]$Top, [double]$Width, [double]$Height)
    $card = New-Object Windows.Controls.Border
    $card.Tag = $WindowTarget
    $card.Width = $Width
    $card.Height = $Height
    $card.Background = [Windows.Media.Brushes]::White
    $card.BorderBrush = [Windows.Media.Brushes]::DodgerBlue
    $card.BorderThickness = '1'
    $card.CornerRadius = '4'
    $card.ClipToBounds = $true
    $content = New-Object Windows.Controls.Grid
    $content.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
    $content.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
    $content.RowDefinitions[0].Height = [Windows.GridLength]::new(26)
    $content.RowDefinitions[1].Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
    $header = New-Object Windows.Controls.Grid
    $header.Background = [Windows.Media.Brushes]::LightSteelBlue
    $headerThumb = New-Object Windows.Controls.Primitives.Thumb
    $headerThumb.Background = [Windows.Media.Brushes]::Transparent
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = [string]$WindowTarget.ProcessName
    $label.Margin = '6,3,4,2'
    $label.TextTrimming = 'CharacterEllipsis'
    $label.IsHitTestVisible = $false
    $header.Children.Add($headerThumb) | Out-Null
    $header.Children.Add($label) | Out-Null
    $content.Children.Add($header) | Out-Null
    [Windows.Controls.Grid]::SetRow($header, 0)
    $detail = New-Object Windows.Controls.TextBlock
    $detail.Text = [string]$WindowTarget.Title
    $detail.Margin = '6,4,6,6'
    $detail.TextWrapping = 'Wrap'
    $detail.FontSize = 10
    $content.Children.Add($detail) | Out-Null
    [Windows.Controls.Grid]::SetRow($detail, 1)
    $card.Child = $content
    [Windows.Controls.Canvas]::SetLeft($card, $Left)
    [Windows.Controls.Canvas]::SetTop($card, $Top)
    $Canvas.Children.Add($card) | Out-Null
    $headerThumb.Add_DragDelta({
        $left = [Windows.Controls.Canvas]::GetLeft($card) + $_.HorizontalChange
        $top = [Windows.Controls.Canvas]::GetTop($card) + $_.VerticalChange
        $left = [math]::Round($left / 10) * 10
        $top = [math]::Round($top / 10) * 10
        [Windows.Controls.Canvas]::SetLeft($card, [math]::Max(0, [math]::Min($left, $Canvas.ActualWidth - $card.Width)))
        [Windows.Controls.Canvas]::SetTop($card, [math]::Max(0, [math]::Min($top, $Canvas.ActualHeight - $card.Height)))
    })
    $resize = New-Object Windows.Controls.Primitives.Thumb
    $resize.Width = 14
    $resize.Height = 14
    $resize.Background = [Windows.Media.Brushes]::DodgerBlue
    $resize.HorizontalAlignment = 'Right'
    $resize.VerticalAlignment = 'Bottom'
    $resize.Cursor = [Windows.Input.Cursors]::SizeNWSE
    $content.Children.Add($resize) | Out-Null
    $resize.Add_DragDelta({
        $card.Width = [math]::Max(95, [math]::Min($card.Width + $_.HorizontalChange, $Canvas.ActualWidth - [Windows.Controls.Canvas]::GetLeft($card)))
        $card.Height = [math]::Max(58, [math]::Min($card.Height + $_.VerticalChange, $Canvas.ActualHeight - [Windows.Controls.Canvas]::GetTop($card)))
    })
    return $card
}

function Show-VisualDesigner {
    param([Parameter(Mandatory)]$Profile)
    $displays = @(Get-HaySpaceDisplays)
    if ($displays.Count -eq 0) { throw 'No connected displays are available for the designer.' }
    if (@($Profile.Windows).Count -eq 0) {
        [System.Windows.MessageBox]::Show('Capture a workspace first so the designer has windows to arrange.', 'Visual designer') | Out-Null
        return $false
    }

    $designer = New-Object Windows.Window
    $designer.Title = "Visual layout - $($Profile.ProfileName)"
    $designer.Width = 1040
    $designer.Height = 680
    $designer.MinWidth = 850
    $designer.MinHeight = 560
    $designer.Owner = $window
    $designer.WindowStartupLocation = 'CenterOwner'
    $rootPanel = New-Object Windows.Controls.DockPanel
    $rootPanel.Margin = '16'
    $designer.Content = $rootPanel
    $buttons = New-Object Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = '0,12,0,0'
    [Windows.Controls.DockPanel]::SetDock($buttons, [Windows.Controls.Dock]::Bottom)
    $saveButton = New-Object Windows.Controls.Button
    $saveButton.Content = 'Save layout'
    $cancelButton = New-Object Windows.Controls.Button
    $cancelButton.Content = 'Cancel'
    $buttons.Children.Add($saveButton) | Out-Null
    $buttons.Children.Add($cancelButton) | Out-Null
    $rootPanel.Children.Add($buttons) | Out-Null
    $layoutGrid = New-Object Windows.Controls.Grid
    $layoutGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) | Out-Null
    $layoutGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) | Out-Null
    $layoutGrid.ColumnDefinitions[0].Width = [Windows.GridLength]::new(3, [Windows.GridUnitType]::Star)
    $layoutGrid.ColumnDefinitions[1].Width = [Windows.GridLength]::new(2, [Windows.GridUnitType]::Star)
    $rootPanel.Children.Add($layoutGrid) | Out-Null

    $canvasScroll = New-Object Windows.Controls.ScrollViewer
    $canvasScroll.HorizontalScrollBarVisibility = 'Auto'
    $canvasScroll.VerticalScrollBarVisibility = 'Auto'
    $canvasScroll.Margin = '0,0,12,0'
    $canvas = New-Object Windows.Controls.Canvas
    $canvas.Width = 720
    $canvas.Height = 470
    $canvas.Background = [Windows.Media.Brushes]::WhiteSmoke
    $canvasScroll.Content = $canvas
    $layoutGrid.Children.Add($canvasScroll) | Out-Null
    $windowGrid = New-Object Windows.Controls.DataGrid
    $windowGrid.AutoGenerateColumns = $false
    $windowGrid.CanUserAddRows = $false
    $windowGrid.SelectionMode = 'Single'
    $windowGrid.SelectionUnit = 'FullRow'
    $windowGrid.Margin = '0,0,0,0'
    [Windows.Controls.Grid]::SetColumn($windowGrid, 1)
    $layoutGrid.Children.Add($windowGrid) | Out-Null
    foreach ($column in @(
        @{ Header = 'Application'; Path = 'ProcessName'; Width = '110'; ReadOnly = $true },
        @{ Header = 'X'; Path = 'X'; Width = '55'; ReadOnly = $false },
        @{ Header = 'Y'; Path = 'Y'; Width = '55'; ReadOnly = $false },
        @{ Header = 'Width'; Path = 'Width'; Width = '60'; ReadOnly = $false },
        @{ Header = 'Height'; Path = 'Height'; Width = '60'; ReadOnly = $false }
    )) {
        $gridColumn = New-Object Windows.Controls.DataGridTextColumn
        $gridColumn.Header = $column.Header
        $gridColumn.IsReadOnly = $column.ReadOnly
        $binding = New-Object Windows.Data.Binding
        $binding.Path = $column.Path
        $binding.Mode = if ($column.ReadOnly) { [Windows.Data.BindingMode]::OneWay } else { [Windows.Data.BindingMode]::TwoWay }
        $gridColumn.Binding = $binding
        $gridColumn.Width = [Windows.Controls.DataGridLengthConverter]::new().ConvertFromString([string]$column.Width)
        $windowGrid.Columns.Add($gridColumn) | Out-Null
    }
    $displayColumn = New-Object Windows.Controls.DataGridComboBoxColumn
    $displayColumn.Header = 'Display'
    $displayColumn.ItemsSource = @($displays | ForEach-Object DisplayName)
    $displayBinding = New-Object Windows.Data.Binding
    $displayBinding.Path = 'DisplayName'
    $displayBinding.Mode = [Windows.Data.BindingMode]::TwoWay
    $displayColumn.SelectedItemBinding = $displayBinding
    $displayColumn.Width = [Windows.Controls.DataGridLengthConverter]::new().ConvertFromString('110')
    $windowGrid.Columns.Add($displayColumn) | Out-Null
    $stateColumn = New-Object Windows.Controls.DataGridComboBoxColumn
    $stateColumn.Header = 'State'
    $stateColumn.ItemsSource = @('Normal', 'Maximized', 'Minimized')
    $stateBinding = New-Object Windows.Data.Binding
    $stateBinding.Path = 'State'
    $stateBinding.Mode = [Windows.Data.BindingMode]::TwoWay
    $stateColumn.SelectedItemBinding = $stateBinding
    $stateColumn.Width = [Windows.Controls.DataGridLengthConverter]::new().ConvertFromString('105')
    $windowGrid.Columns.Add($stateColumn) | Out-Null
    $windows = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($target in @($Profile.Windows)) {
        $windows.Add($target)
    }
    $windowGrid.ItemsSource = $windows

    $minimumX = ($displays | Measure-Object -Property X -Minimum).Minimum
    $minimumY = ($displays | Measure-Object -Property Y -Minimum).Minimum
    $maximumX = ($displays | ForEach-Object { $_.X + $_.Width } | Measure-Object -Maximum).Maximum
    $maximumY = ($displays | ForEach-Object { $_.Y + $_.Height } | Measure-Object -Maximum).Maximum
    $scale = [math]::Min(660.0 / [math]::Max(1, ($maximumX - $minimumX)), 390.0 / [math]::Max(1, ($maximumY - $minimumY)))
    $displayCards = @()
    foreach ($display in $displays) {
        $left = 24 + (($display.X - $minimumX) * $scale)
        $top = 24 + (($display.Y - $minimumY) * $scale)
        $monitor = New-Object Windows.Controls.Border
        $monitor.Width = [math]::Max(80, $display.Width * $scale)
        $monitor.Height = [math]::Max(70, $display.Height * $scale)
        $monitor.BorderBrush = [Windows.Media.Brushes]::SlateGray
        $monitor.BorderThickness = '2'
        $monitor.Background = [Windows.Media.Brushes]::LightGray
        $monitor.Tag = $display
        $monitorLabel = New-Object Windows.Controls.TextBlock
        $monitorLabel.Text = $display.DisplayName
        $monitorLabel.HorizontalAlignment = 'Center'
        $monitorLabel.VerticalAlignment = 'Top'
        $monitorLabel.Margin = '4'
        $monitor.Child = $monitorLabel
        [Windows.Controls.Canvas]::SetLeft($monitor, $left)
        [Windows.Controls.Canvas]::SetTop($monitor, $top)
        $canvas.Children.Add($monitor) | Out-Null
        $displayCards += $monitor
    }
    $cards = @()
    foreach ($target in $windows) {
        $display = $displays | Where-Object { $_.DisplayName -eq $target.DisplayName } | Select-Object -First 1
        if (-not $display) { $display = $displays | Where-Object { $_.DeviceName -eq $target.DeviceName } | Select-Object -First 1 }
        if (-not $display) { $display = $displays | Where-Object Primary | Select-Object -First 1 }
        if (-not $display) { $display = $displays[0] }
        $left = 24 + (($display.X - $minimumX) * $scale) + ([double]$target.RelativeX * $display.WorkWidth * $scale)
        $top = 24 + (($display.Y - $minimumY) * $scale) + ([double]$target.RelativeY * $display.WorkHeight * $scale)
        $card = New-VisualDesignerCard -WindowTarget $target -Canvas $canvas -Left $left -Top $top -Width ([math]::Max(95, [double]$target.RelativeWidth * $display.WorkWidth * $scale)) -Height ([math]::Max(58, [double]$target.RelativeHeight * $display.WorkHeight * $scale))
        $cards += $card
    }
    $saveButton.Add_Click({
        $windowGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
        $windowGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        foreach ($card in $cards) {
            $target = $card.Tag
            $centerX = [Windows.Controls.Canvas]::GetLeft($card) + ($card.Width / 2)
            $centerY = [Windows.Controls.Canvas]::GetTop($card) + ($card.Height / 2)
            $monitor = $displayCards | Where-Object {
                $left = [Windows.Controls.Canvas]::GetLeft($_)
                $top = [Windows.Controls.Canvas]::GetTop($_)
                $centerX -ge $left -and $centerX -le ($left + $_.Width) -and $centerY -ge $top -and $centerY -le ($top + $_.Height)
            } | Select-Object -First 1
            if ($monitor) {
                $display = $monitor.Tag
                $target.DisplayName = $display.DisplayName
                $target.DeviceName = $display.DeviceName
                $target.RelativeX = [math]::Max(0, ([Windows.Controls.Canvas]::GetLeft($card) - (24 + (($display.X - $minimumX) * $scale))) / ($display.WorkWidth * $scale))
                $target.RelativeY = [math]::Max(0, ([Windows.Controls.Canvas]::GetTop($card) - (24 + (($display.Y - $minimumY) * $scale))) / ($display.WorkHeight * $scale))
                $target.RelativeWidth = $card.Width / ($display.WorkWidth * $scale)
                $target.RelativeHeight = $card.Height / ($display.WorkHeight * $scale)
                $target.X = [int]($display.WorkX + ($target.RelativeX * $display.WorkWidth))
                $target.Y = [int]($display.WorkY + ($target.RelativeY * $display.WorkHeight))
                $target.Width = [int]($target.RelativeWidth * $display.WorkWidth)
                $target.Height = [int]($target.RelativeHeight * $display.WorkHeight)
            }
        }
        $Profile.Windows = @($windows)
        try {
            Save-HaySpaceProfile -Profile $Profile | Out-Null
            $designer.DialogResult = $true
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to save layout', 'OK', 'Error') | Out-Null
        }
    })
    $cancelButton.Add_Click({ $designer.DialogResult = $false })
    return [bool]$designer.ShowDialog()
}

function Show-ProfileEditor {
    param($Profile)
    if ($null -eq $Profile) {
        $Profile = [pscustomobject]@{
            ProfileName = ''
            ProfileType = 'Full Workspace'
            BrowserMode = 'Ignore'
            Applications = @()
            Windows = @()
            Urls = @()
            ExplorerFolders = @()
            RdpFiles = @()
            Hotkey = ''
            Displays = @(Get-HaySpaceDisplays)
            LaunchDelaySeconds = 2
        }
    }
    foreach ($property in @(
        @{ Name = 'Applications'; Value = @() },
        @{ Name = 'Windows'; Value = @() },
        @{ Name = 'Urls'; Value = @() },
        @{ Name = 'RdpFiles'; Value = @() },
        @{ Name = 'Hotkey'; Value = '' },
        @{ Name = 'Displays'; Value = @(Get-HaySpaceDisplays) },
        @{ Name = 'LaunchDelaySeconds'; Value = 2 },
        @{ Name = 'BrowserMode'; Value = 'Ignore' },
        @{ Name = 'ProfileType'; Value = 'Full Workspace' }
    )) {
        if (-not $Profile.PSObject.Properties[$property.Name]) {
            $Profile | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
    }
    $isNew = [string]::IsNullOrWhiteSpace([string]$Profile.ProfileName)
    $originalName = [string]$Profile.ProfileName
    $dialog = New-Object Windows.Window
    $dialog.Title = if ($isNew) { 'New profile' } else { 'Edit profile' }
    $dialog.Width = 900
    $dialog.Height = 820
    $dialog.MinWidth = 760
    $dialog.MinHeight = 620
    $dialog.Owner = $window
    $dialog.WindowStartupLocation = 'CenterOwner'
    $scrollViewer = New-Object Windows.Controls.ScrollViewer
    $scrollViewer.VerticalScrollBarVisibility = 'Auto'
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = '20'
    $scrollViewer.Content = $panel
    $dialog.Content = $scrollViewer
    foreach ($label in @('Profile name', 'Profile type', 'Browser mode')) {
        $text = New-Object Windows.Controls.TextBlock
        $text.Text = $label
        $text.Margin = '0,8,0,4'
        $text.FontWeight = 'SemiBold'
        $panel.Children.Add($text) | Out-Null
        if ($label -eq 'Profile type') {
            $typeControl = New-Object Windows.Controls.ComboBox
            $typeControl.ItemsSource = @('Quick Layout', 'Workspace Layout', 'Full Workspace')
            $typeControl.SelectedItem = if ($Profile.ProfileType) { $Profile.ProfileType } else { 'Full Workspace' }
            $panel.Children.Add($typeControl) | Out-Null
        }
        elseif ($label -eq 'Browser mode') {
            $browserControl = New-Object Windows.Controls.ComboBox
            $browserControl.ItemsSource = @('Ignore', 'URL', 'Session', 'Hybrid')
            $browserControl.SelectedItem = if ($Profile.BrowserMode) { $Profile.BrowserMode } else { 'Hybrid' }
            $panel.Children.Add($browserControl) | Out-Null
        }
        else {
            $box = New-Object Windows.Controls.TextBox
            $box.Margin = '0,0,0,4'
            if ($label -eq 'Profile name') {
                $nameBox = $box
                $box.Text = [string]$Profile.ProfileName
            }
            $panel.Children.Add($box) | Out-Null
        }
    }

    $appsHeader = New-Object Windows.Controls.TextBlock
    $appsHeader.Text = 'Applications'
    $appsHeader.Margin = '0,12,0,4'
    $appsHeader.FontWeight = 'SemiBold'
    $panel.Children.Add($appsHeader) | Out-Null
    $appsGrid = New-Object Windows.Controls.DataGrid
    $appsGrid.Height = 210
    $appsGrid.AutoGenerateColumns = $false
    $appsGrid.CanUserAddRows = $false
    $appsGrid.IsReadOnly = $false
    $appsGrid.SelectionMode = 'Single'
    $appsGrid.SelectionUnit = 'FullRow'
    $appsGrid.Margin = '0,0,0,4'
    foreach ($column in @(
        @{ Header = 'Application'; Binding = 'ProcessName'; Width = '130' },
        @{ Header = 'Executable path'; Binding = 'ProcessPath'; Width = '*' },
        @{ Header = 'Installed app ID'; Binding = 'AppUserModelId'; Width = '180' },
        @{ Header = 'Arguments (optional)'; Binding = 'Arguments'; Width = '160' },
        @{ Header = 'Launch order'; Binding = 'LaunchOrder'; Width = '80' }
    )) {
        $gridColumn = New-Object Windows.Controls.DataGridTextColumn
        $gridColumn.Header = $column.Header
        $binding = New-Object Windows.Data.Binding
        $binding.Path = $column.Binding
        $gridColumn.Binding = $binding
        $gridColumn.Width = [Windows.Controls.DataGridLengthConverter]::new().ConvertFromString([string]$column.Width)
        $appsGrid.Columns.Add($gridColumn) | Out-Null
    }
    $launchColumn = New-Object Windows.Controls.DataGridCheckBoxColumn
    $launchColumn.Header = 'Launch'
    $launchBinding = New-Object Windows.Data.Binding
    $launchBinding.Path = 'Launch'
    $launchColumn.Binding = $launchBinding
    $launchColumn.Width = [Windows.Controls.DataGridLength]::new(65)
    $appsGrid.Columns.Add($launchColumn) | Out-Null
    $applications = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($application in @($Profile.Applications)) {
        if (-not $application.PSObject.Properties['Arguments']) { $application | Add-Member -NotePropertyName Arguments -NotePropertyValue '' }
        if (-not $application.PSObject.Properties['AppUserModelId']) { $application | Add-Member -NotePropertyName AppUserModelId -NotePropertyValue '' }
        if (-not $application.PSObject.Properties['Launch']) { $application | Add-Member -NotePropertyName Launch -NotePropertyValue $true }
        if (-not $application.PSObject.Properties['LaunchOrder']) { $application | Add-Member -NotePropertyName LaunchOrder -NotePropertyValue $applications.Count }
        $applications.Add($application)
    }
    $appsGrid.ItemsSource = $applications
    $panel.Children.Add($appsGrid) | Out-Null

    $appButtons = New-Object Windows.Controls.StackPanel
    $appButtons.Orientation = 'Horizontal'
    $addAppButton = New-Object Windows.Controls.Button
    $addAppButton.Content = 'Add application'
    $addInstalledAppButton = New-Object Windows.Controls.Button
    $addInstalledAppButton.Content = 'Add installed app'
    $removeAppButton = New-Object Windows.Controls.Button
    $removeAppButton.Content = 'Remove selected'
    $appButtons.Children.Add($addAppButton) | Out-Null
    $appButtons.Children.Add($addInstalledAppButton) | Out-Null
    $appButtons.Children.Add($removeAppButton) | Out-Null
    $panel.Children.Add($appButtons) | Out-Null
    $appHelp = New-Object Windows.Controls.TextBlock
    $appHelp.Text = 'New apps launch normally by default. Window placement only applies to windows captured in this profile. Removing an app also removes its saved window placements.'
    $appHelp.TextWrapping = 'Wrap'
    $appHelp.Foreground = [Windows.Media.Brushes]::DimGray
    $appHelp.Margin = '4,0,4,8'
    $panel.Children.Add($appHelp) | Out-Null

    $windowsHeader = New-Object Windows.Controls.TextBlock
    $windowsHeader.Text = 'Window placements'
    $windowsHeader.Margin = '0,12,0,4'
    $windowsHeader.FontWeight = 'SemiBold'
    $panel.Children.Add($windowsHeader) | Out-Null
    $windowGrid = New-Object Windows.Controls.DataGrid
    $windowGrid.Height = 180
    $windowGrid.AutoGenerateColumns = $false
    $windowGrid.CanUserAddRows = $false
    $windowGrid.SelectionMode = 'Single'
    $windowGrid.SelectionUnit = 'FullRow'
    $windowGrid.Margin = '0,0,0,4'
    foreach ($column in @(
        @{ Header = 'Application'; Path = 'ProcessName'; Width = '100'; ReadOnly = $true },
        @{ Header = 'X'; Path = 'X'; Width = '55'; ReadOnly = $false },
        @{ Header = 'Y'; Path = 'Y'; Width = '55'; ReadOnly = $false },
        @{ Header = 'Width'; Path = 'Width'; Width = '60'; ReadOnly = $false },
        @{ Header = 'Height'; Path = 'Height'; Width = '60'; ReadOnly = $false }
    )) {
        $columnControl = New-Object Windows.Controls.DataGridTextColumn
        $columnControl.Header = $column.Header
        $columnControl.IsReadOnly = $column.ReadOnly
        $binding = New-Object Windows.Data.Binding
        $binding.Path = $column.Path
        $binding.Mode = if ($column.ReadOnly) { [Windows.Data.BindingMode]::OneWay } else { [Windows.Data.BindingMode]::TwoWay }
        $columnControl.Binding = $binding
        $columnControl.Width = [Windows.Controls.DataGridLengthConverter]::new().ConvertFromString([string]$column.Width)
        $windowGrid.Columns.Add($columnControl) | Out-Null
    }
    $windowDisplayColumn = New-Object Windows.Controls.DataGridComboBoxColumn
    $windowDisplayColumn.Header = 'Display'
    $windowDisplayColumn.ItemsSource = @(Get-HaySpaceDisplays | ForEach-Object DisplayName)
    $windowDisplayBinding = New-Object Windows.Data.Binding
    $windowDisplayBinding.Path = 'DisplayName'
    $windowDisplayBinding.Mode = [Windows.Data.BindingMode]::TwoWay
    $windowDisplayColumn.SelectedItemBinding = $windowDisplayBinding
    $windowDisplayColumn.Width = [Windows.Controls.DataGridLengthConverter]::new().ConvertFromString('110')
    $windowGrid.Columns.Add($windowDisplayColumn) | Out-Null
    $windowStateColumn = New-Object Windows.Controls.DataGridComboBoxColumn
    $windowStateColumn.Header = 'State'
    $windowStateColumn.ItemsSource = @('Normal', 'Maximized', 'Minimized')
    $windowStateBinding = New-Object Windows.Data.Binding
    $windowStateBinding.Path = 'State'
    $windowStateBinding.Mode = [Windows.Data.BindingMode]::TwoWay
    $windowStateColumn.SelectedItemBinding = $windowStateBinding
    $windowStateColumn.Width = [Windows.Controls.DataGridLengthConverter]::new().ConvertFromString('100')
    $windowGrid.Columns.Add($windowStateColumn) | Out-Null
    $windowEntries = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($target in @($Profile.Windows)) {
        if (-not $target.PSObject.Properties['RelativeX']) { $target | Add-Member -NotePropertyName RelativeX -NotePropertyValue 0 }
        if (-not $target.PSObject.Properties['RelativeY']) { $target | Add-Member -NotePropertyName RelativeY -NotePropertyValue 0 }
        if (-not $target.PSObject.Properties['RelativeWidth']) { $target | Add-Member -NotePropertyName RelativeWidth -NotePropertyValue 0.6 }
        if (-not $target.PSObject.Properties['RelativeHeight']) { $target | Add-Member -NotePropertyName RelativeHeight -NotePropertyValue 0.6 }
        if (-not $target.PSObject.Properties['State']) { $target | Add-Member -NotePropertyName State -NotePropertyValue 'Normal' }
        if (-not $target.PSObject.Properties['DisplayName']) { $target | Add-Member -NotePropertyName DisplayName -NotePropertyValue '' }
        if (-not $target.PSObject.Properties['DeviceName']) { $target | Add-Member -NotePropertyName DeviceName -NotePropertyValue '' }
        $windowEntries.Add($target)
    }
    $windowGrid.ItemsSource = $windowEntries
    $panel.Children.Add($windowGrid) | Out-Null
    $designerButton = New-Object Windows.Controls.Button
    $designerButton.Content = 'Open visual designer'
    $designerButton.HorizontalAlignment = 'Left'
    $panel.Children.Add($designerButton) | Out-Null
    $designerButton.Add_Click({
        $Profile.Windows = @($windowEntries)
        try {
            $null = Show-VisualDesigner -Profile $Profile
            $windowEntries.Clear()
            foreach ($target in @($Profile.Windows)) { $windowEntries.Add($target) }
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to open designer', 'OK', 'Error') | Out-Null
        }
    })

    $urlsHeader = New-Object Windows.Controls.TextBlock
    $urlsHeader.Text = 'URLs (one per line; used only in URL or Hybrid mode)'
    $urlsHeader.Margin = '0,8,0,4'
    $urlsHeader.FontWeight = 'SemiBold'
    $panel.Children.Add($urlsHeader) | Out-Null
    $urlsBox = New-Object Windows.Controls.TextBox
    $urlsBox.AcceptsReturn = $true
    $urlsBox.Height = 75
    $urlsBox.VerticalScrollBarVisibility = 'Auto'
    $urlsBox.Text = (@($Profile.Urls) -join [Environment]::NewLine)
    $panel.Children.Add($urlsBox) | Out-Null

    $rdpHeader = New-Object Windows.Controls.TextBlock
    $rdpHeader.Text = 'Remote Desktop files'
    $rdpHeader.Margin = '0,8,0,4'
    $rdpHeader.FontWeight = 'SemiBold'
    $panel.Children.Add($rdpHeader) | Out-Null
    $rdpBox = New-Object Windows.Controls.TextBox
    $rdpBox.AcceptsReturn = $true
    $rdpBox.Height = 55
    $rdpBox.VerticalScrollBarVisibility = 'Auto'
    $rdpBox.Text = (@($Profile.RdpFiles) -join [Environment]::NewLine)
    $panel.Children.Add($rdpBox) | Out-Null
    $rdpBrowse = New-Object Windows.Controls.Button
    $rdpBrowse.Content = 'Add RDP file'
    $rdpBrowse.HorizontalAlignment = 'Left'
    $panel.Children.Add($rdpBrowse) | Out-Null
    $rdpBrowse.Add_Click({
        $picker = New-Object Microsoft.Win32.OpenFileDialog
        $picker.Filter = 'Remote Desktop files (*.rdp)|*.rdp'
        $picker.Multiselect = $true
        if ($picker.ShowDialog()) {
            $existing = @($rdpBox.Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $rdpBox.Text = (@($existing + $picker.FileNames | Select-Object -Unique) -join [Environment]::NewLine)
        }
    })
    $hotkeyHeader = New-Object Windows.Controls.TextBlock
    $hotkeyHeader.Text = 'Profile hotkey (Ctrl+Alt+key)'
    $hotkeyHeader.Margin = '0,8,0,4'
    $hotkeyHeader.FontWeight = 'SemiBold'
    $panel.Children.Add($hotkeyHeader) | Out-Null
    $hotkeyBox = New-Object Windows.Controls.TextBox
    $hotkeyBox.IsReadOnly = $true
    $hotkeyBox.Text = [string]$Profile.Hotkey
    $hotkeyBox.ToolTip = 'Press Ctrl+Alt+one key, for example Ctrl+Alt+1'
    $hotkeyBox.Add_PreviewKeyDown({
        $keyValue = $_.Key
        if ($keyValue -eq [Windows.Input.Key]::System) { $keyValue = $_.SystemKey }
        $modifiers = [Windows.Input.Keyboard]::Modifiers
        if (($modifiers -band [Windows.Input.ModifierKeys]::Control) -eq 0 -or ($modifiers -band [Windows.Input.ModifierKeys]::Alt) -eq 0) {
            $hotkeyBox.ToolTip = 'Press Ctrl+Alt+one key, for example Ctrl+Alt+1'
            $_.Handled = $true
            return
        }
        $keyName = $keyValue.ToString()
        if ($keyName -match '^D[0-9]$') { $keyName = $keyName.Substring(1) }
        if ($keyName -match '^[A-Z]$|^[0-9]$|^F([1-9]|1[0-2])$') {
            $hotkeyBox.Text = 'Ctrl+Alt+' + $keyName
        }
        $_.Handled = $true
    })
    $panel.Children.Add($hotkeyBox) | Out-Null

    $addAppButton.Add_Click({
        $picker = New-Object Microsoft.Win32.OpenFileDialog
        $picker.Filter = 'Applications (*.exe)|*.exe'
        $picker.Title = 'Select application'
        if ($picker.ShowDialog()) {
            $applications.Add([pscustomobject]@{
                ProcessName = [IO.Path]::GetFileNameWithoutExtension($picker.FileName)
                ProcessPath = $picker.FileName
                Arguments = ''
                Launch = $true
                LaunchOrder = $applications.Count
            })
        }
    })
    $addInstalledAppButton.Add_Click({
        try {
            $installedApp = Show-InstalledAppPicker -Profile $Profile -Owner $window
            if (-not $installedApp) { return }
            $existingApp = $applications | Where-Object ProcessName -eq $installedApp.ProcessName | Select-Object -First 1
            if ($existingApp) {
                $existingApp.ProcessPath = ''
                $existingApp.AppUserModelId = $installedApp.AppUserModelId
            }
            else {
                $applications.Add([pscustomobject]@{
                    ProcessName = $installedApp.ProcessName
                    ProcessPath = ''
                    AppUserModelId = $installedApp.AppUserModelId
                    Arguments = ''
                    Launch = $true
                    LaunchOrder = $applications.Count
                })
            }
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to add installed app', 'OK', 'Error') | Out-Null
        }
    }.GetNewClosure())
    $removeAppButton.Add_Click({
        if ($appsGrid.SelectedItem) {
            $removedApplication = $appsGrid.SelectedItem
            $applications.Remove($removedApplication)
            $remainingWindows = @($windowEntries | Where-Object {
                $_.ProcessName -ne $removedApplication.ProcessName -and
                (-not $removedApplication.ProcessPath -or $_.ProcessPath -ne $removedApplication.ProcessPath)
            })
            $windowEntries.Clear()
            foreach ($target in $remainingWindows) { $windowEntries.Add($target) }
            for ($index = 0; $index -lt $applications.Count; $index++) {
                $applications[$index].LaunchOrder = $index
            }
        }
    })

    $buttons = New-Object Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = '0,14,0,0'
    $save = New-Object Windows.Controls.Button
    $save.Content = 'Save'
    $save.Width = 100
    $save.Margin = '0,0,8,0'
    $cancel = New-Object Windows.Controls.Button
    $cancel.Content = 'Cancel'
    $cancel.Width = 100
    $buttons.Children.Add($save) | Out-Null
    $buttons.Children.Add($cancel) | Out-Null
    $panel.Children.Add($buttons) | Out-Null
    $cancel.Add_Click({ $dialog.DialogResult = $false })
    $save.Add_Click({
        if ([string]::IsNullOrWhiteSpace($nameBox.Text)) {
            [System.Windows.MessageBox]::Show('Enter a profile name.', 'HaySpace') | Out-Null
            return
        }
        $Profile.ProfileName = $nameBox.Text.Trim()
        $Profile.ProfileType = [string]$typeControl.SelectedItem
        $Profile.BrowserMode = [string]$browserControl.SelectedItem
        $Profile.Urls = @($urlsBox.Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $Profile.RdpFiles = @($rdpBox.Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $Profile.Hotkey = $hotkeyBox.Text
        $appsGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
        $appsGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        $windowGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
        $windowGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        $Profile.Applications = @($applications)
        $Profile.Windows = @($windowEntries)
        $connectedDisplays = @(Get-HaySpaceDisplays)
        foreach ($target in $Profile.Windows) {
            $targetDisplay = $connectedDisplays | Where-Object DisplayName -eq $target.DisplayName | Select-Object -First 1
            if (-not $targetDisplay) { continue }
            $target.RelativeX = [math]::Round(([double]$target.X - $targetDisplay.WorkX) / [math]::Max(1, $targetDisplay.WorkWidth), 5)
            $target.RelativeY = [math]::Round(([double]$target.Y - $targetDisplay.WorkY) / [math]::Max(1, $targetDisplay.WorkHeight), 5)
            $target.RelativeWidth = [math]::Round([double]$target.Width / [math]::Max(1, $targetDisplay.WorkWidth), 5)
            $target.RelativeHeight = [math]::Round([double]$target.Height / [math]::Max(1, $targetDisplay.WorkHeight), 5)
            $target.DeviceName = $targetDisplay.DeviceName
        }
        foreach ($application in $Profile.Applications) {
            if ($application.ProcessPath) {
                $application.ProcessName = [IO.Path]::GetFileNameWithoutExtension([string]$application.ProcessPath)
            }
        }
        if (-not $Profile.Displays) { $Profile.Displays = @(Get-HaySpaceDisplays) }
        try {
            $destination = Get-HaySpaceProfilePath -ProfileName $Profile.ProfileName
            if ($Profile.ProfileName -ne $originalName -and (Test-Path -LiteralPath $destination) -and [System.Windows.MessageBox]::Show("A profile named '$($Profile.ProfileName)' already exists. Replace it?", 'Confirm overwrite', 'YesNo', 'Warning') -ne 'Yes') {
                return
            }
            Save-HaySpaceProfile -Profile $Profile | Out-Null
            $dialog.DialogResult = $true
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to save profile', 'OK', 'Error') | Out-Null
        }
    })
    if ($dialog.ShowDialog()) {
        Refresh-Profiles
        Sync-ProfileHotkeys
        $script:ProfileList.SelectedItem = Get-HaySpaceProfiles | Where-Object ProfileName -eq $Profile.ProfileName | Select-Object -First 1
        Set-Status "Saved profile '$($Profile.ProfileName)'."
        return $true
    }
    return $false
}

$script:ProfileList.Add_SelectionChanged({
    $profile = $script:ProfileList.SelectedItem
    if ($profile) {
        $script:ProfileSummary.Text = "{0}`n{1}  |  {2} windows  |  {3} applications`nLast updated: {4}" -f $profile.ProfileName, $profile.ProfileType, @($profile.Windows).Count, @($profile.Applications).Count, $profile.UpdatedAt
    }
    else {
        $script:ProfileSummary.Text = 'Select a profile to see its details.'
    }
})

$script:RunAtLogonCheckBox.IsChecked = Test-HaySpaceRunAtLogon
$script:RunAtLogonCheckBox.Add_Click({
    try {
        Set-HaySpaceRunAtLogon -Enabled ([bool]$script:RunAtLogonCheckBox.IsChecked) -ScriptPath $script:HaySpaceScriptPath
        if ($script:RunAtLogonCheckBox.IsChecked) {
            Set-Status 'HaySpace will start at user logon and select a workspace for the connected displays.'
        }
        else {
            Set-Status 'HaySpace will no longer start automatically at user logon.'
        }
    }
    catch {
        $script:RunAtLogonCheckBox.IsChecked = Test-HaySpaceRunAtLogon
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to update logon startup', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('AppDesktopShortcutButton').Add_Click({
    try {
        $shortcut = New-HaySpaceDesktopShortcut
        Set-Status "HaySpace desktop shortcut created: $shortcut"
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to create HaySpace desktop shortcut', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('AppTaskbarShortcutButton').Add_Click({
    try {
        $result = Add-HaySpaceApplicationTaskbarShortcut
        if ($result.Pinned) {
            Set-Status 'HaySpace was pinned to the taskbar.'
        }
        else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$([IO.Path]::GetDirectoryName($result.StartMenuShortcutPath))`""
            [System.Windows.MessageBox]::Show(
                "A HaySpace shortcut that opens Start-HaySpace.cmd was added under Start > All apps > HaySpace. Open Start, search for HaySpace, then right-click it and choose Pin to taskbar if Windows offers that option.`n`n$($result.StartMenuShortcutPath)",
                'Finish pinning HaySpace',
                'OK',
                'Information'
            ) | Out-Null
            Set-Status 'HaySpace Start menu shortcut created; pin it from Start if Windows allows.'
        }
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to add HaySpace to taskbar', 'OK', 'Error') | Out-Null
    }
})

$window.FindName('RefreshProfilesButton').Add_Click({
    try {
        Refresh-Profiles
        Sync-ProfileHotkeys
        Set-Status 'Profiles refreshed from disk.'
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to refresh profiles', 'OK', 'Error') | Out-Null
    }
})

$window.FindName('CaptureButton').Add_Click({
    try {
        $options = Show-CaptureOptions
        if (-not $options) { return }
        $profile = New-HaySpaceCapture -ProfileName 'New Workspace' -ExcludeBrowsers:$options.ExcludeBrowsers -ExcludeExplorer:$options.ExcludeExplorer -ExcludedProcessNames $options.ExcludedProcessNames
        $profile.ProfileName = ''
        if (Show-ProfileEditor -Profile $profile) {
            Set-Status "Captured $(@($profile.Windows).Count) window(s)."
        }
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to capture workspace', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('NewButton').Add_Click({ Show-ProfileEditor -Profile $null })
$window.FindName('EditButton').Add_Click({
    if ($script:ProfileList.SelectedItem) { Show-ProfileEditor -Profile $script:ProfileList.SelectedItem }
})
$window.FindName('CloneButton').Add_Click({
    if ($script:ProfileList.SelectedItem) {
        $clone = $script:ProfileList.SelectedItem | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $clone.ProfileName = $clone.ProfileName + ' Copy'
        Show-ProfileEditor -Profile $clone
    }
})
$window.FindName('DeleteButton').Add_Click({
    $profile = $script:ProfileList.SelectedItem
    if ($profile -and [System.Windows.MessageBox]::Show("Delete '$($profile.ProfileName)'?", 'Confirm deletion', 'YesNo', 'Warning') -eq 'Yes') {
        Remove-HaySpaceProfile -ProfileName $profile.ProfileName
        Remove-HaySpaceShortcut -ProfileName $profile.ProfileName
        Refresh-Profiles
        Sync-ProfileHotkeys
        Set-Status 'Profile deleted.'
    }
})
$window.FindName('LoadButton').Add_Click({
    $profile = $script:ProfileList.SelectedItem
    if (-not $profile) { return }
    try {
        $result = Restore-HaySpaceWorkspace -Profile $profile -LaunchApplications
        Set-Status "Loaded '$($profile.ProfileName)': positioned $($result.PositionedWindows) window(s)."
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to load profile', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('SetDisplayDefaultButton').Add_Click({
    $profile = $script:ProfileList.SelectedItem
    if (-not $profile) {
        [System.Windows.MessageBox]::Show('Select the profile to use for the connected displays.', 'Set display default') | Out-Null
        return
    }
    try {
        $displays = @(Get-HaySpaceDisplays)
        $configurationKey = Set-HaySpaceDisplayProfileAssignment -Displays $displays -ProfileName ([string]$profile.ProfileName)
        Set-Status "'$($profile.ProfileName)' is now the default for this display layout."
        Write-HaySpaceLog -Message "Assigned profile '$($profile.ProfileName)' to the current display configuration '$configurationKey'."
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to set display default', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('MigrationButton').Add_Click({
    $profile = $script:ProfileList.SelectedItem
    if (-not $profile) {
        [System.Windows.MessageBox]::Show('Select a profile to migrate.', 'Migration assistant') | Out-Null
        return
    }
    try {
        if (Show-MigrationAssistant -Profile $profile) {
            Refresh-Profiles
            Set-Status "Migration settings saved for '$($profile.ProfileName)'."
        }
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Migration assistant failed', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('ShortcutButton').Add_Click({
    if ($script:ProfileList.SelectedItem) {
        try {
            $shortcut = New-HaySpaceShortcut -ProfileName $script:ProfileList.SelectedItem.ProfileName
            Set-Status "Shortcut created: $shortcut"
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to create shortcut', 'OK', 'Error') | Out-Null
        }
    }
})
$window.FindName('TaskbarShortcutButton').Add_Click({
    if (-not $script:ProfileList.SelectedItem) { return }
    try {
        $result = Add-HaySpaceTaskbarShortcut -ProfileName $script:ProfileList.SelectedItem.ProfileName
        if ($result.Pinned) {
            Set-Status "Pinned '$($script:ProfileList.SelectedItem.ProfileName)' to the taskbar."
        }
        else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$([IO.Path]::GetDirectoryName($result.StartMenuShortcutPath))`""
            [System.Windows.MessageBox]::Show(
                "A HaySpace Profiles shortcut was added to the Start menu. Open Start > All apps > HaySpace Profiles, then right-click '$([IO.Path]::GetFileNameWithoutExtension($result.StartMenuShortcutPath))'. If Windows offers 'Pin to taskbar' under More, select it. Some Windows versions restrict taskbar pinning.`n`n$($result.StartMenuShortcutPath)",
                'Finish pinning from Start',
                'OK',
                'Information'
            ) | Out-Null
            Set-Status 'Start menu shortcut created; use Start > All apps to pin it if Windows allows.'
        }
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to add taskbar shortcut', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('ExportProfileButton').Add_Click({
    $profile = $script:ProfileList.SelectedItem
    if (-not $profile) { return }
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = 'HaySpace profile (*.json)|*.json'
    $dialog.FileName = '{0}_{1}.json' -f $profile.ProfileName, (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
    if ($dialog.ShowDialog()) {
        try {
            $profile | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $dialog.FileName -Encoding UTF8
            Set-Status "Exported '$($profile.ProfileName)'."
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to export profile', 'OK', 'Error') | Out-Null
        }
    }
})
$window.FindName('ImportProfileButton').Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = 'HaySpace profile (*.json)|*.json'
    if (-not $dialog.ShowDialog()) { return }
    try {
        $profile = Get-Content -LiteralPath $dialog.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $profile.ProfileName -or -not $profile.Version) {
            throw 'The selected JSON file is not a valid HaySpace profile.'
        }
        $destination = Get-HaySpaceProfilePath -ProfileName ([string]$profile.ProfileName)
        if ((Test-Path -LiteralPath $destination) -and [System.Windows.MessageBox]::Show("A profile named '$($profile.ProfileName)' already exists. Replace it?", 'Confirm overwrite', 'YesNo', 'Warning') -ne 'Yes') {
            return
        }
        Save-HaySpaceProfile -Profile $profile | Out-Null
        Refresh-Profiles
        Sync-ProfileHotkeys
        Set-Status "Imported '$($profile.ProfileName)'."
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to import profile', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('BackupButton').Add_Click({
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = 'ZIP backup (*.zip)|*.zip'
    $dialog.FileName = 'HaySpaceBackup_{0}.zip' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
    if ($dialog.ShowDialog()) {
        try {
            Export-HaySpaceBackup -DestinationPath $dialog.FileName
            Set-Status 'Backup created.'
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to create backup', 'OK', 'Error') | Out-Null
        }
    }
})
$window.FindName('RestoreButton').Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = 'ZIP backup (*.zip)|*.zip'
    if ($dialog.ShowDialog() -and [System.Windows.MessageBox]::Show('Restore this backup? Existing matching files will be replaced.', 'Confirm restore', 'YesNo', 'Warning') -eq 'Yes') {
        try {
            Import-HaySpaceBackup -ArchivePath $dialog.FileName
            Refresh-Profiles
            Refresh-Displays
            Sync-ProfileHotkeys
            Set-Status 'Backup restored.'
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to restore backup', 'OK', 'Error') | Out-Null
        }
    }
})
$window.FindName('RefreshDisplaysButton').Add_Click({ Refresh-Displays })
$window.FindName('TestDisplayButton').Add_Click({
    $display = $script:DisplayList.SelectedItem
    if (-not $display) { return }
    try {
        Show-HaySpaceDisplayIdentification -Display $display
        Set-Status "Display test complete: $($display.DisplayName)."
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Display test failed', 'OK', 'Error') | Out-Null
    }
})
$window.FindName('RenameDisplayButton').Add_Click({
    $display = $script:DisplayList.SelectedItem
    if (-not $display) { return }
    $dialog = New-Object Windows.Window
    $dialog.Title = 'Rename display'
    $dialog.Width = 360
    $dialog.Height = 150
    $dialog.Owner = $window
    $dialog.WindowStartupLocation = 'CenterOwner'
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = '16'
    $box = New-Object Windows.Controls.TextBox
    $box.Text = $display.DisplayName
    $panel.Children.Add($box) | Out-Null
    $save = New-Object Windows.Controls.Button
    $save.Content = 'Save'
    $save.Margin = '0,12,0,0'
    $save.HorizontalAlignment = 'Right'
    $panel.Children.Add($save) | Out-Null
    $dialog.Content = $panel
    $save.Add_Click({
        try {
            Set-HaySpaceDisplayName -DeviceName $display.DeviceName -DisplayName $box.Text
            $dialog.DialogResult = $true
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to rename display', 'OK', 'Error') | Out-Null
        }
    })
    if ($dialog.ShowDialog()) { Refresh-Displays; Set-Status 'Display name saved.' }
})
$window.FindName('OpenDataFolderButton').Add_Click({
    Start-Process explorer.exe -ArgumentList "`"$($paths.Root)`""
})

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$notifyIcon.Text = 'HaySpace'
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayMenu.Add_Opening({
    $trayMenu.Items.Clear()
    $showItem = $trayMenu.Items.Add('Open HaySpace')
    $showItem.Add_Click({ Show-HaySpaceDashboard })
    $trayMenu.Items.Add('-') | Out-Null
    foreach ($trayProfile in @(Get-HaySpaceProfiles)) {
        $profileName = [string]$trayProfile.ProfileName
        $item = $trayMenu.Items.Add($profileName)
        $item.Add_Click({
            param($sender, $eventArgs)
            $name = [string]$sender.Text
            $targetProfile = Get-HaySpaceProfiles | Where-Object ProfileName -eq $name | Select-Object -First 1
            if ($targetProfile) {
                try {
                    $null = Restore-HaySpaceWorkspace -Profile $targetProfile -LaunchApplications
                    Set-Status "Loaded '$name' from tray."
                }
                catch {
                    [System.Windows.MessageBox]::Show($_.Exception.Message, 'Unable to load profile', 'OK', 'Error') | Out-Null
                }
            }
        })
    }
    $trayMenu.Items.Add('-') | Out-Null
    $exitItem = $trayMenu.Items.Add('Exit')
    $exitItem.Add_Click({
        $script:ExitRequested = $true
        Write-HaySpaceLog -Message 'HaySpace exit requested from the notification area.'
        $window.Close()
        [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvokeShutdown([Windows.Threading.DispatcherPriority]::Normal)
    })
})
$notifyIcon.ContextMenuStrip = $trayMenu
$notifyIcon.Visible = $true
$notifyIcon.Add_DoubleClick({ Show-HaySpaceDashboard })
$window.Add_Closing({
    param($sender, $eventArgs)
    if (-not $script:ExitRequested) {
        $eventArgs.Cancel = $true
        Write-HaySpaceLog -Message 'Dashboard close requested; minimizing HaySpace to the notification area.'
        Minimize-HaySpaceToTray
    }
    else {
        foreach ($id in @($script:HotkeyIds.Keys)) {
            [HaySpace.NativeWindow]::UnregisterHotKey($script:HotkeySource.Handle, [int]$id) | Out-Null
        }
        $script:HotkeyIds.Clear()
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        $trayMenu.Dispose()
        Write-HaySpaceLog -Message 'HaySpace notification area resources released.'
    }
})

Refresh-Profiles
Refresh-Displays
$window.Add_SourceInitialized({
    $script:HotkeySource = [Windows.Interop.HwndSource]::FromHwnd((New-Object Windows.Interop.WindowInteropHelper($window)).Handle)
    if ($script:HotkeySource) {
        $script:HotkeyHook = [Windows.Interop.HwndSourceHook]{
            param($handle, $message, $wParam, $lParam, [ref]$handled)
            if ($message -ne 0x0312) { return [IntPtr]::Zero }
            $hotkeyIdValue = $wParam.ToInt64()
            if ($hotkeyIdValue -lt [int]::MinValue -or $hotkeyIdValue -gt [int]::MaxValue) { return [IntPtr]::Zero }
            $hotkeyId = [int]$hotkeyIdValue
            if ($script:HotkeyIds.ContainsKey($hotkeyId)) {
                $handled.Value = $true
                $profileName = [string]$script:HotkeyIds[$hotkeyId]
                $profile = Get-HaySpaceProfiles | Where-Object ProfileName -eq $profileName | Select-Object -First 1
                if ($profile) {
                    try {
                        $result = Restore-HaySpaceWorkspace -Profile $profile -LaunchApplications
                        Set-Status "Loaded '$profileName' by hotkey; positioned $($result.PositionedWindows) window(s)."
                    }
                    catch {
                        Write-HaySpaceLog -Level Error -Message "Hotkey restore failed for '$profileName': $($_.Exception.Message)"
                        Set-Status "Could not load '$profileName'; see the log."
                    }
                }
            }
            return [IntPtr]::Zero
        }
        $script:HotkeySource.AddHook($script:HotkeyHook)
        Sync-ProfileHotkeys
    }
})
if ($Tray) {
    $window.Add_ContentRendered({ Minimize-HaySpaceToTray })
}
if ($AutoLoadProfile) {
    $window.Add_ContentRendered({
        if ($Tray) { Minimize-HaySpaceToTray }
        Invoke-AutoProfileStartup
    })
}
Write-HaySpaceLog -Message "HaySpace dashboard starting (tray startup: $([bool]$Tray); automatic profile loading: $([bool]$AutoLoadProfile))."
$dispatcher = [Windows.Threading.Dispatcher]::CurrentDispatcher
$dispatcher.Add_UnhandledException({
    param($sender, $eventArgs)
    Write-HaySpaceLog -Level Error -Message "Unhandled WPF dispatcher exception: $($eventArgs.Exception.ToString())"
})
try {
    $window.Show()
    [Windows.Threading.Dispatcher]::Run()
}
catch {
    Write-HaySpaceLog -Level Error -Message "HaySpace dispatcher failed: $($_.Exception.ToString())"
    throw
}
finally {
    Write-HaySpaceLog -Message 'HaySpace dispatcher stopped.'
    $script:HaySpaceInstanceMutex.ReleaseMutex()
    $script:HaySpaceInstanceMutex.Dispose()
    [HaySpace.NativeWindow]::RestoreDpiAwarenessContext($script:HaySpaceDpiContext)
}
