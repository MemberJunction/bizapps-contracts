# Publishing the app

An Open App is **consumed from GitHub + npm**: the manifest and migrations are
fetched from a tagged GitHub release, the packages are installed from npm.
Publishing = making those two things exist for a version. The pipeline is
already wired in `.github/workflows/publish.yml`.

## The release pipeline (two halves, deliberately)

Versioning and publishing are separate workflows, and neither writes to a
branch. The version bump arrives as a **pull request**; publishing reads the
versions that PR landed.

### 1. `version.yml` — on every push to `next`

Runs `changesets/action` with a version script and **no** publish script, so it
can only open or update the **"Version Packages" PR** into `next`. That PR
carries, as a reviewable diff: every package bumped, the generated CHANGELOG
entries, `mj-app.json`'s `version` and `mjVersionRange`, and a **refreshed
lockfile**.

The lockfile refresh is not incidental. `changeset version` rewrites every
`package.json` — internal dependency ranges included — and does **not** touch
the lockfile. Skip it and `--frozen-lockfile` fails on every branch afterwards.

Its checks run automatically: the PR is opened by a GitHub App, and App-created
PRs trigger workflows, so `build.yml` verifies `--frozen-lockfile` before merge.

### 2. `release-readiness.yml` — on the version PR, and on any PR to `main`

Two aggregate assertions, sharing one implementation (`ci/check-bump-level.sh`):
no changesets may still be pending, and a release carrying migrations must be at
least a minor. Both are properties of the *release*, not of any one PR — which is
why they are not enforced per feature PR: changesets aggregate, so one minor
already in the window covers the release. Label a PR `bump-level-exempt` for a
migration that genuinely is not a feature.

### 3. `publish.yml` — on push to `main`

Validates (lockfile case, migration filenames, packages exist on npm,
`repository.url` matches the root, every publishable package restricts what it
ships), **fails** if changesets are still pending, builds, runs
`changeset publish`, and tags `vX.Y.Z` idempotently.

`changeset publish` never reads `.changeset/*.md`. It compares each package's
version against the registry and publishes what is missing — so the versions the
release PR carried *are* the instruction, and a re-run is a safe no-op.

Nothing in this half writes to `main` or `next`. The shape it replaced did (a
version commit pushed straight to `main`, then a merge-back to `next`), and under
a ruleset requiring pull requests that fails **after** publishing to npm:
registry moves, repository does not, no tag.

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
- [ ] "Version Packages" PR reviewed and merged into `next` (confirm it carries the
      refreshed lockfile and the `mj-app.json` sync — its checks run on their own,
      since a GitHub App opens the PR)
- [ ] Release PR `next` → `main` green on `release-readiness`
- [ ] Workflow run green; tag exists; packages on npm
