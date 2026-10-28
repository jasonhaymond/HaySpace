# HaySpace User Guide

## Start the application

Run `Start-HaySpace.cmd`. The dashboard opens and a HaySpace icon appears in the notification area. Closing the dashboard hides it; choose **Exit** from the tray menu to end the application.

## Capture a workspace

Arrange application windows as desired, then select **Capture workspace**. Choose whether to exclude browser/Explorer windows and enter process names to exclude. Enter a profile name and choose Quick Layout, Workspace Layout, or Full Workspace.

- **Quick Layout** saves the current window arrangement without application launch entries.
- **Workspace Layout** and **Full Workspace** save application launch paths as well as window placements.
- Add web addresses in the profile editor, one per line. Only HTTP and HTTPS addresses should be used.

Capture includes visible windows with usable dimensions. Explorer folder paths are captured when Windows exposes them. Some elevated, protected, or transient windows may not be capturable.

When a browser window is included, HaySpace attempts to read its active address bar through Windows UI Automation and save an HTTP(S) URL. This is best-effort and varies by browser and window state.

## Load and manage profiles

Select a profile and use **Load workspace**. Existing windows are matched by process name and title. If a matching window is not found, its saved executable may be started when the profile type allows launching. Restoration waits briefly for windows and places them on the matching friendly display, then saved device name, then the primary display.

Use **New**, **Edit**, **Clone**, **Delete**, **Export profile**, and **Import profile** to manage profiles. In **Edit**, add an executable with **Add application**, remove the selected row, change its executable path, launch order or optional arguments, and choose whether it launches. Removing an app also removes its saved window placements. Edit placement, size, display and state in the **Window placements** table or open **Visual designer** to drag and resize window cards across monitor representations. Blank arguments launch an app normally. An app without a captured window has no saved placement. Browser mode defaults to **Ignore**; **URL** opens saved URLs, **Session** requests the browser's last-session behavior, and **Hybrid** opens saved URLs only when a supported browser is not already running. Browser session handling is best-effort and depends on browser settings. Add RDP connection files under **Remote Desktop files**. Configure a profile hotkey by focusing its hotkey field and pressing Ctrl+Alt plus a supported letter, number, or F1-F12 key. Use **Create desktop shortcut** to create a profile launcher, or **Add to taskbar** to ask Windows to pin it. If Windows does not offer taskbar pinning, HaySpace creates and selects the shortcut in File Explorer so you can pin it manually if supported. Use **Refresh** above the profile list after external JSON edits.

The tray menu provides shortcuts to load profiles while the dashboard is hidden.

## Manage displays

Open the **Displays** tab and select **Refresh** to enumerate currently connected screens. Select a screen and choose **Rename selected** or **Test selected**. Names are saved locally and used to match displays when restoring. Use **Migration assistant** on a profile to map its saved displays to this computer and update unavailable application or Explorer folder paths.

If a profile's display is missing, HaySpace falls back to the primary display and keeps the window within the display's usable work area.

## Back up or restore

Use **Backup** to create a ZIP containing profiles, settings, and generated shortcuts. Use **Restore backup** to restore an archive; confirm before the local profiles, settings, and shortcuts folders are replaced. Store backups in a location of your choosing.

For manual migration, copy the complete HaySpace folder or use a backup archive. Review executable paths and display names on the destination computer before loading migrated profiles.

## Local data

- `Profiles`: profile JSON files
- `Settings`: friendly display names and application settings
- `Shortcuts`: generated profile launch shortcuts
- `Backups`: reserved for user-managed backups
- `Logs`: local daily log files, rotated after 30 days

HaySpace does not send telemetry or upload data.
