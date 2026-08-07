---
'@mj-biz-apps/contracts-ng': patch
---

One coherent demo dataset across contracts, orders and accounting — and one command to apply it.

**The problem.** Each app grew its own demo data, so an instance ended up with two universes that
shared nothing: orders/accounting had *DEMO Publishing Co* selling to *DEMO Riverside Library*, while
contracts had *Blue Cypress* selling to *Northwind Association*. No screen could show an agreement,
the orders it generated and the journal entries those booked — which is the whole story these apps
exist to tell. Contracts now hangs off the same company, customers and catalogue.

**`npm run demo:seed`** resets and rebuilds everything; **`npm run demo:reset`** just clears.

**Written through the entity layer, not SQL.** `ContractEntityServer` and its child collections, so
term numbering is derived, the escalation ceiling is checked against the contract type, and coverage
is required before a term activates. Raw SQL produces rows the *database* accepts; this produces rows
the *app* accepts. The retired seed it replaces escalated a term 6.67% under a 5% cap and the UI
displayed exactly that.

**Orders' seeder is delegated to, not reimplemented** — it owns its own story (two companies, a real
chart of accounts, nine orders across every state, trial balance balanced) and duplicating it would
guarantee drift.

**Its reset had to be rebuilt here, because orders' does not work twice:**

- it opens its pool without `enableQuotedIdentifier: true`, so every DELETE against a table with a
  filtered index fails with `Msg 1934` — the Product delete dies, ProductCategory then cannot go, and
  the re-seed collides on `UQ_Company_Name`
- `DISABLE TRIGGER` needs rights `MJ_Connect` does not have; the CodeGen credentials do
- its delete list predates `ProductPrice`, `ProductBundleItem`, `OrderAdjustment` and several others

So the teardown here **deletes to a fixed point** — attempt everything, retry what failed on a
foreign key, repeat — which makes ordering irrelevant and stops the list rotting the next time a
table is added. It verifies afterwards that nothing tagged `DEMO` remains, rather than reporting
success.

**`ui-layout.mjs` no longer hardcodes contract numbers.** It named `CTR-002001`/`CTR-002004` from one
seed file, which quietly made a *layout* suite depend on which dataset had been applied. It now
discovers what the app returns.

Verified: seed → reset → seed again, twice over; 527 assertions green; one company across all three
apps; zero active terms without coverage; zero escalations above their type's ceiling.
