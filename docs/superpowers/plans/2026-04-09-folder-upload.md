# Folder Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support dragging a folder into the drive while preserving the internal structure by creating subfolders automatically inside the current folder.

**Architecture:** Add a small authenticated JSON endpoint for programmatic folder creation with auto-suffix behavior, then teach the `DirectUploadZone` hook to traverse dropped directory entries, create folders in depth order, and upload files into the resolved folder ids.

**Tech Stack:** Phoenix, LiveView, Elixir, vanilla browser File System entry APIs, esbuild

---

### Task 1: Backend folder-creation primitive

**Files:**
- Modify: `lib/open_drive/drive.ex`
- Test: `test/open_drive/drive_test.exs`

- [ ] Add a failing domain test for auto-suffixed folder creation under the same parent.
- [ ] Implement a `Drive.create_folder_with_available_name/2` helper that retries with `Folder (2)` style suffixes on `:name_conflict`.
- [ ] Run `mix test test/open_drive/drive_test.exs`.

### Task 2: Authenticated folder-upload endpoint

**Files:**
- Create: `lib/open_drive_web/controllers/folder_upload_controller.ex`
- Modify: `lib/open_drive_web/router.ex`
- Test: `test/open_drive_web/controllers/folder_upload_controller_test.exs`

- [ ] Add a failing controller test for authenticated JSON folder creation returning the created folder id and suffixed name when needed.
- [ ] Implement the controller and route under the authenticated browser scope.
- [ ] Run `mix test test/open_drive_web/controllers/folder_upload_controller_test.exs`.

### Task 3: Dropzone copy and recursive traversal

**Files:**
- Modify: `assets/js/app.js`
- Modify: `lib/open_drive_web/live/drive_live/components.ex`
- Modify: `test/open_drive_web/live/drive_live/index_test.exs`

- [ ] Keep the dropzone copy explicit that folder upload is supported by drag-and-drop.
- [ ] Replace the current directory-skip path with recursive traversal using dropped directory entries.
- [ ] Create folders in depth order through the new endpoint, then upload each file with the resolved `folder_id`.
- [ ] Preserve empty subfolders and keep current queue behavior for files.
- [ ] Run `mix test test/open_drive_web/live/drive_live/index_test.exs`.
- [ ] Run `mix assets.build`.

### Task 4: Focused verification

**Files:**
- No new files expected

- [ ] Run `mix test test/open_drive/drive_test.exs test/open_drive_web/controllers/folder_upload_controller_test.exs test/open_drive_web/live/drive_live/index_test.exs`.
- [ ] Run `mix compile`.
- [ ] If available, perform one manual browser verification by dragging a nested folder and confirming the resulting structure.
