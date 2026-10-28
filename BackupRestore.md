# Backup and Restore

## Create a backup

In the HaySpace dashboard, choose **Backup** and select a ZIP destination. The archive contains `Profiles`, `Settings`, `Shortcuts`, and a `manifest.json`. Logs and transient runtime data are intentionally excluded.

## Restore a backup

Choose **Restore backup**, select a HaySpace ZIP, and confirm the operation. HaySpace validates the archive manifest before restoring the listed data folders. Existing `Profiles`, `Settings`, and `Shortcuts` folders in the backup are replaced as a unit; a rollback copy is retained temporarily until the restore succeeds. Back up the current HaySpace directory first if you need to preserve the pre-restore state.

The archive is local and is not encrypted. Protect it as you would the original profiles, which may contain local paths and workspace URLs.

## Migrate to another computer

1. Create a backup, or copy the entire HaySpace folder.
2. Place the application in a writable folder on the destination Windows computer.
3. Restore the backup if using an archive.
4. Open the **Displays** tab and assign friendly names to connected displays.
5. Edit profiles to update missing executable paths and URLs.
6. Load one profile and confirm the workspace before relying on it.

When a saved display is unavailable, HaySpace uses the primary display. A saved executable is started only if its path exists on the new computer.
