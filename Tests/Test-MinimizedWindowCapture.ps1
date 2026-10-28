$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'Modules\Storage.psm1') -Force
Import-Module (Join-Path $root 'Modules\Workspace.psm1') -Force
$null = Initialize-HaySpaceStorage
Add-Type -AssemblyName System.Windows.Forms

$title = 'HaySpace Minimized Capture Test ' + [guid]::NewGuid().ToString('N')
$form = New-Object System.Windows.Forms.Form
$form.Text = $title
$form.StartPosition = 'Manual'
$form.Width = 800
$form.Height = 600

try {
    $display = Get-HaySpaceDisplays | Where-Object Primary | Select-Object -First 1
    if (-not $display) { throw 'No primary display is available for the test window.' }
    $form.Location = New-Object System.Drawing.Point ($display.WorkX + 80), ($display.WorkY + 80)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()

    $before = [HaySpace.NativeWindow]::GetWindows() | Where-Object Title -eq $title | Select-Object -First 1
    if (-not $before) { throw 'The test window was not found before minimizing.' }

    $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 200

    $capture = New-HaySpaceCapture -ProfileName 'Minimized capture regression' -ProfileType 'Quick Layout'
    $captured = $capture.Windows | Where-Object { $_.Title -eq $title } | Select-Object -First 1
    if (-not $captured) { throw 'The minimized test window was not included in the capture.' }
    if ($captured.State -ne 'Minimized') { throw "Expected minimized state; got '$($captured.State)'." }

    foreach ($dimension in @('X', 'Y', 'Width', 'Height')) {
        if ([math]::Abs([double]$captured.$dimension - [double]$before.$dimension) -gt 2) {
            throw "Captured $dimension did not preserve the restored window bounds."
        }
    }

    Write-Output 'Minimized window capture preserves the window and its restored bounds.'
}
finally {
    $form.Close()
    $form.Dispose()
}
