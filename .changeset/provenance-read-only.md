---
'@mj-biz-apps/contracts-ng': patch
---

The polymorphic provenance pair can no longer be typed over (#28 item 18, completing it).

`CreatingEntityID` and `CreatingRecordID` rendered as ordinary inputs in Edit mode even though the server owns them — `LiveContractsSeam.setProvenance` sets the pair on Close-Won and nothing else should. `CreatingEntityID` is a real FK to `__mj.Entity` and `CreatingRecordID` is the row it names, with `CK_Contract_CreatingPairBothOrNeither` requiring both or neither, so editing one field alone produced a save the constraint refused and editing both silently re-pointed a contract's provenance at an unrelated record — which is then what the header's Source Deal link displays. Both are now read-only, joining Contract Number, Has Modifications and Superseded By Contract.

**The Provenance section is kept, which item 18 says to hide.** Its stated reason is that item 1's Source Deal link replaces the section, and that is not yet true: the link renders only when both provenance columns are set, and one contract of eleven has them — a hand-typed pair naming `MJ: Explorer Navigation Items` with a record id that is not a valid UUID. On every contract a person can currently open, the replacement is invisible, so hiding the section would remove the only visible provenance in exchange for a stat that does not appear. Worth revisiting once a contract created by a real Close-Won deal exists to verify item 1 against.
