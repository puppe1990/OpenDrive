# OpenDrive

OpenDrive is a multi-tenant internal drive built with Elixir, Phoenix LiveView, SQLite metadata, and pluggable blob storage behind `OpenDrive.Storage`.

![OpenDrive dashboard](priv/static/images/opendrive-dashboard.png)

## Overview

The application is organized around workspaces (`tenants`). Each authenticated user operates inside one active workspace and all drive reads and writes are scoped by `tenant_id`.

Current product surface:

- Email/password authentication plus magic-link login support
- Workspace creation during registration
- Multi-tenant membership model with `owner`, `admin`, and `member` roles
- Tenant switcher for users who belong to multiple workspaces
- Folder tree navigation
- File upload with direct-to-storage flow and backend proxy fallback
- Authenticated single-file download and multi-file ZIP download
- Soft delete, trash listing, restore, and permanent empty-trash cleanup
- Audit log entries for key tenant, membership, and drive actions

## Stack

- Elixir `~> 1.15`
- Phoenix `~> 1.8.5`
- Phoenix LiveView `~> 1.1`
- Ecto + SQLite via `ecto_sqlite3`
- Tailwind CSS + esbuild
- S3-compatible storage adapter plus a fake local adapter for development and tests

## Domain structure

Main modules:

- `OpenDrive.Accounts`: registration, authentication, session tokens, password/email updates, scope bootstrap
- `OpenDrive.Tenancy`: workspace creation, membership listing, member management, scope resolution
- `OpenDrive.Drive`: folders, files, uploads, renames, downloads, trash, restore, ZIP assembly
- `OpenDrive.Audit`: tenant-scoped audit event persistence
- `OpenDrive.Storage`: blob storage facade with adapter-based implementation

Relevant web entrypoints:

- `lib/open_drive_web/router.ex`
- `lib/open_drive_web/live/drive_live/index.ex`
- `lib/open_drive_web/live/members_live/index.ex`
- `lib/open_drive_web/live/trash_live/index.ex`
- `lib/open_drive_web/controllers/direct_upload_controller.ex`
- `lib/open_drive_web/controllers/file_download_controller.ex`

## Data model

The current schema is composed of:

- `users`
- `users_tokens`
- `tenants`
- `memberships`
- `folders`
- `file_objects`
- `files`
- `audit_events`

Important storage and integrity rules:

- Tenant slug uniqueness is scoped by `owner_user_id`, not globally
- Active folders must have unique names within the same tenant + parent folder
- Active files must have unique names within the same tenant + folder
- Soft-deleted folders/files do not block reuse of the same name

## Local development

### Requirements

- Elixir `~> 1.15`
- Erlang/OTP compatible with Phoenix 1.8
- Node.js is not required globally; Tailwind and esbuild are installed through Mix tasks

### Bootstrapping

```bash
mix setup
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000).

`mix setup` runs:

- dependency install
- database creation and migrations
- `priv/repo/seeds.exs`
- Tailwind/esbuild installation
- asset build

At the moment, `priv/repo/seeds.exs` is only a placeholder, so the first user/workspace is created through the registration flow.

### Handy commands

```bash
mix test
mix precommit
mix ecto.reset
mix assets.build
```

## Authentication and workspace flow

- Anonymous users land on `/`
- Registration creates both the user and the first workspace in a single transaction
- Authenticated users are redirected to `/app`
- Users with more than one membership can switch the active workspace via `/app/switch-tenant`
- Member management is limited to owners and admins
- Adding a member requires that the invited email already exists as a registered OpenDrive user

## Upload and download flow

Uploads support two paths:

1. Direct upload preparation through `POST /app/uploads`
2. Backend proxy upload through `POST /app/uploads/proxy`

Direct uploads are signed with a Phoenix token and finalized through `POST /app/uploads/complete`.

Current operational limits from the code:

- Maximum upload size: `2 GB`
- Backend proxy fallback threshold constant: `100 MB`
- ZIP download limit: `100 files`
- ZIP download total size limit: `500 MB`

Downloads support:

- Single file redirect through a presigned download URL
- ZIP generation for selected files

## Storage configuration

By default, development and tests use `OpenDrive.Storage.Fake`.

To enable the S3-compatible adapter at runtime:

```bash
export OPEN_DRIVE_STORAGE_ADAPTER=s3
export AWS_S3_BUCKET=your-bucket
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1
```

Optional custom endpoint variables:

```bash
export AWS_S3_HOST=localhost
export AWS_S3_PORT=9000
export AWS_S3_SCHEME=http://
```

You can also place these variables in `.env.local` at the project root. `config/runtime.exs` loads that file automatically outside the test environment without overriding shell-exported variables.

## Database configuration

Default database files:

- Development: `open_drive_dev.db`
- Test: `open_drive_test.db`
- Production fallback when `DATABASE_PATH` is set: custom path
- Production fallback without `DATABASE_PATH`: `/tmp/open_drive.db`

To override the runtime database path:

```bash
export DATABASE_PATH=/absolute/path/to/open_drive.db
```

## Quality gate

Project checks are grouped in:

```bash
mix precommit
```

That alias runs:

- compile with warnings as errors
- `mix deps.unlock --unused`
- format check
- Credo strict mode
- tests

If you want the same gate before each push:

```bash
git config core.hooksPath .githooks
```

## Notes for contributors

- Keep tenant-aware behavior scoped through the current workspace context
- Prefer changing the smallest layer that solves the problem
- Preserve blob handling behind `OpenDrive.Storage`
- For root-level UI metadata and global assets, start with `lib/open_drive_web/components/layouts/root.html.heex`
- For front-end work, keep the current Phoenix, Tailwind, and LiveView structure unless there is a concrete reason to refactor
