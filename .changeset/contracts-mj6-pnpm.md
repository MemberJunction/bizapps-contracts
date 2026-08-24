---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-actions': patch
'@mj-biz-apps/contracts-server': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

MJ 6 and pnpm, matching the family baseline.

Contracts was the last app in the estate still on **npm** and **MJ 5.44** — common, tasks,
accounting and orders had all moved. That gap is not cosmetic: an npm-locked member cannot join a
pnpm cross-repo workspace on equal terms, and 5.44 peer pins against a 6.1 host are a resolution
accident waiting to happen rather than a declared contract.

**The manifest now says what it needs.** `mjVersionRange` is `>=6.1.0-edge.2 <7.0.0` — a
**same-tuple prerelease bound**, because standard semver excludes a prerelease from any comparator
that does not share its `major.minor.patch`, so `>=6.0.0 <7.0.0` would reject `6.1.0-edge.2` under
every tool except MJ's own gate (which coerces to the base tuple first). Every sub-package's
`@memberjunction/*` peer moved `^5.44.0` → `^6.1.0-edge.2`, and `ng-ui-components` `^5.50.0` → the
same.

**pnpm, configured like its siblings.** `packageManager` is `pnpm@10.33.0`; `pnpm-workspace.yaml`
carries `linkWorkspacePackages: true` (without it, internally-pinned exact versions resolve from the
registry instead of linking locally) and the 16-name build-scripts allowlist; the npm `overrides`
block became `pnpm.overrides` with the family's Angular 21.1.3 set plus `@memberjunction/core` and
`global`. `package-lock.json` is gone and `pnpm-lock.yaml` replaces it.

**One deliberate divergence from common/accounting**, and the same one orders carries: `.npmrc` sets
`auto-install-peers=false`. With it on, every unsatisfied peer becomes an install instruction — and
`contracts-ng` declares the **unpublished** `@mj-biz-apps/accounting-ng` as a mandatory peer, so the
install would 404 and no lockfile could exist. It flips to the family default when accounting
publishes. That peer's range also tightened from `*` to `>=0.1.0`, matching how the converted apps
declare each other.

`.npmrc` is no longer git-ignored. It was, via a scaffold-template rule that grouped it with the
`.mjrc.*` files — which would have left CI installing on pnpm defaults while local ran on these
settings. Both sibling repos track theirs.

CI moved with it: `pnpm/action-setup` before `setup-node` (the `cache: 'pnpm'` option needs pnpm on
PATH first), `pnpm install --frozen-lockfile` in place of `npm ci`, lockfile paths and cache keys
repointed, `pnpm exec changeset publish`, and the case-sensitivity validator replaced with the pnpm
version already proven in accounting.

**The tab strip no longer asks for a disabled state, because MJ has none.** `ToTabConfigs` used to
set `disabled` and `disabledReason` on every `not-yet` tab. MJ's `TabConfig` is
`key | label | icon | badge | badgeVariant`, and `mj-tab-nav` renders every tab as a plain clickable
button — so **those two fields were already being discarded**. A blocked tab has always rendered
enabled and unexplained at runtime; type erasure was the only reason nobody saw it, and MJ 6 turned
it into three `TS2339` that finally said so.

Nothing regressed by removing them. The gating still lives in `ContractTabDef.State` / `.Reason`,
`ResolveActiveTab` still refuses to land on an unreachable tab, and `SelectTab` still rejects a click
on one — that rejection is now correctly documented as the ONLY guard rather than "the second of
two". What is missing is the visual affordance: a user can click a blocked tab and nothing happens,
with no explanation. Restoring it is two lines once MJ's disabled state lands (`2acd4dc7cb`,
unmerged) — `plans/BACKLOG.md` B-2. Contracts is moving to custom forms and the MJ record system, so
the treatment gets revisited there rather than rebuilt against this component.

The two tests that asserted on `TabConfig.disabled` now assert the same invariants against
`ContractTabDef`, the layer that still carries them — left pointed at `TabConfig` they would have
filtered on a property nothing sets and passed while testing nothing. A new test pins the emitted
key set to what MJ actually supports, so the next silently-ignored field fails instead of shipping.

All six packages build clean on MJ 6; the Angular suite is 56/56. The other five packages' `test`
scripts are still `echo "No tests configured yet"` stubs — that green is vacuous and is not coverage.
