# @mj-biz-apps/contracts-integration-tests

## 0.2.0

### Patch Changes

- Updated dependencies [4e8c1ce]
  - @mj-biz-apps/contracts-entities@0.2.0
  - @mj-biz-apps/contracts-core-entities-server@0.2.0

## 0.1.1

### Patch Changes

- 8062a66: Split the release into a version step and a publish step, so neither writes directly to a branch.

  `version.yml` (new, on `next`) turns pending changesets into a reviewable "Version Packages" PR —
  bumps, CHANGELOGs, the mj-app.json version and range, and a refreshed lockfile.
  `release-readiness.yml` (new) gates the version PR and any PR to `main`. `publish.yml` keeps only
  the publish half and refuses to run while changesets are pending.

  Ported from bizapps-accounting, where the old flow published to npm and then failed to write the
  bump back because its branches are under a ruleset requiring pull requests. This repo's branches are
  not ruled that way today, so nothing is broken here — the point is that the release no longer
  depends on that staying true, and the version bump becomes a reviewable diff either way.

  - @mj-biz-apps/contracts-core-entities-server@0.1.1
  - @mj-biz-apps/contracts-entities@0.1.1

## 0.1.0

### Patch Changes

- Updated dependencies [80ac891]
- Updated dependencies [2aa3ace]
- Updated dependencies [b373233]
- Updated dependencies [00e11b3]
- Updated dependencies [6315add]
- Updated dependencies [dc55dd0]
- Updated dependencies [668fa6d]
- Updated dependencies [4d190f5]
- Updated dependencies [bab2cc5]
- Updated dependencies [3b2edc7]
- Updated dependencies [94e73d3]
- Updated dependencies [1aa3c88]
  - @mj-biz-apps/contracts-entities@0.1.0
  - @mj-biz-apps/contracts-core-entities-server@0.1.0
