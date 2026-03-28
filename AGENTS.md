# OpenDrive Agent Notes

## Project context

- App: `OpenDrive`
- Stack: Elixir `~> 1.15`, Phoenix `~> 1.8.5`, LiveView, Ecto, SQLite, Tailwind, esbuild
- Main purpose: multi-tenant internal drive with file upload, download, trash, memberships, and audit trail

## Common commands

```bash
mix setup
mix phx.server
mix test
mix precommit
```

## Important paths

- `lib/open_drive/`: domain logic (`Accounts`, `Tenancy`, `Drive`, `Audit`, `Storage`)
- `lib/open_drive_web/`: Phoenix web layer, LiveViews, controllers, components, router
- `lib/open_drive_web/components/layouts/`: root and app layout templates
- `priv/static/`: static assets such as images, favicon, robots
- `priv/repo/migrations/`: database migrations
- `assets/`: CSS and JS entrypoints

## Working rules

- Prefer changing the smallest layer that solves the problem.
- Keep tenant-aware behavior scoped correctly. Reads and writes that depend on workspace context must stay bound to `tenant_id`.
- Preserve the storage abstraction through `OpenDrive.Storage`; do not couple domain code directly to S3-specific details unless the task is explicitly about the adapter.
- For UI metadata like page title, favicon, and global assets, check `lib/open_drive_web/components/layouts/root.html.heex` first.
- For frontend changes, preserve the current Phoenix/Tailwind/LiveView structure unless there is a clear reason to refactor.

## Validation

- Run focused tests when touching domain or controller behavior.
- Run `mix precommit` before finishing larger changes when practical.
- If a change affects static assets only, a quick layout/template review is usually enough unless the user asks for runtime verification.
