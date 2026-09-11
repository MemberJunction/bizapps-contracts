---
'@mj-biz-apps/contracts-ng': patch
---

Three places where the Re-papering panel described something other than what was on screen (#28 item 23).

**Changing the selection left the previous outcome up.** "Linked — that contract is now superseded by this agreement." stayed on screen while the user picked a different contract, reading as a description of the new selection. A success message that reports an action nobody took is worse than no message; both banners now clear when the selection changes.

**The candidate list was keyed on a boolean.** The form reuses the panel instance when it navigates, so the flag stayed true and the picker went on offering the previous contract's candidates — filtered to the previous customer and the previous level, which is a wrong list rather than a stale one. It is now keyed on the record's ID.

**A failed read stayed reported after a later one succeeded**, so the panel showed candidates and told the reader it could not read any.
