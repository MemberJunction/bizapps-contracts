---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-actions': patch
'@mj-biz-apps/contracts-server': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

The baseline is one file, and it now actually installs the app.

**The migrations installed nothing.** Applying them to an empty database produced eleven
tables and nothing else — no base views, no CRUD procedures, no `__mj.Entity` rows. Every
sibling app self-installs; contracts was the only one that did not, and the migration said
so in a banner nobody had cause to read ("NOTHING HAS BEEN APPENDED YET"). Measured
from zero, before → after:

    schema                    tables  views  procs  entities
    __mj_BizAppsContracts         11      0      0         0     ← before
    __mj_BizAppsContracts         11     10     30        10     ← after

The CodeGen output is folded in, so the baseline produces an INSTALLED app; `mj sync push`
seeds the reference vocabulary as before.

**One file, not two.** `B…__Schema_and_Types` + `V…__Tables_and_Objects` were split following
orders so a user-defined table type would be committed before any trigger declaring a variable
of it compiled. That hazard is real and **this app has no table types**, so the second file
bought nothing. The constraint — and instructions to split back out if a type ever lands — is
kept in §2.A and `migrations/_README.md`.

**Compatibility with the current orders and accounting.** Verified against both at
`origin/next`, rebuilt from zero. Accounting's `Batch` → `JournalEntryBatch` rename stays
inside its own tables; contracts' only accounting FK is `Currency`, and its orders surface
(`Product`, `SubscriptionType`, `Subscription`, `OrderHeader`, `PaymentTermsType`) is
unchanged — so **no contracts schema change was required**.

**A trap worth writing down.** CodeGen regenerates from the DATABASE, so capturing its output
before the other apps' metadata is synced silently drops definitions — a first attempt lost
1350 lines of `Orders.*` from the generated remote operations. The sequence that works:
`wipe → migrate → sync EVERY OTHER APP → codegen → capture → verify from zero`.
