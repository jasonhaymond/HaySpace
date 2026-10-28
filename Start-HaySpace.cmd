@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
    start "" powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "%~dp0HaySpace.ps1"
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0HaySpace.ps1" %*
)
