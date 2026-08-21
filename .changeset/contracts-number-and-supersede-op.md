---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

A contract can be created without hand-typing its number, and re-papering runs as a remotable operation.

**`ContractNumber` is now nullable, and the server holds the invariant.** MJ has no way to express
"NOT NULL, assigned by the server on insert" (MJ#4001), and both available workarounds break creation
in opposite directions: a DB `DEFAULT` makes CodeGen emit an expression as a quoted literal, so
`spCreateContract` fails to compile and is left **dropped** (MJ#4000, added and reverted in
`V202608211000`/`1100`); and `AllowUpdateAPI = false` silences the validator but makes the field
read-only, which **omits it from the insert payload** so the procedure fails with "expects parameter
'@ContractNumber', which was not supplied".

So `V202608211200` relaxes the column and `ContractEntityServer.Save()` mints whenever the incoming
value is null **or blank** — blank matters because a form posting an empty string, a seed script or an
import would otherwise persist `''` as a contract number. `test-harnesses/contract-number-mint.mjs`
covers both cases and is load-bearing now that the database no longer holds this rule.

**Uniqueness stays the database's job, with a plain unique index.** `V202608211300` replaces the
filtered index `V202608211200` created. Both guarantee that every real number is unique; the plain one
additionally permits only **one** un-numbered row, so the multi-NULL state that only raw SQL could
create is refused at the floor rather than accumulating. No application-level null check was added and
none is needed: the entity guarantees a number on the way in and the index is the floor beneath it.
The plain index also removes a trap the filtered one introduced, where every INSERT depended on
`QUOTED_IDENTIFIER ON` and failed with a message naming neither the table nor the cause.

**Re-papering is a remotable operation.** `Contracts.Supersede` replaces the panel loading and saving a
foreign contract itself — server work that was being done in the client, and which could not work
anyway: in the browser MJ resolves the CodeGen-generated entity class rather than the app subclass, so
`ContractEntity.Supersede()` is simply absent client-side (MJ#4002). Server-side the app subclass
resolves correctly and the same-level, self-reference and lineage-cycle guards actually run. The
operation does replace-not-add, reports refusals with the entity's own prose, and **returns the live
list** — which is what fixes an Unlink button that lingered after the link was cleared elsewhere,
because the panel no longer keeps its own cached idea of what a contract supersedes.

It routes through `RouteOperation` rather than a generated typed client: the server resolves an
operation purely from the ClassFactory by key, so this needs no `MJ: Remote Operations` metadata row
and no file-generating CodeGen run.

**Supersession now lives in three places, each doing one job:** the `Supersedes` grid (see and remove),
the Re-papering picker in Details (add), and the derived `State` chip (that it happened). The picker is
available when NOT editing and only on a saved contract — it writes another record, so it needs this
one to exist. `test-harnesses/supersede.mjs` proves the entity path end to end.
