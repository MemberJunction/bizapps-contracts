# Browser harnesses — what covers what

Three files, each answering a different question. Counts are from the run on 2026-08-06.

| File | Question it answers | Assertions |
|---|---|---|
| `ui-workspace.mjs` | Does the app DO the things? Create, save, activate, renew, amend, terminate — driven through the real Explorer. | 96 |
| `ui-layout.mjs` | Does it LOOK right, at any window size? Every page in every section at three viewports, plus the workspace access model. | 179 |
| `erd-schema-diff.ts` | Does `docs/ERD.md` still describe the schema that exists? Diagram blocks diffed against `sys.columns`, plus the header's five counts. | 45 |

`ui-layout.mjs` exists because a suite that renders ONE window size cannot see a layout that depends
on the window size — which is precisely the bug that produced pages with content stacked into a
column on the right. `erd-schema-diff.ts` exists because every prior "check the ERD" pass was a
throwaway script, run once and lost, which is why the drift kept coming back.

Run them the same way (`erd-schema-diff.ts` needs no browser, only the instance `.env`):

```sh
URL=$(mjdev explorer-url contracts-dev | grep -oE 'http://localhost:[0-9]+/#token=[A-Za-z0-9._-]+')
node test-harnesses/ui-workspace.mjs "$URL"
node test-harnesses/ui-layout.mjs "$URL"
npx tsx test-harnesses/erd-schema-diff.ts
```

`ui-workspace.mjs` WRITES — see the cleanup note below. The other two are read-only.

---

## The consolidation that produced `ui-workspace.mjs`

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

## The last one, which briefly had no home

| `ui-form-editing` | MJ's presenter mounts a REAL form, populated with the right record, left alone on cancel | §10b.1–10b.5 |

This one was genuinely GONE for about an hour, and was recorded as a gap rather than glossed over:
the consolidated workspace first edited every row with hand-built field sets inline, so there was no
slide-in to assert. Wiring `MJFormPresenterService` into the panes closed it the same day, and the
coverage came back stronger than it left.

The inline fields did not go away, and that is deliberate: a form needs a RECORD to open, and a row
being composed does not have one yet. So the draft is how a contract is assembled and the form is
how a saved record is edited — the Form button appears only once the row exists, which is what makes
the distinction visible rather than a rule to remember.

One authoring note worth keeping: §10b.3 reads the form's INPUT VALUES rather than its innerText. A
field's value is an attribute and never appears in rendered text, so an innerText check there passes
or fails for reasons unrelated to whether the form loaded the record — the same class of mistake as
a loose locator.

## Running it

```sh
URL=$(mjdev explorer-url contracts-dev | grep -oE 'http://localhost:[0-9]+/#token=[A-Za-z0-9._-]+')
node test-harnesses/ui-workspace.mjs "$URL"
```

**It WRITES.** Its contract is tagged `UI-E2E workspace …`; `demo/cleanup-ui-e2e.sql` removes
`UI-E2E` rows, and that is also how a crashed run is cleaned up. Pristine demo state is 1 contract,
3 terms, 3 lines, 4 audit events, 3 billing events (2 scheduled + 1 failed).
