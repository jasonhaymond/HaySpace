$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'Modules\Storage.psm1') -Force
Import-Module (Join-Path $root 'Modules\Workspace.psm1') -Force
$null = Initialize-HaySpaceStorage
$previousDpiContext = [HaySpace.NativeWindow]::EnterPhysicalCoordinates()
Add-Type -AssemblyName System.Windows.Forms

$suffix = [guid]::NewGuid().ToString('N')
$processName = (Get-Process -Id $PID).ProcessName
$forms = @()
$requestedBounds = @{}
$capturedBounds = @{}
$windowTitles = @()

try {
    $displays = @(Get-HaySpaceDisplays | Where-Object Primary)
    if (-not $displays.Count) { throw 'No primary display is available for the test windows.' }

    foreach ($display in $displays) {
        $halfWidth = [math]::Floor($display.WorkWidth / 2)
        $frameAllowance = 8
        $titles = @(
            "HaySpace split-left $suffix $($display.DeviceName)"
            "HaySpace split-right $suffix $($display.DeviceName)"
        )
        $bounds = @(
            @{
                X = $display.WorkX - $frameAllowance
                Y = $display.WorkY - $frameAllowance
                Width = $halfWidth + ($frameAllowance * 2)
                Height = $display.WorkHeight + ($frameAllowance * 2)
                ResetX = $display.WorkX + 80
                ResetY = $display.WorkY + 80
            }
            @{
                X = $display.WorkX + $halfWidth - $frameAllowance
                Y = $display.WorkY - $frameAllowance
                Width = $display.WorkWidth - $halfWidth + ($frameAllowance * 2)
                Height = $display.WorkHeight + ($frameAllowance * 2)
                ResetX = $display.WorkX + 80
                ResetY = $display.WorkY + 80
            }
        )
        for ($index = 0; $index -lt 2; $index++) {
            $form = New-Object System.Windows.Forms.Form
            $form.Text = $titles[$index]
            $form.StartPosition = 'Manual'
            $form.Width = 500
            $form.Height = 400
            $form.Location = New-Object System.Drawing.Point ($display.WorkX + 80), ($display.WorkY + 80)
            $form.Show()
            $forms += $form
            $windowTitles += $titles[$index]
            $requestedBounds[$titles[$index]] = $bounds[$index]
        }
    }
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 100

    $windows = [HaySpace.NativeWindow]::GetWindows()
    foreach ($title in $windowTitles) {
        $window = $windows | Where-Object Title -eq $title | Select-Object -First 1
        if (-not $window) { throw "Could not enumerate test window '$title'." }
        $bounds = $requestedBounds[$title]
        if (-not [HaySpace.NativeWindow]::Move($window.Handle, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height, 0)) {
            throw "Could not position test window '$title'."
        }
    }

    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 250
    $windows = [HaySpace.NativeWindow]::GetWindows()
    foreach ($title in $windowTitles) {
        $window = $windows | Where-Object Title -eq $title | Select-Object -First 1
        $capturedBounds[$title] = @{
            X = $window.X
            Y = $window.Y
            Width = $window.Width
            Height = $window.Height
        }
    }

    $capture = New-HaySpaceCapture -ProfileName 'Window placement accuracy regression' -ProfileType 'Quick Layout'
    foreach ($title in $windowTitles) {
        $captured = $capture.Windows | Where-Object Title -eq $title | Select-Object -First 1
        if (-not $captured) { throw "Capture did not include test window '$title'." }
        foreach ($dimension in @('X', 'Y', 'Width', 'Height')) {
            if ([math]::Abs([double]$captured.$dimension - [double]$capturedBounds[$title][$dimension]) -gt 1) {
                throw "Capture changed '$title' $dimension on its display: expected $($capturedBounds[$title][$dimension]), got $($captured.$dimension)."
            }
        }
    }

    $profile = [pscustomobject]@{
        ProfileName = 'Window placement accuracy regression'
        ProfileType = 'Quick Layout'
        BrowserMode = 'Ignore'
        Applications = @()
        ExplorerFolders = @()
        RdpFiles = @()
        Windows = @($capture.Windows | Where-Object { $windowTitles -contains $_.Title })
        Urls = @()
    }
    $currentWindows = [HaySpace.NativeWindow]::GetWindows()
    foreach ($window in $profile.Windows) {
        $current = $currentWindows | Where-Object Title -eq $window.Title | Select-Object -First 1
        $resetBounds = $requestedBounds[$window.Title]
        if (-not $current -or -not [HaySpace.NativeWindow]::Move($current.Handle, $resetBounds.ResetX, $resetBounds.ResetY, 500, 400, 0)) {
            throw "Could not move test window '$($window.Title)' away from its captured bounds."
        }
    }
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 100
    $null = Restore-HaySpaceWorkspace -Profile $profile
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 100

    $restoredWindows = [HaySpace.NativeWindow]::GetWindows()
    foreach ($title in $windowTitles) {
        $restored = $restoredWindows | Where-Object Title -eq $title | Select-Object -First 1
        if (-not $restored) { throw "Restore lost test window '$title'." }
        foreach ($dimension in @('X', 'Y', 'Width', 'Height')) {
            if ([math]::Abs([double]$restored.$dimension - [double]$capturedBounds[$title][$dimension]) -gt 1) {
                $target = $profile.Windows | Where-Object Title -eq $title | Select-Object -First 1
                throw "Restore changed '$title' ${dimension}: expected $($capturedBounds[$title][$dimension]), got $($restored.$dimension); display '$($target.DisplayName)' ($($target.DeviceName)), relative x=$($target.RelativeX), work area origin=$($target.X - ($target.RelativeX * $target.Width / $target.RelativeWidth))."
            }
        }
    }

    $maximizeTarget = $profile.Windows | Where-Object Title -eq $windowTitles[0] | Select-Object -First 1
    $maximizeTarget.State = 'Maximized'
    $null = Restore-HaySpaceWorkspace -Profile $profile
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 100
    $maximizedWindow = [HaySpace.NativeWindow]::GetWindows() | Where-Object Title -eq $maximizeTarget.Title | Select-Object -First 1
    $maximizedCenterX = $maximizedWindow.X + ($maximizedWindow.Width / 2)
    $maximizedCenterY = $maximizedWindow.Y + ($maximizedWindow.Height / 2)
    $maximizedOnTarget = $maximizedCenterX -ge $displays[0].X -and
        $maximizedCenterX -lt ($displays[0].X + $displays[0].Width) -and
        $maximizedCenterY -ge $displays[0].Y -and
        $maximizedCenterY -lt ($displays[0].Y + $displays[0].Height)
    $frameAllowance = 32
    $fillsWorkArea = [math]::Abs($maximizedWindow.X - $displays[0].WorkX) -le $frameAllowance -and
        [math]::Abs($maximizedWindow.Y - $displays[0].WorkY) -le $frameAllowance -and
        [math]::Abs(($maximizedWindow.X + $maximizedWindow.Width) - ($displays[0].WorkX + $displays[0].WorkWidth)) -le $frameAllowance -and
        [math]::Abs(($maximizedWindow.Y + $maximizedWindow.Height) - ($displays[0].WorkY + $displays[0].WorkHeight)) -le $frameAllowance
    if (-not $maximizedWindow.Maximized -or -not $maximizedOnTarget -or -not $fillsWorkArea) {
        throw "Maximized restore did not fill the target display '$($maximizeTarget.DeviceName)' for '$($maximizeTarget.Title)'."
    }

    Write-Output 'Split-window bounds, frame offsets, and maximized work-area bounds restore correctly on the primary display.'
}
finally {
    foreach ($form in $forms) {
        $form.Close()
        $form.Dispose()
    }
    [HaySpace.NativeWindow]::RestoreDpiAwarenessContext($previousDpiContext)
}
