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

Versioning and publishing are separate, and neither writes to a branch.

1. `version.yml` maintains a **"Version Packages" PR** into `next` — the bump,
   the CHANGELOGs, `mj-app.json`'s version and range, and a refreshed
   `pnpm-lock.yaml`. Review it and merge when you are ready to release. Its
   checks do not start on their own under the default `GITHUB_TOKEN`: click
   **Approve and run** on the PR.
2. Open one PR: `next` → `main`, titled `Release vX.Y.Z`.
   `release-readiness.yml` asserts no changesets are still pending and that a
   release carrying migrations is at least a minor.
3. Merge. The push to `main` runs `publish.yml`: validate → build →
   `changeset publish` (every package whose version is not already on the
   registry) → tag `vX.Y.Z`. It computes no version and writes to no branch.

Never hand-edit the version bump. It is `changeset version`'s output, delivered
by the Version Packages PR — and bumping a package.json by hand desynchronises
it from the lockfile, since `changeset version` rewrites internal dependency
ranges and does not touch the lockfile.

## Hotfixes

A genuine emergency can PR straight to `main`. **Open an ordinary `main` →
`next` PR immediately afterwards** to carry the fix home — there is no automated
merge-back. It used to exist because the old flow created the version commit ON
`main` and had to push it back; the bump now originates on `next`, so a hotfix is
the only thing that travels in that direction. Until that PR merges, the fix
exists only on `main`. Prefer the normal path.

## Why `main` looks "ahead" of `next`

Permanently, by one commit per release: the release PRs' own merge commits, whose
trees are identical to `next` — GitHub creates a merge commit even when the base
is strictly behind. `git diff next main` (empty) is the check that means
something; `git log next..main` is noise. Nothing in the release path depends on
the ancestry, which is why there is no merge-back to "fix" it.
