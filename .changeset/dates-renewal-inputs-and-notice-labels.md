---
'@mj-biz-apps/contracts-ng': minor
---

Edit mode on the Dates and Renewal terms panels stops changing how the form looks, and the two notice fields say which direction the notice runs (#28 items 5 and 6).

Those panels render bare native controls — `<input type="date">`, `<input type="number">`, `<select>` — because the generated datetime picker shows a time component for a `date` column, which is the reason the Dates panel exists at all. A bare control inherits none of the app's typography or chrome, so every field visibly changed font, height and border the moment you pressed Edit. The kit now styles `.mjc-field input, .mjc-field select` to mirror `.mjc-val` field for field, and the seven inline `style="width:100%"` attributes are gone in favour of that rule. `font: inherit` is the load-bearing part: form controls do not inherit font from their ancestor in any browser, so without it the value box and the input disagree however well everything else matches. The dates stay date-only — the fix is CSS, not a return to the generated control.

"Renewal notice we owe (days)" becomes **Renewal notice (days)**, with the direction moved into a hint beneath it — "Written notice we must give the customer before a renewal price change." Its mirror, "Notice to cancel (days)", gains "Notice the customer must give us to cancel." The pair is the point: one is notice we owe and one is notice we are owed, they are not the same field, and two adjacent day-counts with no stated direction is exactly how they get confused. The "deadline:" hint is unchanged — it is a different fact.

`EntityField.DisplayName` for `RenewalNoticeDays` becomes **Renewal Notice (Days)** so grids and generated forms match the panel. Unlike the `CompanyID` case in the previous change, this one is real: CodeGen strips a trailing `ID` from a foreign key but does not bracket a unit, so it derives "Renewal Notice Days" — verified against the database before adding.

Minor rather than patch: the branch now edits `metadata/`, and metadata becomes a migration at release.
