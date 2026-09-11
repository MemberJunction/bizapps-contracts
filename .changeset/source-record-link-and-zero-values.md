---
'@mj-biz-apps/contracts-ng': patch
---

The header names the record that created a contract, a recorded zero stops reading as "not recorded", and edit-mode controls get their width from the kit (#28 items 1, 21 and 5's panel half).

The "Created from" stat rendered `CreatingEntity` — the name of an entity, not a record — so a contract raised from a Close-Won deal read "Deals" and one entered by hand read "Entered directly". Neither told the reader which deal. It is now a **Source Deal** stat carrying the deal's own name, clickable through to the record, and absent entirely when there is no source. Nothing is hardcoded to Deals: `CreatingEntityID`/`CreatingRecordID` is a polymorphic pair, so the entity is resolved from the id and the label takes that entity's own singular name — an Order would read "Source Order" with no code change. Navigation reuses the panel's existing `open()` helper, the one Customer and Contact use, so ctrl/cmd-click opens a new tab like every other link on the form.

A recorded `0` now reads "0 days" and "0%". `Record.X ? … : '—'` conflated zero with absent, so the panel reported holding no figure about a figure that says no notice is required. The "No renewal terms recorded." empty state now also requires Auto-renews to be No — it previously appeared directly beneath a field reading Yes.

The seven inline `style="width:100%"` attributes are gone; the kit's `.mjc-field input, .mjc-field select` rule carries the width along with everything else that makes edit mode match read mode.

All three shipped once before and were reverted when `origin/next` rewrote the contract form; this re-applies them against its stat grid.
