---
'@mj-biz-apps/contracts-integration-tests': patch
---

Split the release into a version step and a publish step, so neither writes directly to a branch.

`version.yml` (new, on `next`) turns pending changesets into a reviewable "Version Packages" PR —
bumps, CHANGELOGs, the mj-app.json version and range, and a refreshed lockfile.
`release-readiness.yml` (new) gates the version PR and any PR to `main`. `publish.yml` keeps only
the publish half and refuses to run while changesets are pending.

Ported from bizapps-accounting, where the old flow published to npm and then failed to write the
bump back because its branches are under a ruleset requiring pull requests. This repo's branches are
not ruled that way today, so nothing is broken here — the point is that the release no longer
depends on that staying true, and the version bump becomes a reviewable diff either way.
