---
'@mj-biz-apps/contracts-ng': minor
---

Bare form controls on the custom panels no longer change how the form looks when you press Edit (#28 item 5, kit half).

Those panels render native `<input type="date">`, `<input type="number">` and `<select>` because the generated datetime picker shows a time component for a `date` column. A native control inherits none of the app's typography or chrome, so a field visibly changed font, height and border on entering edit mode. The kit now styles `.mjc-field input, .mjc-field select` to mirror `.mjc-val` field for field, plus focus-visible and disabled states. `font: inherit` is the load-bearing declaration: form controls do not inherit font from their ancestor in any browser, so matching padding, border, radius and height was not enough on its own.

`EntityField.DisplayName` for `RenewalNoticeDays` becomes **Renewal Notice (Days)**, so grids and generated forms bracket the unit. CodeGen strips a trailing `ID` from a foreign key but does not bracket a unit, so it derived "Renewal Notice Days" — checked against the database rather than assumed.

Minor rather than patch: the branch edits `metadata/`, and metadata becomes a migration at release.
