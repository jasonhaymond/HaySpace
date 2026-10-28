# Display Mapping

HaySpace enumerates active displays through Windows Forms and records device name, friendly name, resolution, screen position, and work area. The work area excludes taskbars and other reserved desktop space.

Friendly names are editable in the dashboard's **Displays** tab. They are stored in `Settings/settings.json` keyed by the Windows device name and included in full backups.

During restore, a saved window is assigned to a currently connected display by:

1. Matching its saved friendly display name.
2. Matching its saved Windows device name.
3. Falling back to the primary display (or first available display).

Window size and location are scaled against the destination display's work area and clamped so the window remains visible. This makes layouts more resilient to different resolutions; it does not infer a physical monitor's manufacturer, model, serial number, or hardware identity.

On a new computer, rename the connected screens as needed and verify profile placements. Device names and friendly mappings are local to the Windows environment and may not transfer exactly.
