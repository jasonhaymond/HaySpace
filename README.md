# HaySpace

HaySpace is a portable Windows workspace utility for saving application-window layouts and restoring them on the current or a replacement set of displays. It uses PowerShell 5.1 and WPF and stores its profiles and settings locally beside the application.

## Run

1. Extract or copy the folder to a location writable by your account.
2. Double-click `Start-HaySpace.cmd`.
3. Optionally run `Start-HaySpace.cmd -Capture` for command-line capture or `Start-HaySpace.cmd -LoadProfile "Profile Name"` to restore a profile.

No installer or external service is required. The launcher uses the current user's built-in Windows PowerShell. Windows may show an execution-policy prompt in managed environments; follow your organization's policy rather than changing system policy.

## Current capabilities

- Capture visible, standard desktop windows and their process, title, size, state, and display-relative position.
- Save and edit JSON profiles, including applications, launch arguments/order, launch toggles, window placement/state/display, URLs, Explorer folders, RDP files, and profile hotkeys.
- Restore matching windows and optionally start missing applications when their original executable path is still available.
- Remap to connected displays using saved friendly display names, with a primary-display fallback.
- Use a visual drag/resize layout designer, selective capture filters, configurable Ctrl+Alt hotkeys, and a migration assistant for display/application path remapping.
- Rename connected displays; create desktop or taskbar profile shortcuts; create and restore local ZIP backups.
- Minimize the dashboard to the notification area; use its menu to load saved profiles.
- Start at user logon, automatically matching saved workspaces to connected display layouts and remembering profile choices per layout.
- Create desktop and taskbar shortcuts for the HaySpace launcher as well as profile-specific shortcuts.
- Run portably with local-only data and rotating local logs.

Profiles, settings, logs, backups, shortcuts, and connection files are local runtime data and are excluded from Git by `.gitignore`.

## Important limitations

- Window management requires an interactive Windows desktop. Elevated or protected applications may not expose process paths or allow positioning.
- Browser URL opening is supported. Session restoration requests the browser's restore-last-session behavior and depends on browser settings; active-tab URL capture and tab-level restoration are not available through standard Windows window APIs.
- New profiles default to launching applications normally and do not open browser URLs or request browser sessions unless the browser mode is changed.
- RDP files must be added to a profile manually; HaySpace captures the RDP client window but cannot reliably infer which connection file opened it.
- Friendly monitor names are stored against Windows display device names on this computer. When those names are unavailable elsewhere, restoration uses the primary display.
- Profile applications store their executable path but not command-line arguments captured from a running process.

See [UserGuide.md](./UserGuide.md) for daily use and [Roadmap.md](./Roadmap.md) for planned work.
