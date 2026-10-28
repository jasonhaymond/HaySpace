Set-StrictMode -Version Latest

if (-not ('HaySpace.NativeWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Diagnostics;

namespace HaySpace {
    public class WindowInfo {
        public IntPtr Handle;
        public string Title;
        public int ProcessId;
        public string ProcessName;
        public string ProcessPath;
        public int X;
        public int Y;
        public int Width;
        public int Height;
        public bool Maximized;
        public bool Minimized;
    }

    public static class NativeWindow {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }
        [StructLayout(LayoutKind.Sequential)]
        private struct WINDOWPLACEMENT {
            public uint Length;
            public uint Flags;
            public uint ShowCmd;
            public POINT MinPosition;
            public POINT MaxPosition;
            public RECT NormalPosition;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct MONITORINFO {
            public uint Size;
            public RECT Monitor;
            public RECT Work;
            public uint Flags;
        }
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int processId);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")] private static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
        [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool IsZoomed(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int command);
        [DllImport("user32.dll", SetLastError=true)] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);
        [DllImport("user32.dll", SetLastError=true)] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint virtualKey);
        [DllImport("user32.dll", SetLastError=true)] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        private const uint SWP_NOZORDER = 0x0004;
        private const uint SWP_NOACTIVATE = 0x0010;
        private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

        public static IntPtr EnterPhysicalCoordinates() {
            try {
                return SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
            } catch (EntryPointNotFoundException) {
                return IntPtr.Zero;
            }
        }

        public static void RestoreDpiAwarenessContext(IntPtr previousContext) {
            if (previousContext != IntPtr.Zero) SetThreadDpiAwarenessContext(previousContext);
        }

        public static WindowInfo[] GetWindows() {
            IntPtr previousContext = EnterPhysicalCoordinates();
            try {
                var result = new System.Collections.Generic.List<WindowInfo>();
                EnumWindows(delegate(IntPtr hWnd, IntPtr ignored) {
                    if (!IsWindowVisible(hWnd)) return true;
                    var text = new StringBuilder(1024);
                    GetWindowText(hWnd, text, text.Capacity);
                    if (text.Length == 0) return true;
                    int pid;
                    GetWindowThreadProcessId(hWnd, out pid);
                    try {
                        var process = Process.GetProcessById(pid);
                        RECT rect;
                        bool minimized = IsIconic(hWnd);
                        if (minimized) {
                            WINDOWPLACEMENT placement = new WINDOWPLACEMENT();
                            placement.Length = (uint)Marshal.SizeOf(typeof(WINDOWPLACEMENT));
                            if (GetWindowPlacement(hWnd, ref placement)) {
                                rect = placement.NormalPosition;
                                IntPtr monitor = MonitorFromWindow(hWnd, 2);
                                if (monitor != IntPtr.Zero) {
                                    MONITORINFO info = new MONITORINFO();
                                    info.Size = (uint)Marshal.SizeOf(typeof(MONITORINFO));
                                    if (GetMonitorInfo(monitor, ref info)) {
                                        int offsetX = info.Monitor.Left - info.Work.Left;
                                        int offsetY = info.Monitor.Top - info.Work.Top;
                                        rect.Left += offsetX;
                                        rect.Right += offsetX;
                                        rect.Top += offsetY;
                                        rect.Bottom += offsetY;
                                    }
                                }
                            } else if (!GetWindowRect(hWnd, out rect)) {
                                return true;
                            }
                        } else if (!GetWindowRect(hWnd, out rect)) {
                            return true;
                        }
                        result.Add(new WindowInfo {
                            Handle = hWnd,
                            Title = text.ToString(),
                            ProcessId = pid,
                            ProcessName = process.ProcessName,
                            ProcessPath = process.MainModule.FileName,
                            X = rect.Left,
                            Y = rect.Top,
                            Width = Math.Max(0, rect.Right - rect.Left),
                            Height = Math.Max(0, rect.Bottom - rect.Top),
                            Maximized = IsZoomed(hWnd),
                            Minimized = minimized
                        });
                    } catch { }
                    return true;
                }, IntPtr.Zero);
                return result.ToArray();
            } finally {
                RestoreDpiAwarenessContext(previousContext);
            }
        }

        public static bool Move(IntPtr handle, int x, int y, int width, int height, int state) {
            IntPtr previousContext = EnterPhysicalCoordinates();
            try {
                ShowWindow(handle, 9);
                if (!SetWindowPos(handle, IntPtr.Zero, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE)) return false;
                if (state == 1) ShowWindow(handle, 3);
                else if (state == 2) ShowWindow(handle, 2);
                return true;
            } finally {
                RestoreDpiAwarenessContext(previousContext);
            }
        }
    }
}
'@
}

function Get-HaySpaceDisplays {
    Add-Type -AssemblyName System.Windows.Forms
    $settings = Get-HaySpaceSettings
    $previousDpiContext = [HaySpace.NativeWindow]::EnterPhysicalCoordinates()
    try {
        $screens = [System.Windows.Forms.Screen]::AllScreens
        $result = @()
        foreach ($screen in $screens) {
            $friendlyName = $screen.DeviceName
            if ($settings.DisplayNames -and $settings.DisplayNames.ContainsKey($screen.DeviceName)) {
                $friendlyName = [string]$settings.DisplayNames[$screen.DeviceName]
            }
            $result += [pscustomobject]@{
                DeviceName = $screen.DeviceName
                DisplayName = $friendlyName
                Primary = $screen.Primary
                X = $screen.Bounds.X
                Y = $screen.Bounds.Y
                Width = $screen.Bounds.Width
                Height = $screen.Bounds.Height
                WorkX = $screen.WorkingArea.X
                WorkY = $screen.WorkingArea.Y
                WorkWidth = $screen.WorkingArea.Width
                WorkHeight = $screen.WorkingArea.Height
            }
        }
        return $result
    }
    finally {
        [HaySpace.NativeWindow]::RestoreDpiAwarenessContext($previousDpiContext)
    }
}

function Get-HaySpaceDisplayConfigurationKey {
    param([Parameter(Mandatory)][object[]]$Displays)
    if (-not $Displays.Count) { throw 'At least one display is required to identify a configuration.' }
    $minimumX = [double](($Displays | Measure-Object -Property X -Minimum).Minimum)
    $minimumY = [double](($Displays | Measure-Object -Property Y -Minimum).Minimum)
    $configuration = @(
        foreach ($display in $Displays) {
            $displayName = if ($display.PSObject.Properties['DisplayName'] -and $display.DisplayName) { [string]$display.DisplayName } else { [string]$display.DeviceName }
            if ([string]::IsNullOrWhiteSpace($displayName) -or [double]$display.Width -le 0 -or [double]$display.Height -le 0) {
                throw 'Each display needs a name and positive dimensions to identify its configuration.'
            }
            [pscustomobject]@{
                Name = $displayName
                X = [int]([double]$display.X - $minimumX)
                Y = [int]([double]$display.Y - $minimumY)
                Width = [int]$display.Width
                Height = [int]$display.Height
                Primary = [bool]$display.Primary
            }
        }
    )
    $canonical = ConvertTo-Json -InputObject @($configuration | Sort-Object Name, X, Y, Width, Height) -Depth 4 -Compress
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-HaySpaceExplorerFolders {
    $folders = @{}
    $shell = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($item in $shell.Windows()) {
            try {
                $path = [uri]::UnescapeDataString(([uri]$item.LocationURL).LocalPath)
                if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
                $handle = [int64]$item.HWND
                $folders[$handle.ToString()] = [IO.Path]::GetFullPath($path)
            }
            catch {
                Write-HaySpaceLog -Level Debug -Message "Skipped an Explorer window without a local folder path: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-HaySpaceLog -Level Warning -Message "Could not enumerate Explorer folder windows: $($_.Exception.Message)"
    }
    return $folders
}

function Get-HaySpaceBrowserUrl {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)
    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
        $element = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
        if (-not $element) { return $null }
        $descendants = $element.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        foreach ($candidate in $descendants) {
            $automationId = [string]$candidate.Current.AutomationId
            $name = [string]$candidate.Current.Name
            if ($automationId -notmatch '(?i)(address|omnibox|urlbar)' -and $name -notmatch '(?i)(address and search|search or enter address|url bar)') { continue }
            $pattern = $null
            if (-not $candidate.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) { continue }
            $value = [string]$pattern.Current.Value
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            if ($value -notmatch '^[a-z][a-z0-9+.-]*://') { $value = 'https://' + $value }
            $uri = $null
            if ([uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https') -and $uri.Host) {
                return $uri.AbsoluteUri
            }
        }
    }
    catch {
        Write-HaySpaceLog -Level Debug -Message "Could not read the active browser URL: $($_.Exception.Message)"
    }
    return $null
}

function Set-HaySpaceDisplayName {
    param([Parameter(Mandatory)][string]$DeviceName, [Parameter(Mandatory)][string]$DisplayName)
    $settings = Get-HaySpaceSettings
    if (-not $settings.DisplayNames) {
        $settings | Add-Member -NotePropertyName DisplayNames -NotePropertyValue @{} -Force
    }
    $settings.DisplayNames[$DeviceName] = $DisplayName.Trim()
    Save-HaySpaceSettings $settings
}

function Get-HaySpaceWindowState {
    param($Window)
    if ($Window.Minimized) { return 'Minimized' }
    if ($Window.Maximized) { return 'Maximized' }
    return 'Normal'
}

function Get-HaySpaceWindowDisplay {
    param($Window, [array]$Displays)
    $centerX = [int]($Window.X + ($Window.Width / 2))
    $centerY = [int]($Window.Y + ($Window.Height / 2))
    foreach ($display in $Displays) {
        if ($centerX -ge $display.X -and $centerX -lt ($display.X + $display.Width) -and $centerY -ge $display.Y -and $centerY -lt ($display.Y + $display.Height)) {
            return $display
        }
    }
    return ($Displays | Where-Object Primary | Select-Object -First 1)
}

function Test-HaySpaceApplicationWindowOpen {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Windows, [Parameter(Mandatory)][string]$ProcessName)
    return [bool](
        $Windows |
            Where-Object { $_.ProcessName -eq $ProcessName -and $_.Width -gt 0 -and $_.Height -gt 0 } |
            Select-Object -First 1
    )
}

function New-HaySpaceCapture {
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [ValidateSet('Quick Layout', 'Workspace Layout', 'Full Workspace')][string]$ProfileType = 'Full Workspace',
        [string[]]$ExcludedProcessNames = @(),
        [switch]$ExcludeBrowsers,
        [switch]$ExcludeExplorer
    )
    $displays = @(Get-HaySpaceDisplays)
    $browserNames = @('msedge', 'chrome', 'firefox')
    $explorerFoldersByHandle = Get-HaySpaceExplorerFolders
    $windows = @()
    $applications = @()
    $explorerFolders = @()
    $urls = @()
    foreach ($window in [HaySpace.NativeWindow]::GetWindows()) {
        if ($ExcludedProcessNames -contains $window.ProcessName) { continue }
        if ($ExcludeBrowsers -and $browserNames -contains $window.ProcessName) { continue }
        if ($ExcludeExplorer -and $window.ProcessName -eq 'explorer') { continue }
        if ($window.Width -lt 100 -or $window.Height -lt 60) { continue }
        $display = Get-HaySpaceWindowDisplay -Window $window -Displays $displays
        if (-not $display) { continue }
        $state = Get-HaySpaceWindowState $window
        if ($browserNames -contains $window.ProcessName) {
            $activeUrl = Get-HaySpaceBrowserUrl -WindowHandle $window.Handle
            if ($activeUrl -and $urls -notcontains $activeUrl) {
                $urls += $activeUrl
            }
        }
        $folderPath = $null
        $handleKey = $window.Handle.ToInt64().ToString()
        if ($window.ProcessName -eq 'explorer' -and $explorerFoldersByHandle.ContainsKey($handleKey)) {
            $folderPath = $explorerFoldersByHandle[$handleKey]
            $explorerFolders += [pscustomobject]@{
                Path = $folderPath
                Title = $window.Title
                DisplayName = $display.DisplayName
                DeviceName = $display.DeviceName
                X = $window.X
                Y = $window.Y
                Width = $window.Width
                Height = $window.Height
                RelativeX = [math]::Round(($window.X - $display.WorkX) / [double]$display.WorkWidth, 5)
                RelativeY = [math]::Round(($window.Y - $display.WorkY) / [double]$display.WorkHeight, 5)
                RelativeWidth = [math]::Round($window.Width / [double]$display.WorkWidth, 5)
                RelativeHeight = [math]::Round($window.Height / [double]$display.WorkHeight, 5)
                State = $state
            }
        }
        $windows += [pscustomobject]@{
            Title = $window.Title
            ProcessName = $window.ProcessName
            ProcessPath = $window.ProcessPath
            DisplayName = $display.DisplayName
            DeviceName = $display.DeviceName
            X = $window.X
            Y = $window.Y
            Width = $window.Width
            Height = $window.Height
            RelativeX = [math]::Round(($window.X - $display.WorkX) / [double]$display.WorkWidth, 5)
            RelativeY = [math]::Round(($window.Y - $display.WorkY) / [double]$display.WorkHeight, 5)
            RelativeWidth = [math]::Round($window.Width / [double]$display.WorkWidth, 5)
            RelativeHeight = [math]::Round($window.Height / [double]$display.WorkHeight, 5)
            State = $state
            FolderPath = $folderPath
        }
        if ($ProfileType -ne 'Quick Layout' -and -not ($applications | Where-Object { $_.ProcessPath -eq $window.ProcessPath })) {
            $applications += [pscustomobject]@{
                ProcessName = $window.ProcessName
                ProcessPath = $window.ProcessPath
                Arguments = ''
                Launch = $true
                LaunchOrder = $applications.Count
            }
        }
    }

    $browserMode = 'Ignore'
    if ($ProfileType -eq 'Quick Layout') {
        $applications = @()
    }
    return [pscustomobject]@{
        ProfileName = $ProfileName.Trim()
        ProfileType = $ProfileType
        Version = '1.0'
        CreatedAt = (Get-Date).ToString('o')
        UpdatedAt = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        BrowserMode = $browserMode
        Applications = @($applications)
        Windows = @($windows)
        Urls = @($urls)
        ExplorerFolders = @($explorerFolders)
        RdpFiles = @()
        Hotkey = ''
        Displays = @($displays)
        LaunchDelaySeconds = 2
    }
}

function Get-HaySpaceBrowserPath {
    param([string]$ProcessName)
    $candidates = switch ($ProcessName) {
        'msedge' { @("$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") }
        'chrome' { @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") }
        'firefox' { @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "$env:ProgramFiles(x86)\Mozilla Firefox\firefox.exe") }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Restore-HaySpaceWorkspace {
    param([Parameter(Mandatory)]$Profile, [switch]$LaunchApplications)
    $displays = @(Get-HaySpaceDisplays)
    if ($displays.Count -eq 0) { throw 'No displays are currently available.' }
    $profileType = if ($Profile.PSObject.Properties['ProfileType']) { [string]$Profile.ProfileType } else { 'Full Workspace' }
    $profileApplications = @(if ($Profile.PSObject.Properties['Applications']) { $Profile.Applications })
    $profileExplorerFolders = @(if ($Profile.PSObject.Properties['ExplorerFolders']) { $Profile.ExplorerFolders })
    $profileRdpFiles = @(if ($Profile.PSObject.Properties['RdpFiles']) { $Profile.RdpFiles })
    $profileWindows = @(if ($Profile.PSObject.Properties['Windows']) { $Profile.Windows })
    $browserMode = if ($Profile.PSObject.Properties['BrowserMode']) { [string]$Profile.BrowserMode } else { 'Ignore' }
    $browserNames = @('msedge', 'chrome', 'firefox')
    $launches = @()
    if ($LaunchApplications) {
        foreach ($folder in $profileExplorerFolders) {
            if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path -PathType Container)) {
                Write-HaySpaceLog -Level Warning -Message "Explorer folder is unavailable: '$($folder.Path)'."
                continue
            }
            try {
                Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$($folder.Path)`"" | Out-Null
                Start-Sleep -Milliseconds 150
            }
            catch {
                Write-HaySpaceLog -Level Warning -Message "Could not open Explorer folder '$($folder.Path)': $($_.Exception.Message)"
            }
        }
        foreach ($rdpFile in $profileRdpFiles) {
            if (-not $rdpFile -or -not (Test-Path -LiteralPath $rdpFile -PathType Leaf)) {
                Write-HaySpaceLog -Level Warning -Message "RDP file is unavailable: '$rdpFile'."
                continue
            }
            try {
                Start-Process -FilePath 'mstsc.exe' -ArgumentList "`"$rdpFile`"" | Out-Null
                Start-Sleep -Milliseconds 200
            }
            catch {
                Write-HaySpaceLog -Level Warning -Message "Could not open RDP file '$rdpFile': $($_.Exception.Message)"
            }
        }
    }
    if ($LaunchApplications -and $profileType -ne 'Quick Layout') {
        $currentWindows = @([HaySpace.NativeWindow]::GetWindows())
        foreach ($app in @($profileApplications | Sort-Object LaunchOrder)) {
            if ($app.PSObject.Properties['Launch'] -and -not $app.Launch) { continue }
            $processName = if ($app.PSObject.Properties['ProcessName']) { [string]$app.ProcessName } else { '' }
            $processPath = if ($app.PSObject.Properties['ProcessPath']) { [string]$app.ProcessPath } else { '' }
            $appUserModelId = if ($app.PSObject.Properties['AppUserModelId']) { [string]$app.AppUserModelId } else { '' }
            $alreadyRunning = if ($processName) { Test-HaySpaceApplicationWindowOpen -Windows $currentWindows -ProcessName $processName } else { $false }
            $launchAlreadyRequested = [bool]($launches | Where-Object ProcessName -eq $processName | Select-Object -First 1)
            $isSessionBrowser = $browserMode -eq 'Session' -and $processName -in @('msedge', 'chrome', 'firefox')
            if (-not $launchAlreadyRequested -and (-not $alreadyRunning -or $isSessionBrowser) -and $appUserModelId) {
                try {
                    if ($appUserModelId -notmatch '^[^\\/:*?"<>|]+![^\\/:*?"<>|]+$') {
                        throw "Invalid installed-app identifier '$appUserModelId'."
                    }
                    $process = Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$appUserModelId" -PassThru
                    $launches += [pscustomobject]@{ ProcessName = $processName; ProcessId = $process.Id; StartedAt = Get-Date }
                    Start-Sleep -Milliseconds 500
                }
                catch {
                    Write-HaySpaceLog -Level Warning -Message "Could not launch installed app '$appUserModelId': $($_.Exception.Message)"
                }
            }
            elseif (-not $launchAlreadyRequested -and (-not $alreadyRunning -or $isSessionBrowser) -and $processPath -and (Test-Path -LiteralPath $processPath)) {
                try {
                    $arguments = if ($app.PSObject.Properties['Arguments']) { [string]$app.Arguments } else { '' }
                    if ($browserMode -eq 'Session' -and $processName -in @('msedge', 'chrome', 'firefox')) {
                        $sessionArgument = if ($processName -eq 'firefox') { '-restore' } else { '--restore-last-session' }
                        if ($arguments) { $arguments += ' ' + $sessionArgument } else { $arguments = $sessionArgument }
                    }
                    if ($processName -in $browserNames -and -not $alreadyRunning -and $arguments -notmatch '(?i)(^|\s)--new-window(\s|$)') {
                        if ($arguments) { $arguments += ' --new-window' } else { $arguments = '--new-window' }
                    }
                    if ([string]::IsNullOrWhiteSpace($arguments)) {
                        $process = Start-Process -FilePath $processPath -PassThru
                    }
                    else {
                        $process = Start-Process -FilePath $processPath -ArgumentList $arguments -PassThru
                    }
                    $launches += [pscustomobject]@{ ProcessName = $processName; ProcessId = $process.Id; StartedAt = Get-Date }
                    Start-Sleep -Milliseconds 250
                }
                catch {
                    Write-HaySpaceLog -Level Warning -Message "Could not launch '$processPath': $($_.Exception.Message)"
                }
            }
            elseif (-not $alreadyRunning -and $processPath) {
                Write-HaySpaceLog -Level Warning -Message "Application executable is unavailable: '$processPath'."
            }
        }
    }

    $profileUrls = @(if ($Profile.PSObject.Properties['Urls']) { $Profile.Urls })
    $shouldOpenUrls = $browserMode -eq 'URL'
    if ($browserMode -eq 'Hybrid') {
        $browserWindows = @([HaySpace.NativeWindow]::GetWindows() | Where-Object { $_.ProcessName -in $browserNames -and $_.Width -gt 0 -and $_.Height -gt 0 })
        $shouldOpenUrls = $browserWindows.Count -eq 0
    }
    if ($shouldOpenUrls) {
        foreach ($url in $profileUrls) {
            if ([string]::IsNullOrWhiteSpace([string]$url)) { continue }
            $parsedUrl = $null
            if ([uri]::TryCreate([string]$url, [UriKind]::Absolute, [ref]$parsedUrl) -and $parsedUrl.Scheme -in @('http', 'https')) {
                Start-Process -FilePath $parsedUrl.AbsoluteUri
            }
            else {
                Write-HaySpaceLog -Level Warning -Message "Skipped a non-HTTP(S) profile URL in '$($Profile.ProfileName)'."
            }
        }
    }

    $profileProcessNames = @(
        $profileApplications |
            Where-Object { $_.ProcessName -and -not ($_.PSObject.Properties['Launch'] -and -not $_.Launch) } |
            Select-Object -ExpandProperty ProcessName -Unique
    )
    $startupTimeoutSeconds = if ($LaunchApplications -and $profileWindows.Count -gt 0 -and $profileProcessNames.Count -gt 0) { 45 } else { 15 }
    $deadline = (Get-Date).AddSeconds($startupTimeoutSeconds)
    $requestedCount = $profileWindows.Count
    $placedTargets = @{}
    $trackedTargets = @{}
    $targetIndex = 0
    foreach ($target in $profileWindows) {
        if ($target.ProcessName -and $profileProcessNames -contains [string]$target.ProcessName -and $target.Title) {
            $trackedTargets[$targetIndex.ToString()] = $true
        }
        $targetIndex++
    }
    $settleSeconds = if ($Profile.PSObject.Properties['LaunchDelaySeconds']) {
        [math]::Max(0, [math]::Min(10, [int]$Profile.LaunchDelaySeconds))
    }
    else {
        2
    }
    $settledSince = $null
    $settings = Get-HaySpaceSettings
    do {
        $currentWindows = [HaySpace.NativeWindow]::GetWindows()
        $usedHandles = @{}
        $targetIndex = 0
        $placedThisPass = 0
        $exactTitleMatches = @{}
        foreach ($target in $profileWindows) {
            $targetKey = $targetIndex.ToString()
            $targetIndex++
            $eligible = @($currentWindows | Where-Object { $_.Width -gt 0 -and $_.Height -gt 0 -and -not $usedHandles.ContainsKey($_.Handle.ToInt64().ToString()) })
            $candidate = $eligible | Where-Object { $_.ProcessName -eq $target.ProcessName -and $_.Title -eq $target.Title } | Select-Object -First 1
            if ($candidate) { $exactTitleMatches[$targetKey] = $true }
            if (-not $candidate) {
                $candidate = $eligible | Where-Object { $_.ProcessName -eq $target.ProcessName } | Select-Object -First 1
            }
            if (-not $candidate -and $target.Title) {
                $candidate = $eligible | Where-Object { $_.Title -eq $target.Title } | Select-Object -First 1
            }
            if (-not $candidate -and $target.ProcessPath) {
                $candidate = $eligible |
                    Where-Object { $_.ProcessPath -eq $target.ProcessPath } |
                    Select-Object -First 1
            }
            if (-not $candidate) { continue }
            $usedHandles[$candidate.Handle.ToInt64().ToString()] = $true

            $mappedDeviceName = $null
            if ($settings.DisplayMappings -and $target.DisplayName -and $settings.DisplayMappings.ContainsKey([string]$target.DisplayName)) {
                $mappedDeviceName = [string]$settings.DisplayMappings[[string]$target.DisplayName]
            }
            $display = $displays | Where-Object { $_.DeviceName -eq $mappedDeviceName } | Select-Object -First 1
            if (-not $display) {
                $display = $displays | Where-Object { $_.DisplayName -eq $target.DisplayName } | Select-Object -First 1
            }
            if (-not $display) {
                $display = $displays | Where-Object { $_.DeviceName -eq $target.DeviceName } | Select-Object -First 1
            }
            if (-not $display) { $display = $displays | Where-Object Primary | Select-Object -First 1 }
            if (-not $display) { $display = $displays[0] }

            $workWidth = [math]::Max(1, $display.WorkWidth)
            $workHeight = [math]::Max(1, $display.WorkHeight)
            $relativeX = if ($target.PSObject.Properties['RelativeX'] -and $null -ne $target.RelativeX) { [double]$target.RelativeX } else { ([double]$target.X - $display.WorkX) / $workWidth }
            $relativeY = if ($target.PSObject.Properties['RelativeY'] -and $null -ne $target.RelativeY) { [double]$target.RelativeY } else { ([double]$target.Y - $display.WorkY) / $workHeight }
            $relativeWidth = if ($target.PSObject.Properties['RelativeWidth'] -and $null -ne $target.RelativeWidth) { [double]$target.RelativeWidth } else { [double]$target.Width / $workWidth }
            $relativeHeight = if ($target.PSObject.Properties['RelativeHeight'] -and $null -ne $target.RelativeHeight) { [double]$target.RelativeHeight } else { [double]$target.Height / $workHeight }
            $frameAllowance = 32
            $width = [math]::Min($workWidth + ($frameAllowance * 2), [math]::Max(240, [int][math]::Round($relativeWidth * $workWidth)))
            $height = [math]::Min($workHeight + ($frameAllowance * 2), [math]::Max(160, [int][math]::Round($relativeHeight * $workHeight)))
            $x = [int][math]::Round($display.WorkX + ($relativeX * $workWidth))
            $y = [int][math]::Round($display.WorkY + ($relativeY * $workHeight))
            $x = [math]::Max($display.WorkX - $frameAllowance, [math]::Min($x, $display.WorkX + $workWidth - $width + $frameAllowance))
            $y = [math]::Max($display.WorkY - $frameAllowance, [math]::Min($y, $display.WorkY + $workHeight - $height + $frameAllowance))
            $state = switch ([string]$target.State) { 'Maximized' { 1 } 'Minimized' { 2 } default { 0 } }
            $candidateDisplay = Get-HaySpaceWindowDisplay -Window $candidate -Displays $displays
            $needsMove = switch ($state) {
                1 {
                    -not $candidate.Maximized -or $candidate.Minimized -or
                        -not $candidateDisplay -or $candidateDisplay.DeviceName -ne $display.DeviceName
                }
                2 {
                    -not $candidate.Minimized -or
                        [math]::Abs($candidate.X - $x) -gt 1 -or
                        [math]::Abs($candidate.Y - $y) -gt 1 -or
                        [math]::Abs($candidate.Width - $width) -gt 1 -or
                        [math]::Abs($candidate.Height - $height) -gt 1
                }
                default {
                    $candidate.Maximized -or $candidate.Minimized -or
                        [math]::Abs($candidate.X - $x) -gt 1 -or
                        [math]::Abs($candidate.Y - $y) -gt 1 -or
                        [math]::Abs($candidate.Width - $width) -gt 1 -or
                        [math]::Abs($candidate.Height - $height) -gt 1
                }
            }
            if ($needsMove -and -not [HaySpace.NativeWindow]::Move($candidate.Handle, $x, $y, $width, $height, $state)) {
                continue
            }
            $placedTargets[$targetKey] = $true
            $placedThisPass++
        }
        $allLaunchedTargetsMatched = $true
        foreach ($targetKey in $trackedTargets.Keys) {
            if (-not $exactTitleMatches.ContainsKey($targetKey)) {
                $allLaunchedTargetsMatched = $false
                break
            }
        }
        if ($placedThisPass -eq $requestedCount -and $allLaunchedTargetsMatched) {
            if (-not $settledSince) { $settledSince = Get-Date }
            if ($launches.Count -eq 0 -or ((Get-Date) - $settledSince).TotalSeconds -ge $settleSeconds) { break }
        }
        else {
            $settledSince = $null
        }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if (-not $allLaunchedTargetsMatched) {
        $unmatchedTitles = @(
            foreach ($targetKey in $trackedTargets.Keys) {
                if (-not $exactTitleMatches.ContainsKey($targetKey)) {
                    [string]$profileWindows[[int]$targetKey].Title
                }
            }
        ) -join ', '
        Write-HaySpaceLog -Level Warning -Message "Application windows did not reach their saved titles within $startupTimeoutSeconds seconds: $unmatchedTitles."
    }
    $positionedCount = $placedTargets.Count
    Write-HaySpaceLog -Message "Restored profile '$($Profile.ProfileName)': positioned $positionedCount window(s)."
    return [pscustomobject]@{ PositionedWindows = $positionedCount; RequestedWindows = $requestedCount; LaunchedApplications = $launches.Count; RestoredExplorerFolders = $profileExplorerFolders.Count }
}

Export-ModuleMember -Function Get-HaySpaceDisplays, Get-HaySpaceDisplayConfigurationKey, Get-HaySpaceExplorerFolders, Get-HaySpaceBrowserUrl, Set-HaySpaceDisplayName, New-HaySpaceCapture, Restore-HaySpaceWorkspace, Get-HaySpaceBrowserPath
