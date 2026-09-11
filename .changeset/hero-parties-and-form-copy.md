---
'@mj-biz-apps/contracts-ng': patch
---

The hero names its two parties the way the rest of the app does, and the form stops explaining itself (#28 items 8 and 19).

The selling company's stat was labelled "Selling", a word that appeared on no other surface and matched no field a user could go looking for — the column is `CompanyID` and every grid calls it Company. It is now **Company**, and it comes before **Customer**: our company first, then the counterparty, which is how the agreement itself reads. No metadata change is needed; CodeGen strips a trailing `ID` from a foreign key and already derives "Company", the same rule that makes `CustomerOrganizationID` read "Customer Organization".

Eight pieces of prose described how the software works rather than what the reader should do. The hero's flag becomes "Contract number is assigned on save." — how the counter avoids a collision is not a fact about this contract. The Terminated hint says what setting the date *does* rather than characterising it as "a fact about what happened". The derived-lifecycle note, the executed-date-may-precede reassurance, the orders-subscription ruling and the auto-renew aside are deleted. The Renewal and Lineage empty states name what is absent instead of characterising the contract. The "as stated in the agreement" chip stays, as specified.

Both items shipped once before and were reverted when `origin/next` rewrote the contract form; this re-applies them against its collapsible hero and stat grid. Item 19's three Documents replacements are **not** included: next replaced the custom Documents panel with MJ stock attachments, so they need re-scoping against the new mechanism rather than porting.
