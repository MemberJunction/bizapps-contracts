# Design brief — Contracts obligation dashboard

**Status:** exploration. Pairs with `bizapps-sales/plans/pipeline-command-center/`.

## Architecture (already correct)

Rails: dashboard / all contracts / renewals / awaiting / modifications.
Grids: `mj-explorer-entity-data-grid`.
Record open: `NavigationService.OpenEntityRecord` / `OpenNewEntityRecord`.
No in-rail workspace. Marcelo did not repeat the sales/orders mistake.

## What’s thin

`contracts-dashboard.page.ts` is five count pills (in force without paper, notice window 60d, ends in 120d, signed not started, modified) plus a manifesto card. The counts are the right *questions* — they read the layered view’s derived columns so they cannot disagree with the worklists — but there is no calendar, no hot list, and no way to inspect without leaving for another rail.

## Constraint from plan §1

Contracts is not money. No ARR, no TCV, no billing. Health is paper, notice, state, and modifications.

## Recommendation

Option A — 90-day calendar + the four derived-column tiles + a hot list. Click = Explorer tab.
