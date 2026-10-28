param(
    [switch]$Child,
    [string]$TestScriptPath,
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'Modules\Workspace.psm1') -Force

if (-not $Child) {
    $TestScriptPath = Join-Path $env:TEMP ('HaySpace-console-test-' + [guid]::NewGuid().ToString('N') + '.vbs')
    $ResultPath = Join-Path $env:TEMP ('HaySpace-console-test-' + [guid]::NewGuid().ToString('N') + '.json')
    $errorPath = Join-Path $env:TEMP ('HaySpace-console-test-' + [guid]::NewGuid().ToString('N') + '.err')
    Set-Content -LiteralPath $TestScriptPath -Value 'WScript.Sleep 12000' -Encoding ASCII
    try {
        $powerShellPath = Join-Path $PSHOME 'powershell.exe'
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Child -TestScriptPath "{1}" -ResultPath "{2}"' -f $PSCommandPath, $TestScriptPath, $ResultPath
        $launcher = Start-Process -FilePath $powerShellPath -ArgumentList $arguments -PassThru `
            -RedirectStandardError $errorPath
        Wait-Process -Id $launcher.Id

        if (-not (Test-Path -LiteralPath $ResultPath)) {
            $details = if (Test-Path -LiteralPath $errorPath) { Get-Content -LiteralPath $errorPath -Raw } else { '' }
            throw "The detached launcher did not report console status. $details"
        }

        $result = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
        $childProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($result.ProcessId)" -ErrorAction SilentlyContinue
        if (-not $childProcess) {
            throw "The application exited after its PowerShell launcher ($($launcher.Id)) closed."
        }
        if ($childProcess.ExecutablePath -ne (Join-Path $env:WINDIR 'System32\wscript.exe') -or $childProcess.CommandLine -notmatch [regex]::Escape($TestScriptPath)) {
            throw "PID $($result.ProcessId) does not match the launched test application."
        }
        if ($result.ConsoleAttachSucceeded) {
            throw "The application shares a console with its launcher: $($result.ConsoleProcessIds -join ', ')."
        }
        if ([int]$result.ConsoleAttachError -ne 6) {
            throw "Unable to verify that the application has no console (Win32 error $($result.ConsoleAttachError))."
        }

        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($childProcess.ParentProcessId)" -ErrorAction SilentlyContinue
        if ($parent.Name -ne 'explorer.exe') {
            throw "The application was not launched by Explorer as expected (parent: $($parent.Name))."
        }

        Write-Output "PASS: application PID $($result.ProcessId) remained alive after launcher PID $($launcher.Id) exited, has no console, and is parented by Explorer."
        Wait-Process -Id $result.ProcessId -Timeout 15 -ErrorAction Stop
    }
    finally {
        Remove-Item -LiteralPath $TestScriptPath, $ResultPath, $errorPath -Force -ErrorAction SilentlyContinue
    }
    return
}

$consoleProbe = @'
using System;
using System.Runtime.InteropServices;
public static class HaySpaceConsoleProbe {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool AttachConsole(uint processId);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint GetConsoleProcessList(uint[] processList, uint processCount);
}
'@
Add-Type -TypeDefinition $consoleProbe
$null = & (Get-Module Workspace) {
    param($Path, $Arguments, $WorkingDirectory)
    Start-HaySpaceApplication -FilePath $Path -Arguments $Arguments -WorkingDirectory $WorkingDirectory
} (Join-Path $env:WINDIR 'System32\wscript.exe') ('"' + $TestScriptPath + '"') $env:TEMP

$deadline = (Get-Date).AddSeconds(10)
$process = $null
do {
    $process = Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" |
        Where-Object { $_.ExecutablePath -eq (Join-Path $env:WINDIR 'System32\wscript.exe') -and $_.CommandLine -match [regex]::Escape($TestScriptPath) } |
        Select-Object -First 1
    if ($process) { break }
    Start-Sleep -Milliseconds 100
} while ((Get-Date) -lt $deadline)
if (-not $process) { throw 'Explorer did not start the test application.' }

[void][HaySpaceConsoleProbe]::FreeConsole()
$attached = [HaySpaceConsoleProbe]::AttachConsole([uint32]$process.ProcessId)
$attachError = if ($attached) { 0 } else { [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
$consoleProcessIds = @()
if ($attached) {
    $processIds = New-Object 'uint32[]' 32
    $count = [HaySpaceConsoleProbe]::GetConsoleProcessList($processIds, [uint32]$processIds.Length)
    if ($count -gt 0) { $consoleProcessIds = @($processIds[0..([int]$count - 1)]) }
    [void][HaySpaceConsoleProbe]::FreeConsole()
}

$parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($process.ParentProcessId)" -ErrorAction SilentlyContinue
$result = [pscustomobject]@{
    ProcessId = $process.ProcessId
    ParentProcessId = $process.ParentProcessId
    ParentProcessName = $parent.Name
    ConsoleAttachSucceeded = $attached
    ConsoleAttachError = $attachError
    ConsoleProcessIds = $consoleProcessIds
}
[IO.File]::WriteAllText($ResultPath, (ConvertTo-Json -InputObject $result -Compress))
