# Branching — the `next` → `main` model

This repo (like MemberJunction itself and the shipped BizApps) uses a two-tier
branch model:

```
feature branch ──PR──▶ next ──(Version Packages PR)──▶ main ──(push triggers publish.yml)──▶ npm + tag
                                                           └──(back-merge PR)──▶ next
```

- **`next`** — the DEFAULT + integration branch. All feature work merges here.
- **`main`** — the release branch. Only updated by the bot-opened "Version
  Packages" PR (head `changeset-release/main`), plus rare hotfixes. Pushes to
  `main` publish.

## Feature work

1. Cut from `next`, never from `main`:
   ```sh
   git checkout next && git pull
   git checkout -b feature/short-descriptive-name
   git push -u origin feature/short-descriptive-name
   ```
2. **Branch naming**: `feature/<what-it-does>` (also seen: `fix/…`, `chore/…`).
   Descriptive beats short.
3. **Tracking rule (important)**: a local branch must track
   `origin/<same-name>` — never `origin/next` or `origin/main`. A branch that
   tracks `next` will push straight to `next` and bypass review. Verify with
   `git branch -vv`; fix with
   `git branch --set-upstream-to=origin/<name> <name>`.
4. Open the PR against `next`. CI runs `build.yml` (compile) and `changes.yml`
   (migration filename/timestamp validation + changeset enforcement).
5. If the PR adds a migration, it MUST include a changeset with at least a
   **minor** bump (`npx changeset`) — CI fails otherwise.

## Releasing

1. Every push to `next` runs `version.yml`, which maintains ONE **"Version
   Packages" PR** from `changeset-release/main` into **`main`** (opened with the
   GitHub App token, so its checks run). It carries the bump, the CHANGELOGs,
   `mj-app.json`'s version and range, and a refreshed `pnpm-lock.yaml`.
   **That PR is the release** — there is no hand-opened `next` → `main` PR.
2. PRs into `main` run `release-readiness.yml` (the `rr:` checks) and
   `build.yml`. Review and merge when you are ready to release.
3. The push to `main` runs `publish.yml`: validate → build → `changeset publish`
   (every package whose version is not already on the registry) → tag `vX.Y.Z`
   only if something shipped → the App opens and merges a
   `release-back-merge/vX.Y.Z` PR into `next`, so `next` carries the released
   versions. `rr: release base current` fails the next release if that
   back-merge never landed.

Never hand-edit the version bump. It is `changeset version`'s output, delivered
by the Version Packages PR — and bumping a package.json by hand desynchronises
it from the lockfile, since `changeset version` rewrites internal dependency
ranges and does not touch the lockfile.

## Hotfixes

A genuine emergency can PR straight to `main`, but it must carry its own version
bump (`pnpm exec changeset` + `pnpm run version:prepare`) — `publish.yml` fails a
push to `main` that changes `packages/` without one. The automated back-merge PR
carries the fix home to `next`. Prefer the normal path.
