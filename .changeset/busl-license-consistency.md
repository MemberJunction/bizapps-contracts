---
"@mj-biz-apps/contracts-actions": patch
"@mj-biz-apps/contracts-ng": patch
"@mj-biz-apps/contracts-core-entities-server": patch
"@mj-biz-apps/contracts-entities": patch
"@mj-biz-apps/contracts-server": patch
---

License declarations now agree on BUSL-1.1 everywhere.

Every machine-readable declaration was already correct. The README footer was not: it linked
the text "ISC" to `LICENSE`, a file whose first line reads "Business Source License 1.1", so
the one place a human is told the license contradicted the file it pointed at. The link text
now names the license the file actually grants.
