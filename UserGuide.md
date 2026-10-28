# HaySpace User Guide

## Start the application

Run `Start-HaySpace.cmd`. The dashboard opens and a HaySpace icon appears in the notification area. Closing the dashboard hides it; choose **Restart HaySpace** from the tray menu or the Settings tab to restart the app. Choose **Exit** from the tray menu to end the application.

## Capture a workspace

Arrange application windows as desired, then select **Capture workspace**. Choose whether to exclude browser/Explorer windows and enter process names to exclude. Enter a profile name and choose Quick Layout, Workspace Layout, or Full Workspace.

- **Quick Layout** saves the current window arrangement without application launch entries.
- **Workspace Layout** and **Full Workspace** save application launch paths as well as window placements.
- Add web addresses in the profile editor, one per line. Only HTTP and HTTPS addresses should be used.

Capture includes visible and minimized windows with usable restored dimensions, and preserves minimized state. Window bounds use physical pixels across DPI-scaled displays and retain the small frame offsets used by snapped windows. Explorer folder paths are captured when Windows exposes them. Some elevated, protected, or transient windows may not be capturable.

When a browser window is included, HaySpace attempts to read its active address bar through Windows UI Automation and save an HTTP(S) URL. This is best-effort and varies by browser and window state.

## Load and manage profiles

Select a profile and use **Load workspace**. Existing windows are matched by process name and title. If a matching window is not found, its saved executable may be started without inheriting HaySpace's console when the profile type allows launching. This keeps applications such as VS Code independent from HaySpace's PowerShell window. For Microsoft Teams, HaySpace checks for a running process even when its interface is hidden in the tray, then activates the registered Teams app to open its interface. Browser launch detection checks for visible windows rather than background browser processes, so an Edge background process does not prevent HaySpace from opening a window. After launching apps, HaySpace waits up to 45 seconds only for windows belonging to apps it launched that have not yet been arranged; already-open or already-arranged windows do not keep the timer running. Maximized windows are maximized on the target display rather than left at their previous or nearly-full-screen size. Restoration uses the matching friendly display, then saved device name, then the primary display.

Use **New**, **Edit**, **Clone**, **Delete**, **Export profile**, and **Import profile** to manage profiles. Profile exports default to a filename with a sortable date-and-time suffix. In **Edit**, add an executable with **Add application**, or choose a packaged/Store app with **Add installed app**. Installed apps launch through their Windows app identity, so HaySpace does not need access to protected `WindowsApps` folders. The app's process name is used to match saved window placements; the editor tries to identify it from captured windows and lets you choose or enter it. Remove the selected row, change its executable path, launch order or optional arguments, and choose whether it launches. Removing an app also removes its saved window placements. Edit placement, size, display and state in the **Window placements** table or open **Visual designer** to drag and resize window cards across monitor representations. Blank arguments launch an app normally. An app without a captured window has no saved placement. Browser mode defaults to **Ignore**; **URL** opens saved URLs, **Session** requests the browser's last-session behavior, and **Hybrid** opens saved URLs only when a supported browser is not already running. Browser session handling is best-effort and depends on browser settings. Add RDP connection files under **Remote Desktop files**. Configure a profile hotkey by focusing its hotkey field and pressing Ctrl+Alt plus a supported letter, number, or F1-F12 key. Use **Create desktop shortcut** to create a profile launcher, or **Add to taskbar** to ask Windows to pin it. If Windows does not expose native pinning, HaySpace adds the shortcut under **Start > All apps > HaySpace Profiles** and gives instructions for pinning it from there if Windows allows it. Use **Refresh** above the profile list after external JSON edits.

Launch arguments apply to executable-based entries; packaged apps use their registered Windows activation.

The tray menu provides shortcuts to load profiles while the dashboard is hidden. Starting HaySpace again while its dashboard or tray icon is already running does not launch a second instance; exit from the tray menu before restarting.

## Start with Windows and match display layouts

In **Settings**, enable **Run at user logon and load a workspace for connected displays**. HaySpace starts minimized to the notification area when you sign in. The logon registration uses a hidden Windows Script Host launcher so no PowerShell console appears during startup. HaySpace identifies the connected layout using display names, count, resolution, primary-display status, and relative arrangement. If exactly one saved profile matches, HaySpace loads it automatically. If there is no exact match or several profiles match, choose a profile in the startup chooser; HaySpace remembers that selection for this display layout and uses it on future logons. To choose or change the default manually, select a profile and use **Set default for displays**; this replaces the saved choice for the currently connected layout. Cancel the startup chooser to leave the workspace unchanged. Turn the setting off to remove HaySpace from this user's logon startup.

Use **Create HaySpace desktop shortcut** or **Add HaySpace to taskbar** to launch the general HaySpace dashboard instead of a specific profile. If Windows does not expose native taskbar pinning, the shortcut is added under **Start > All apps > HaySpace**; search for HaySpace there and pin it if Windows offers that option.

## Manage displays

Open the **Displays** tab and select **Refresh** to enumerate currently connected screens. Select a screen and choose **Rename selected** or **Test selected**. Names are saved locally and used to match displays when restoring. In a profile's **Migration assistant**, use **Identify** beside a display mapping to show its name, resolution, and Windows device name on that monitor before choosing it. The assistant can also update unavailable application or Explorer folder paths.

If a profile's display is missing, HaySpace falls back to the primary display and keeps the window within the display's usable work area.

## Back up or restore

Use **Backup** to create a ZIP containing profiles, settings, and generated shortcuts. The backup dialog defaults to a filename with a sortable date-and-time suffix. Use **Restore backup** to restore an archive; confirm before the local profiles, settings, and shortcuts folders are replaced. Store backups in a location of your choosing.

For manual migration, copy the complete HaySpace folder or use a backup archive. Review executable paths and display names on the destination computer before loading migrated profiles.

## Local data

- `Profiles`: profile JSON files
- `Settings`: friendly display names and application settings
- `Shortcuts`: generated profile launch shortcuts
- `Backups`: reserved for user-managed backups
- `Logs`: local daily log files, rotated after 30 days

HaySpace does not send telemetry or upload data.
