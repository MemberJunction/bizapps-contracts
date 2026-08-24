# Developing your app inside a MemberJunction checkout (worktree linking)

An Open App doesn't run by itself — it runs **inside** MemberJunction: MJAPI
loads your server packages, MJExplorer bundles your Angular packages, and your
schema lives in an MJ database. For day-to-day development you therefore
*link* this repo into a local MJ checkout as a workspace member. This page is
the manual, step-by-step version of that link.

**The idea in one sentence:** put a checkout of your app *inside* the MJ repo
at `packages/dev-apps/<your-app>/`, let npm treat your app's packages as
workspace members (so everything shares ONE copy of every `@memberjunction/*`
package), wire two config points, run your migrations, build, and start MJ.

## 0. Prerequisites

- A **MemberJunction checkout** that builds and runs on your machine (clone
  https://github.com/MemberJunction/MJ, `npm install`, `npm run build`, a SQL
  Server database migrated by MJ's own setup, `.env` configured). MJAPI always
  needs its MJ database — that's independent of your app.
- Node ≥ 18, npm ≥ 10.

## 1. Put your app inside the MJ repo — as a git worktree

Keep your main app clone wherever you like; materialize a **linked worktree**
of it inside MJ. A worktree is a second working copy that shares the same git
history — cheap, and your feature branch lives inside MJ while your main clone
stays clean:

```sh
# from your app clone
git worktree add <path-to-MJ>/packages/dev-apps/mj-sample-open-app feature/my-feature
```

(A plain `git clone` into that folder also works; the worktree just keeps one
history. The folder name under `packages/dev-apps/` should be your app's repo
name.)

## 2. Make your app's packages workspace members

Open the **MJ repo's root `package.json`** and make sure the `workspaces`
array contains the dev-apps glob:

```json
"workspaces": [
  "packages/*",
  "...existing entries...",
  "packages/dev-apps/*/packages/*"
]
```

Then, from the MJ repo root:

```sh
npm install
```

This is the step that makes linked development safe: as workspace members,
your app's packages resolve `@memberjunction/*` to the **host's single copy**
(npm dedupes). If you ever install your app's packages some other way and a
second copy of `@memberjunction/global`/`core` nests under them, MJ's class
registry silently splits — entities and resolvers just don't appear, with no
error. Corollaries:

- never run `npm install` inside the app subfolder — always at the MJ root;
- don't have the same app simultaneously *installed* (published packages) and
  *linked* (workspace) in one MJ tree.

## 3. Wire the server (MJAPI)

Two edits in the MJ repo:

1. `packages/MJAPI/package.json` — add your server bootstrap package:
   ```json
   "dependencies": { "@mj-biz-apps/contracts-server": "1.0.0" }
   ```
2. MJ root `mj.config.cjs` — tell MJAPI to load it at boot:
   ```js
   dynamicPackages: {
     server: [
       {
         PackageName: '@mj-biz-apps/contracts-server',
         StartupExport: 'LoadMjBizappsContractsServer',   // must match mj-app.json
         AppName: 'mj-sample-app',
         Enabled: true
       }
     ]
   }
   ```
   Run `npm install` at the MJ root again after the package.json edit.

## 4. Wire the client (MJExplorer) — only if you ship UI packages

1. `packages/MJExplorer/package.json` — add `"@mj-biz-apps/contracts-ng": "1.0.0"`.
2. Add a static import to
   `packages/MJExplorer/src/app/generated/open-app-bootstrap.generated.ts`:
   ```ts
   import '@mj-biz-apps/contracts-ng';
   ```
   (When an app is *installed* via `mj app install`, the CLI maintains this
   file; in a manual link you add the line yourself. Re-run `npm install`.)

## 5. Database — when do you actually need one?

MJAPI itself always needs the MJ database. Whether **your app** adds DB steps
depends on which manifest blocks you kept:

| Your app has… | DB work needed |
|---|---|
| Only a manifest, or only code packages | **None** — skip to step 6 |
| A `schema` + `migrations` block | **Yes** — create/migrate the schema *before first boot* (below) |
| A `metadata/` directory | Yes at dev time — `mj sync push` writes into the DB |

For a schema-backed app, from the MJ repo root:

```sh
npx mj migrate --schema __mj_BizAppsContracts --dir packages/dev-apps/mj-sample-open-app/migrations
```

This creates the schema (if missing) and applies your app's migrations to the
same database MJAPI uses. Re-run it whenever you add a migration. After
schema changes, run `npx mj codegen` (see codegen-and-metadata-migrations.md).

## 6. Build and run

```sh
# from the MJ repo root
npx turbo build --filter="@mj-biz-apps/contracts-*"   # build your app's packages
npm run start:api                              # MJAPI — watch the log for your startupExport being called
npm run start:explorer                         # MJExplorer (if you wired a client package)
```

Server code changes: rebuild your package + restart MJAPI (no HMR on the
server). Client changes: rebuild the package; Explorer's dev server hot-reloads.

## 7. Keep the wiring out of your commits

The edits from steps 2–4 (`MJ/package.json`, `mj.config.cjs`,
`MJAPI/MJExplorer package.json`, the bootstrap import, `package-lock.json`)
are **local development wiring in the MJ repo — never commit them to MJ**.
Your app repo's own changes commit normally on your feature branch inside
`packages/dev-apps/<app>/`, which is its own git checkout.

When you're done: remove the worktree (`git worktree remove <path>`), revert
the MJ wiring edits, `npm install` at the MJ root, and (optionally) drop the
app schema from your dev database.

## Verifying the link worked

1. `npm ls @memberjunction/global` at the MJ root shows **one** resolved copy.
2. MJAPI boot log shows your package loading + `LoadMjBizappsContractsServer` called.
3. Once you've added your first migration + run codegen, your entities appear
   in MJ metadata (queryable via GraphQL / visible in Explorer).
