---
'@mj-biz-apps/contracts-ng': patch
'@mj-biz-apps/contracts-entities': patch
---

Contract form: associate a manually created contract with an existing deal (golive #219, story C-US1).

A contract's provenance is the polymorphic pair `CreatingEntityID` / `CreatingRecordID`, and both
fields have rendered read-only since contracts #28 item 18 — for a reason that still holds. They sit
under `CK_Contract_CreatingPairBothOrNeither`, so editing one alone is a save the database refuses,
and editing both silently re-points a contract's history at an unrelated record. `CTR-000026` still
carries the evidence: a hand-typed pair naming `MJ: Explorer Navigation Items` with a record id that
is not a UUID. The cost was that the Close Won automation became the only writer, so a contract
entered by hand could never show the deal it belongs to, and the hero's Source Deal stat — which
renders only when both columns are set — never appeared for one.

The Provenance panel now carries a **Source deal** lookup above those fields. Choosing a deal writes
**both** halves from the one choice, and **Clear** empties both; no path through the form sets one
alone. The list starts with the deals for the contract's own customer organization — a sales account
shares its primary key with the common organization it represents, so that is a direct compare —
and typing searches every deal by name, number or customer, on the server, with the combobox's own
client-side filtering off. The deal a contract is already pointed at is kept in the list, so a
contract linked to a deal outside its customer shows what it is pointed at rather than a blank box.
The raw ids stay visible and read-only beneath, which is what keeps the provenance auditable.

A contract that arrives with provenance already recorded shows it locked behind **Change source**,
so a link written by Close Won is never re-pointed by an accidental click. The pair stays
polymorphic: the picker pre-selects only when the entity half actually names Deals, and says so when
the source is some other kind of record rather than rendering an empty control beside set ids.

**contracts still does not depend on sales.** Sales depends on this app — its Close Won seam is what
creates contracts — which is why the link is polymorphic in the first place. The Deals entity is
resolved from provider metadata by name at runtime: no import, and no entry in `mj-app.json`. An
installation without sales finds no such entity, renders no picker, and says why.

No schema, migration or metadata change; the constraint and the validator CodeGen derives from it
are unchanged and remain the last word. `Deal.ContractID` — sales' own column, which Close Won also
maintains — is deliberately not written from here, for the same dependency reason.
