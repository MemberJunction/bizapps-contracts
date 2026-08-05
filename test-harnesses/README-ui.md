# Browser harnesses — what covers what

`ui-workspace.mjs` is the browser suite. **57 assertions**, one run, driving the real Explorer.

## Why there is one and not seven

Until 2026-08-05 there were seven, written against a UI with a separate **create page** and a
separate **workspace**. Consolidating those two surfaces into one (see the commit
"three sections, and ONE surface that views, edits and creates") removed the DOM six of them drove.
They did not fail because the app broke; they failed because the thing they described stopped
existing.

They were folded into `ui-workspace.mjs` rather than repointed one by one, because six harnesses
each navigating to the same surface and creating their own contract cost six browser launches and
six contracts to clean up, for coverage that overlaps almost completely.

**Every assertion has a home. The map, so nothing is lost quietly:**

| Retired harness | What it proved | Where it lives now |
|---|---|---|
| `ui-create-to-active` | create a contract WITH coverage, then activate its term | §5–§7 (create + coverage + save), §10.1–10.2 (activation) |
| `ui-full-loop` | create → activate → renew → terminate | §7, §10, §12 |
| `ui-lifecycle` | activation schedules events; renewal previews | §10.2, §10.5–10.6 |
| `ui-terminate` | terminate offers a reason; cancelled/retained split | §12.1–12.7 |
| `ui-history` | the append-only audit trail renders | §11.1 |
| `ui-navigation` | rail navigation, search finds one contract | §1 (sections), §13 (search) |

## The one thing that did NOT survive, and is not pretended otherwise

`ui-form-editing.mjs` proved that **MJ's form presenter mounts a REAL form** for a term — populated
with the record asked for, and leaving it alone on cancel. The consolidated workspace edits terms,
coverage, schedules and commitments with **hand-built field sets inline**, so there is no slide-in
to assert and that coverage is genuinely GONE rather than relocated.

That is a gap, not a decision. Presenting those rows through the 4-layer architecture
(`MJFormPresenterService` over the priority-2 custom forms, which Term and Line already have) is
outstanding work — tracked, and the harness should be restored with it rather than rewritten from
scratch. The retired file is in git history at the commit that removed it.

## Running it

```sh
URL=$(mjdev explorer-url contracts-dev | grep -oE 'http://localhost:[0-9]+/#token=[A-Za-z0-9._-]+')
node test-harnesses/ui-workspace.mjs "$URL"
```

**It WRITES.** Its contract is tagged `UI-E2E workspace …`; `demo/cleanup-ui-e2e.sql` removes
`UI-E2E` rows, and that is also how a crashed run is cleaned up. Pristine demo state is 1 contract,
3 terms, 3 lines, 4 audit events, 3 billing events (2 scheduled + 1 failed).
