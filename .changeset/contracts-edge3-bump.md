---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

Move every MemberJunction dependency from `6.1.0-edge.2` to `6.1.0-edge.3`.

**Why:** `@memberjunction/ng-hierarchy-tree` — which the Lineage panel uses — is published only from
`6.1.0-edge.3`. There is no `edge.2` of it, so a standalone build could not resolve it and CI failed
with `TS2307: Cannot find module`. It resolved locally only because the mjdev parent workspace links
the MJ source directly, which is exactly why this was invisible until CI.

**The mixed state is the thing to avoid.** An earlier attempt updated only the lockfile, which left
some packages on edge.2 and pulled others to edge.3; that combination failed differently, with
`TS2554: Expected 1 arguments, but got 2` inside three CodeGen-generated form components. With every
pin moved together the build is clean — **6/6 packages, 180/180 unit tests, no regeneration required.**
So those errors were a symptom of version skew, not a real signature break, and no CodeGen run is part
of this change.

Bumped: the root `devDependencies` (17 packages), `mj-app.json`'s `mjVersionRange`, and the peer ranges
on all six workspace packages — plus `@memberjunction/ng-hierarchy-tree` added to the root
`devDependencies`, which is the convention this repo already follows for every other MJ Angular peer
(peer on the package, devDependency at the root, because `.npmrc` sets `auto-install-peers=false`).
