# Design plan — Contracts obligation command center

**Locked direction:** Sales-A-shaped command center, no money (plan §1).
**Charts, not ARR.** Counts, calendars, and mix — paper / notice / ending / state.

## Navigation

Already correct. `OpenEntityRecord` / `OpenNewEntityRecord`. No workspace. Do not change rails.

## Dashboard

Replace the five pills + manifesto with:

- The same four derived-column tiles (counts via `TotalRowCount` + the existing ExtraFilters so tiles cannot disagree with worklists).
- State mix bars (read `State` from the layered view — do not re-derive).
- 90-day obligation histogram (DaysToEnd buckets) + notice-vs-end split.
- Attention funnel (paper / notice / ending / modified).
- Hot list: click → `OpenEntityRecord`. Tile click still jumps to the matching worklist rail.

## Build sequence

1. Rewrite `contracts-dashboard.page.ts`
2. Kit CSS for charts (semantic tokens only)
3. Build `@mj-biz-apps/contracts-ng`
