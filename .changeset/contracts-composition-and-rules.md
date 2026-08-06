---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-actions': patch
'@mj-biz-apps/contracts-server': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

A contract is now a COMPOSITION, and every entity's rules live in `BaseEntity`.

**The tree, written once.** `ContractEntityServer` could not create a contract — it had no
child collections at all — so the UI wrote an agreement as a series of separate round trips
and a failure partway left a numbered contract with nothing under it. It now composes
`Contract → Terms → {Lines, Schedules, Commitments}` and writes the whole tree in ONE
transaction, number allocation included, modelled on `JournalEntryEntityServer` one level
deeper. Loading stays lazy: `Load()` reads the header, `LoadFull()` reads the tree in four
queries whatever the term count. The shared `ChildCollection` is the single implementation
of "a parent owns child rows", and its central rule is that **un-hydrated is not empty** — a
lazily loaded parent must not conclude it has no children because nobody asked for them yet.

**Rules where they can explain themselves.** Five entities had CHECK constraints and no
server subclass, which meant the row could not be written invalid and nobody writing one
could be told why. `ContractLine`, `ContractBillingSchedule`, `ContractCommitment`,
`ContractAmendment` and `ContractType` now mirror those readably and add the rules a CHECK
cannot hold because they compare two rows — coverage inside its term, an amendment against a
RUNNING term, a schedule frozen once it has billed.

Cross-child rules are answered at the point of need rather than from a hydration flag. The
flag had a real hole: a contract loaded shallowly and switched to Active skipped the check
entirely, so the rule was correct on the path that did not need it and absent on the path
that did.

**`ContractsEngine`** brings the `BaseEngine` standard to contract types, so configuration is
read as data instead of branched on by name.

**`ContractDraft` + `Contracts.SaveContract`** give the browser a way to send a whole
agreement as one payload — framework-free, unit-testable without Angular, and validated
client-side into per-field, per-section issues so the UI can mark the input rather than print
a paragraph above the form.
