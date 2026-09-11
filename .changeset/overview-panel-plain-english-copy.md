---
'@mj-biz-apps/contracts-ng': patch
---

Contract form Overview panel and header chips: plain-English copy.

The Overview panel landed after golive #203 item 19 was written, so its strings were never put through
that copy pass and still read in developer voice — health alerts arguing why a condition matters
("the watchlist cannot see this", "a customer can walk without renewing"), a card titled "What needs a
person", and an Auto-renew subtext of "as the paper states" / "someone must act". The header chip
tooltips in `contract.panels.ts` carried duplicate wording of their own.

Each message is replaced with the verbatim copy specified on the issue: the alert states the condition,
the next-step card states the action. The card header becomes **Next step**, the Auto-renew subtext line
is dropped, the Parties card label **Selling as** becomes **Company** (golive #203 item 8) and its empty
Agreement value becomes **None**, and the Obligation card's **Created from** row is hidden when there is
no source record rather than reading "Entered directly" (golive #203 item 1).

Copy only. No getter decides differently than it did before — which messages appear, and when, is
unchanged. The one structural edit is the hidden **Created from** row, which added a `HasSource` getter
and left `CanOpenSource` alone; `SourceLabel` no longer carries the "Entered directly" fallback because
nothing renders it without a source any more.

Dates, Renewal terms, Lineage and Re-papering copy are golive #203 item 19 / contracts #36 and are not
touched here, and the dashboard intro paragraph is contracts #42.

Also fixed in passing: `Term ends ${endsInText(d)}` doubled the verb on the day a term ends — "Term ends
ends today." — and read "Term ends ended 3 days ago" behind it. The alert and the next-step line now
compose the clause through `termEndsText`, which carries the verb so it agrees with the tense
`endsInText` picked. Andrew's copy for every other day ("Term ends in 5 months.") is unchanged, and
`EndClock` still calls `endsInText` directly.
