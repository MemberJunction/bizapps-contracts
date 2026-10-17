---
"@mj-biz-apps/contracts-actions": minor
"@mj-biz-apps/contracts-core-entities-server": minor
"@mj-biz-apps/contracts-entities": minor
"@mj-biz-apps/contracts-ng": minor
"@mj-biz-apps/contracts-server": minor
---

Contract types get a required, unique `Code` (for example `ORDER_FORM`) that other apps use to find
a type instead of its display name, so renaming a type no longer breaks callers. The migration sets
codes for the four shipped types by ID and derives the rest from each type's name.
