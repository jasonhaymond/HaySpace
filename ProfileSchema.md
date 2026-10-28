# HaySpace Profile Schema

Profiles are UTF-8 JSON files stored in `Profiles` and currently use schema version `1.0`. HaySpace tolerates unknown fields to support forward-compatible edits.

| Property | Type | Description |
|---|---|---|
| `ProfileName` | string | User-facing name and profile filename. |
| `ProfileType` | string | `Quick Layout`, `Workspace Layout`, or `Full Workspace`. |
| `Version` | string | Schema version; currently `1.0`. |
| `CreatedAt`, `UpdatedAt` | string | ISO 8601 timestamps. |
| `ComputerName` | string | Machine on which the profile was captured. |
| `BrowserMode` | string | `Ignore`, `URL`, `Session`, or `Hybrid`. New profiles default to `Ignore`. `URL` opens saved addresses, `Session` requests browser last-session restoration, and `Hybrid` opens saved addresses only when no supported browser is running. Browser URL capture and session restoration are best-effort. |
| `Applications` | array | Process name/path, optional arguments, launch flag, and launch order. |
| `Windows` | array | Window title, process name/path, display, rectangle, relative work-area rectangle, and state. |
| `Urls` | array of strings | HTTP or HTTPS addresses opened on load for URL/Hybrid modes. |
| `ExplorerFolders` | array | Captured local Explorer folders with window placement and display metadata. |
| `RdpFiles` | array of strings | Optional `.rdp` files to open with Remote Desktop Connection during restore. |
| `Hotkey` | string | Optional profile activation chord in `Ctrl+Alt+key` form. |
| `Displays` | array | Captured display device, friendly name, bounds, and work area. |
| `LaunchDelaySeconds` | number | Reserved launch timing metadata. |

Window state values are `Normal`, `Maximized`, and `Minimized`. Relative coordinates are normalized to the display work area and allow layouts to adapt to a different resolution. On display mismatch, HaySpace first uses a saved migration mapping, then the friendly name, then the saved Windows device name, then the primary display.

Each Explorer folder entry stores `Path` and its saved window title, display, rectangle, relative work-area rectangle, and state. Each window entry may include `FolderPath`. Settings also store `DisplayMappings`, which map a saved friendly name to a current Windows display device name, and may be updated using the migration assistant.

Example:

```json
{
  "ProfileName": "HelpDesk",
  "ProfileType": "Full Workspace",
  "Version": "1.0",
  "BrowserMode": "Ignore",
  "Applications": [
    {
      "ProcessName": "notepad",
      "ProcessPath": "C:\\Windows\\System32\\notepad.exe",
      "Arguments": "",
      "Launch": true,
      "LaunchOrder": 0
    }
  ],
  "Windows": [
    {
      "Title": "Notes - Notepad",
      "ProcessName": "notepad",
      "ProcessPath": "C:\\Windows\\System32\\notepad.exe",
      "DisplayName": "\\\\.\\DISPLAY1",
      "DeviceName": "\\\\.\\DISPLAY1",
      "X": 100,
      "Y": 100,
      "Width": 900,
      "Height": 700,
      "RelativeX": 0.05,
      "RelativeY": 0.05,
      "RelativeWidth": 0.7,
      "RelativeHeight": 0.7,
      "State": "Normal"
    }
  ],
  "Urls": [],
  "ExplorerFolders": [],
  "Displays": []
}
```

Treat imported profiles as executable configuration: loading one can start the executable paths listed in `Applications`.
