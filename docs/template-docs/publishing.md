# Publishing the app

An Open App is **consumed from GitHub + npm**: the manifest and migrations are
fetched from a tagged GitHub release, the packages are installed from npm.
Publishing = making those two things exist for a version. The pipeline is
already wired in `.github/workflows/publish.yml`.

## The release pipeline (what publish.yml does)

Trigger: push to `main` (i.e. merging the release PR from `next`).

1. Validations: lockfile case-sensitivity, migration filenames, every package
   already exists on npm, `repository.url` present (npm provenance).
2. If there are **no pending changesets → no-op** (safe to merge doc-only PRs).
3. `changeset version` — bumps all fixed packages to the next version and
   verifies it against the expected bump (major changeset → major; new
   migrations since the last tag → at least minor; else patch).
4. Syncs `mj-app.json`: `"version"` ← package version; `"mjVersionRange"` ←
   derived from the `@memberjunction/core` peer dep.
5. Builds all packages, then `changeset publish` → **npm**.
6. Tags `vX.Y.Z`, pushes the version-bump commit back to `main`.
7. Merges `main` → `next` and refreshes `package-lock.json` there.

## One-time setup for a new app (first publish bootstrap)

npm refuses OIDC publishing for packages that don't exist yet, and the
validation step fails until they do. So, once per package:

1. **Publish a `0.0.0` placeholder manually** (with a classic npm token or
   `npm login`): minimal `package.json` + `npm publish --access public`.
2. On npmjs.com, under each package → Settings → **Trusted Publisher**, add
   this GitHub repo + the `publish.yml` workflow.
3. From then on the workflow publishes via **OIDC trusted publishing** — there
   is **no `NPM_TOKEN` secret** to create or rotate. (`publish.yml` already
   declares `permissions: id-token: write`.)

## GitHub release tags

`mj app install <repo>` resolves versions from **git tags** (`vX.Y.Z`) — the
publish workflow creates them. The manifest version at a tag must equal the
tag (step 4 guarantees it).

## The no-breaking-changes policy (IMPORTANT)

Within a published **major** version, schema changes must be **additive only**:
no dropping tables/columns, no narrowing types, no renames, no new required
parameters. Anything breaking forces a **major** bump. Consult MemberJunction's
`packages/OpenApp/PUBLISH_NO_BREAK_POLICY.md` before authoring any migration
that touches an existing published schema — upgraders run only your NEW
migrations, never a rebuild.

## Publish checklist

- [ ] Changesets on `next` describe everything since the last release
- [ ] Migrations + regenerated code committed together (see codegen doc)
- [ ] `next` is green (build.yml + changes.yml)
- [ ] Release PR `next` → `main` merged
- [ ] Workflow run green; tag exists; packages on npm; `next` got the merge-back
