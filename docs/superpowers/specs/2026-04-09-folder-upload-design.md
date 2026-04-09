# Folder Upload Design

## Goal

Allow dragging a folder onto the drive dropzone while preserving its internal tree by creating subfolders automatically inside the current folder, including empty subfolders.

## User-visible behavior

- Dragging a folder onto the dropzone starts a folder upload instead of failing.
- The upload preserves the original relative paths under the current drive folder.
- Empty subfolders are created even if they contain no files.
- If a dropped folder or nested subfolder conflicts with an existing sibling folder name, the app creates a new sibling using the same suffixing rule already used for file uploads, for example `Photos (2)`.
- File conflicts continue to use the existing auto-rename behavior.
- The queue continues to track file uploads individually.
- If the browser exposes plain files plus directories in one drop, the app uploads the files and also recreates the folder tree for the directories.
- If the browser does not expose directory traversal APIs, the app keeps the current explicit error.

## Recommended approach

Expand the dropped directory tree in the browser, build a client-side upload plan, create the target folders first, then upload each file with the resolved `folder_id`.

This keeps tenant and folder scoping on the server exactly where it already lives. It also avoids designing a second upload protocol or changing the storage abstraction.

## Architecture

### Frontend

The `DirectUploadZone` hook in `assets/js/app.js` becomes responsible for two drop paths:

- plain file drop: keep current behavior
- directory drop: walk entries recursively, build a tree plan, create folders, then upload files

The hook will:

1. inspect `DataTransferItem`s and detect directory entries with `webkitGetAsEntry()` or `getAsEntry()`
2. recursively enumerate files and directories
3. record each directory by relative path, including empty ones
4. create folders in depth order so parents exist before children
5. resolve conflicts by asking the backend to create folders and accepting the final returned name and id
6. upload files with the final `folder_id` for each relative path

### Backend

The backend needs one folder-creation path that is safe to call programmatically and returns the created folder record. The simplest option is a small authenticated controller endpoint that delegates to `Drive.create_folder/2`.

That endpoint must:

- accept `name` and optional `parent_folder_id`
- use the current tenant scope from the session
- create a suffixed sibling when the requested folder name conflicts
- return the created folder `id` and final `name`

### Domain

`OpenDrive.Drive` needs a helper that mirrors the file auto-rename logic for folders:

- try `create_folder/2`
- on `:name_conflict`, retry with `Folder (2)`, `Folder (3)`, and so on
- keep tenant and parent-folder validation in the domain

This helper should be used only for the folder-upload flow so normal manual folder creation behavior stays unchanged unless we explicitly decide otherwise later.

## Data flow

1. User drops a folder on the drive.
2. Browser expands the folder tree and produces:
   - directories with relative paths
   - files with relative paths and `File` objects
3. Frontend creates folders from shallowest to deepest.
4. Frontend stores a map of relative path to resulting `folder_id`.
5. Frontend uploads each file using the resolved target `folder_id`.
6. Existing upload completion and refresh behavior updates the listing.

## Error handling

- If directory traversal is unsupported, show a clear browser capability message.
- If a folder creation request fails, stop the folder-upload flow and surface which folder path failed.
- If one file upload fails after folders were created, keep the already created folders and show the file error in the queue.
- If an empty folder cannot be created because its parent creation failed, skip descendants and report the parent failure once.

## Constraints

- Preserve current `tenant_id` scoping and do not bypass `Drive`.
- Keep storage access behind `OpenDrive.Storage`.
- Do not require the backend to receive the entire tree manifest in one request.
- Prefer the smallest surface-area change that fits Phoenix and LiveView patterns already present in the app.

## Testing

- Domain test for folder auto-suffix creation inside the same parent.
- Controller test for authenticated folder-upload folder creation endpoint.
- LiveView render test for dropzone messaging if needed.
- JS-level verification through the app build and a focused browser/manual check for nested folder drops.

## Out of scope

- Uploading directories from the file picker via `webkitdirectory`
- Pause/resume for folder uploads
- Cross-browser parity beyond browsers that expose directory drop entries
- Transactional rollback of folders created before a later file upload fails
