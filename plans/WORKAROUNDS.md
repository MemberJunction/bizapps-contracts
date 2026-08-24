# Workarounds carried by this app

Every place this app compensates for something outside its own code — an MJ gap, a platform
behaviour we cannot change from here. Marcelo asked for these to be logged rather than left as
quiet cleverness, so each entry states **what breaks without it**, **why the fix is not in MJ yet**,
and **how to delete it** when MJ closes the gap.

An entry leaves this file only when the workaround is *removed*, not when it stops bothering anyone.

---

## W-1 · The Explorer grid wrapper swallows foreign-key clicks

**Carried by:** `packages/Angular/src/lib/directives/fk-navigate.directive.ts`, applied to every
`<mj-explorer-entity-data-grid>` in `lib/pages/*` and `lib/form-panels/organization.panels.ts`.

**What breaks without it.** Nothing errors — that is the problem. `mj-entity-data-grid` renders
every FK cell as a blue underlined anchor (`.cell-fk-link`), hit-tests the click, and emits
`ForeignKeyClick` carrying the related entity + FK value (`entity-data-grid.component.ts` →
`onAgCellClicked`). The wrapper the forms and our pages use — `mj-explorer-entity-data-grid` — binds
`AfterRowDoubleClick`, `AfterRowClick`, `AfterDataLoad` and `NewRecordTabRequested` on the inner
grid, **and nothing else**, and declares no `ForeignKeyClick` output of its own. So the event dies
inside the wrapper and every FK link in every wrapper-hosted grid is inert while still *looking*
clickable. Marcelo hit it on the Modifications grid within a minute of opening the app.

**Why not fixed in MJ.** It should be — it is a one-output change on the wrapper, and it affects
every app that uses it, not just ours. We do not own MJ here and cannot push to it, so the fix is
filed rather than applied. **Report it upstream** (`MJ-UPSTREAM.md` at the workspace root).

**How to delete this workaround.** When the wrapper exposes `ForeignKeyClick`: delete the directive,
drop `mjcFkNavigate` + the import from the five files, and bind `(ForeignKeyClick)` instead. The
directive deliberately uses MJ's public API (the wrapper's public `innerGrid` ViewChild and the inner
component's own `@Output`) rather than re-reading the DOM `data-*` attributes, so behaviour is
identical either way.

---

## W-2 · `mjdev app migrate` cannot boot on this instance

**Not carried in code** — a procedure to know about.

`mjdev app migrate contracts-mj6 bizapps-contracts` fails at provider boot with
`[Fatal] Cannot read properties of undefined (reading 'Instance')` and exits 1 without applying
anything. The plain MJ CLI applies the same migrations fine, from the MJ worktree:

```sh
cd instances/contracts-mj6/mj
npx mj migrate --dir ../bizapps-contracts/migrations --schema __mj_BizAppsContracts
```

Verified 2026-08-19 (one migration applied in 0.1s after the mjdev path had just failed). Related to
the known deadlock note on big from-zero runs, but distinct — this fails instantly, at boot, on a
one-statement migration. **Belongs in `MJDEV-ISSUES.md`.**

---

## W-3 · Metadata edits need an API restart before the UI reflects them

**Not carried in code** — a rule that cost 45 minutes to learn properly.

MJAPI caches entity metadata at boot. A migration that changes `__mj.EntityField` (e.g.
`DefaultInView`) is correct in the database immediately and **invisible in Explorer until MJAPI is
restarted** — `mjdev restart <slug> api`. Measured twice on 2026-08-19: a grid kept rendering
columns whose `DefaultInView` was already `0` in SQL, then changed on the next restart.

The trap is that this looks exactly like a broken migration. Check the DB value first, then restart
before concluding anything. There is a second, independent cache in the same area: the grid persists
a per-user default column set as a `__mj.UserSetting` row keyed
`default-view-setting/<Entity Name>`, which pins columns for that persona regardless of metadata.
