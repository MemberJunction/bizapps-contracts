---
'@mj-biz-apps/contracts-ng': patch
---

Re-papering's copy reads as sentences, and its messages no longer outlive what they describe (#28 items 19 and 23, re-papering parts).

The two chips become "Finish editing to change" and "Save this contract first". Changing the dropdown selection now clears the previous success or error, so "Linked — that contract is now superseded by this agreement." cannot sit on screen while the user picks a different contract and appear to describe the new one; a stale success reports an action nobody took. The candidate list is keyed on the record rather than a boolean — the form reuses the component instance when it navigates, so a stale flag left the previous contract's candidates on screen, filtered to the previous customer and level, which is a wrong list rather than a stale one.
