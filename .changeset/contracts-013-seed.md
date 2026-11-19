---
"@mj-biz-apps/contracts-entities": minor
---

Ship v0.13's metadata and the Postgres side of its schema change. A `Metadata_Sync` migration creates the Sweep Contract Renewal Terms action and its daily scheduled job on install and upgrade (create-only, so a host that pauses the job or edits the action keeps its change), and the ContractOrder / CarryDiscountOnRenewal migration gains its PostgreSQL counterpart.
