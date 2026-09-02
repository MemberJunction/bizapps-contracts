---
'@mj-biz-apps/contracts-ng': minor
---

Rebuild the Contracts dashboard as four tiles over the book of agreements (#30).

The page now extends MJ's `BaseDashboard` — the pattern MJ itself uses for sub-pages of a
left-nav shell — so it gets `loadData()`/`Refresh()`, an `Error` output the section renders,
and a guaranteed `NotifyLoadComplete()` it previously never called at all. Charts, funnel,
horizon buckets and the hot list are gone; what replaces them is four counts (to process,
awaiting executed document, notice deadlines, clients with special terms) over a grid of
active and executed contracts, filtered by a multi-select Company chip group.

Tile clicks carry a filter preset to the destination worklist, so a tile lands on the list it
just counted rather than on an unfiltered one. Declares `mj-bizapps-tasks` as a dependency:
the "to process" tile and the new "Has open task" pill read Tasks, and the finance flow is
task-driven.
