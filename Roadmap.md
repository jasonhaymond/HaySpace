# HaySpace Roadmap

## 1.0 foundation

- Portable Windows PowerShell/WPF dashboard
- JSON profile storage and basic profile lifecycle
- Visible top-level window capture and display-relative restore
- Display friendly names and primary-display fallback
- Application launch from saved executable paths
- URL opening, local ZIP backup/import, profile shortcuts, and tray menu

## Implemented in the current development build

- Selective capture controls for browsers, Explorer, and process names
- Editable window position, size, state, and display; drag/resize/snap visual layout designer
- Explorer folder capture/restore and configurable RDP file launching
- Per-profile Ctrl+Alt hotkey registration and display/application migration assistant
- Display test overlay and persisted display remapping
- Best-effort active browser URL capture and browser session-restore requests

## Remaining 1.0 scope

- More reliable browser URL and session integrations across browser configurations
- Display hardware manufacturer/model/serial identity where Windows exposes stable values
- Automated end-to-end coverage across monitor topologies, browser configurations, and interactive designer workflows
- Packaged Windows application/installer (excluded from the current work)

## Deferred beyond 1.0

- Automatic profile switching
- Virtual Desktop support
- Cloud synchronization and shared repositories
- Multi-user profiles, Teams integration, PowerShell tab restoration, plugins, updates, AI recommendations, and enterprise deployment tooling
