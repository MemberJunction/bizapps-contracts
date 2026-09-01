---
'@mj-biz-apps/contracts-ng': patch
---

The contract form stops explaining itself and starts helping (#28 items 19, 21, 23 and 24).

Twelve pieces of prose described how the software works rather than what the reader should do, and they are replaced with the issue's own copy. The hero's flag becomes "Contract number is assigned on save." — how the counter avoids collisions is not a fact about this contract. The Terminated hint says what setting the date *does* ("Setting this marks the contract Terminated from this date.") instead of characterising it as "a fact about what happened". The derived-lifecycle note, the executed-date-may-precede reassurance, the orders-subscription ruling and the auto-renew aside are deleted outright. Documents loses the always-works-fallback paragraph for a plain "Open in signing provider" link, tells a user without permission "You don't have permission to open them." rather than naming the roles that do, and replaces the SharePoint/Azure AD configuration essay with "No document storage is configured. Contact your administrator."

A recorded **0** now reads "0 days" and "0%" instead of an em dash. `Record.RenewalNoticeDays ? … : '—'` conflated "zero" with "absent" — the panel reported holding no figure about a figure that says no notice is required, and those are different facts. The "No renewal terms recorded." empty state now also requires Auto-renews to be No: it previously appeared directly beneath a field reading Yes, contradicting the screen it was describing.

Re-papering messages no longer outlive what they describe. Changing the dropdown selection clears the previous success or error, so "Linked — that contract is now superseded by this agreement." cannot sit on screen while the user picks a different contract and appear to describe the new one. The candidate list is keyed on the record rather than a boolean, so navigating the form to another contract reloads it instead of offering the previous contract's candidates — filtered to the previous customer and the previous level, which is a wrong list rather than a stale one.

Also removes a section banner with no code under it.
