# Branching — the `next` → `main` model

This repo (like MemberJunction itself and the shipped BizApps) uses a two-tier
branch model:

```
feature branch ──PR──▶ next ──(release PR)──▶ main ──(push triggers publish.yml)──▶ npm + tag
```

- **`next`** — the DEFAULT + integration branch. All feature work merges here.
- **`main`** — the release branch. Only updated by a single coordinating
  "Release vX.Y.Z" PR from `next` (plus rare hotfixes). Pushes to `main`
  publish.

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

1. Open one PR: `next` → `main`, titled `Release vX.Y.Z`.
2. Merge. The push to `main` runs `publish.yml`: version bump from pending
   changesets → build → npm publish → tag `vX.Y.Z` → commit the bump back to
   `main` → **automatically merge `main` into `next` and refresh the lockfile**.
3. `next` is immediately ready for the next round. Never hand-author the
   `chore: Update package-lock.json with vX.Y.Z dependencies` commit — the
   workflow owns it.

## Hotfixes

A genuine emergency can PR straight to `main`; the publish workflow's
merge-back brings the fix into `next` automatically. Prefer the normal path.
