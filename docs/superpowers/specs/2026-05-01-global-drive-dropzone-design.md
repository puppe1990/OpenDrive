# Global Drive Dropzone Design

## Goal

Replace the current upload card in the Drive view with a global drag-and-drop target that covers the full authenticated app shell. When files are dragged over the app, the UI should show an orange blurred overlay that clearly communicates the pending drop state.

## Scope

- Remove the large upload hero block from the Drive main content.
- Keep the hidden file input, upload queue, and upload error surfaces.
- Move the `DirectUploadZone` hook from the upload card to the top-level authenticated app container for the Drive screen.
- Show a full-screen overlay during drag-over, including header, sidebar, breadcrumbs, filters, and file grid/list.
- Use orange as the active drop feedback color, with blur and a clear “drop now” message.

## UX Design

### Resting state

- The Drive page should no longer show the standalone upload card.
- The page layout starts with the upload queue/errors when present, then breadcrumbs, filters, and entries.
- Clicking to choose files should still be available through the hidden file input, but the visible emphasis shifts from a dedicated upload panel to drag-and-drop across the whole screen.

### Drag-over state

- A fixed overlay appears above the whole Drive app shell.
- The overlay uses a translucent orange wash plus backdrop blur so the underlying interface remains visible but clearly inactive.
- A centered drop message indicates the target folder context, such as “Drop files to upload to this folder”.
- The overlay disappears as soon as drag leaves the app shell or a drop happens.

### Drop behavior

- Dropping files anywhere inside the app shell triggers the existing upload flow.
- Dropping a folder still preserves internal structure through the current `DirectUploadZone` logic.
- Once dropped, the overlay clears immediately and the upload queue becomes the active feedback surface.

## Implementation Plan

### Template changes

- Update `lib/open_drive_web/live/drive_live/components.ex`.
- Remove the visible upload hero block.
- Keep the hidden file input and queue/error markup.
- Add a full-screen overlay node inside the Drive root that can be toggled by the hook.
- Attach `phx-hook="DirectUploadZone"` and its upload dataset attributes to the outermost Drive app shell instead of the old upload card container.

### Hook changes

- Update `assets/js/app.js` in `DirectUploadZone`.
- Switch drag state styling from mutating the old card classes to toggling a dedicated global “drag active” state on the root container and overlay.
- Make drag enter/leave handling robust for nested descendants so the overlay does not flicker while moving across sidebar, header, or content regions.
- Preserve the current queue, cancel/retry, and folder-preserving upload behavior.

### Testing

- Update `test/open_drive_web/live/drive_live/index_test.exs` to stop asserting the removed upload hero copy.
- Add assertions for the new global dropzone markup and overlay container presence.
- Re-run the focused Drive LiveView test file after implementation.

## Risks

- Global dragenter/dragleave can flicker if descendant transitions are not normalized.
- Moving the hook higher in the DOM can accidentally interfere with clicks if the overlay remains active after drop.
- Removing the hero block reduces visible discoverability for click-to-upload, so the remaining trigger path must stay accessible.

## Acceptance Criteria

- The upload hero block is gone from the Drive page.
- Dragging files over any visible part of the authenticated Drive screen activates a full-screen orange blurred overlay.
- Dropping files anywhere inside that screen starts the existing upload flow.
- Upload queue, cancel/retry behavior, and folder structure preservation continue to work.
