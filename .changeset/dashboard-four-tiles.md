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

The tile-4 count's `CompanyIDs` parameter is declared in the query's metadata rather than left to
the server's query-extraction pipeline to infer. MJ's parameter processor rejects any parameter a
query does not declare, so on a host seeded by a route that does not run extraction the tile failed
every read and rendered a dash. `query-categories` and `queries` also join `directoryOrder`: an
unlisted folder is pushed in alphabetical order, which put the queries ahead of the category they
look up by name and broke a push against an empty database — the exact shape of the release capture.
