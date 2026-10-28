# Developer Guide

## Runtime and layout

HaySpace is a portable Windows PowerShell 5.1 and WPF application.

- `HaySpace.ps1`: application entry point and dashboard event wiring
- `UI/MainWindow.xaml`: WPF dashboard
- `Modules/Storage.psm1`: settings, profile persistence, logs, backup import/export
- `Modules/Workspace.psm1`: Windows interop, display discovery, Explorer window capture, and workspace restore
- `Modules/Shortcuts.psm1`: generated profile shortcuts
- `Profiles`, `Settings`, `Shortcuts`, `Backups`, and `Logs`: local data folders created on first run

The native window APIs are declared in C# via `Add-Type` at runtime. No external packages or services are required.

## Development

Run `Start-HaySpace.cmd` from Windows to launch the GUI. A normal double-click starts the WPF app in a hidden PowerShell host and the command window exits immediately. When arguments are supplied, the launcher keeps the console attached for command-line use. For a profile load from the command line:

```powershell
.\Start-HaySpace.cmd -LoadProfile "HelpDesk"
```

Capture from the command line with:

```powershell
.\Start-HaySpace.cmd -Capture
```

Before sharing changes, parse-check all PowerShell files with `System.Management.Automation.Language.Parser` and validate that `UI/MainWindow.xaml` is well-formed XML. Verify capture, profile save/edit, load with and without a running process, display fallback, and backup round-trip on an interactive Windows desktop.

## Data and safety

Profile files are local JSON and may launch saved executable paths when a profile is loaded. Validate URLs as HTTP(S) and paths as local files before starting them. Keep backup import local and validate archives before copying data. HaySpace has no telemetry or network service.

## Current implementation boundaries

The capture engine handles visible top-level windows with standard Win32 rectangles. Protected processes may hide their executable path or prevent window movement. Explorer folder discovery relies on the local Shell COM interface. Browser active-tab URL capture is not available; browser session restore is best effort and depends on profile launch settings and browser configuration. See `Roadmap.md` for work still remaining.
