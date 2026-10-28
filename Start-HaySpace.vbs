Option Explicit

Dim shell, fileSystem, scriptPath, powerShellPath, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptPath = fileSystem.BuildPath(fileSystem.GetParentFolderName(WScript.ScriptFullName), "HaySpace.ps1")
powerShellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
command = """" & powerShellPath & """ -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File """ & scriptPath & """ -AutoLoadProfile -Tray"
shell.Run command, 0, False
