---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-ng': patch
---

Modifications are editable, foreign-key links navigate, and provisions read by name.

**Recording a modification works end to end.** The modification's own form rendered nothing but
"Loading the contract this modification belongs to…" — no fields, no dropdowns, no way to save. A
priority-2 `BaseFormComponent` replacement was shadowing the generated form: it loaded the parent
contract first so it could drive the inline editor through `contract.Modifications`, and that load
never completed the render. The replacement is deleted, not repaired, because the generated form is
strictly better here — CodeGen already emits `ContractID` and `ContractTemplateProvisionID` as
`LinkType="Record"`, which `mj-form-field` renders as **searchable foreign-key dropdowns**, beside a
`Modification Details` section for the negotiated language and its notes. Creating a modification is
now the same shape as creating a provision, which is what makes the two feel like one app. The
editor component remains as the contract form's inline Modifications panel — one implementation, one
host.

The general lesson, since it will recur: **replacing a form costs every generated affordance** —
foreign-key search, section grouping, validation display. Reach for a panel unless you intend to
replace all of it.

**Foreign-key links in grids now open the record they point at.** `mj-entity-data-grid` renders each
FK cell as an anchor, hit-tests the click and emits `ForeignKeyClick`; the Explorer wrapper that
forms and pages use never binds that output and declares no equivalent, so the event dies inside the
wrapper and every such link is inert while still looking clickable. A directive on each grid
subscribes to the inner component's own output and navigates, building the key from the related
entity's real primary-key field rather than assuming `ID`. It uses MJ's public API rather than
re-reading the rendered DOM, so it deletes cleanly when MJ surfaces the event —
`plans/WORKAROUNDS.md` records the trigger for removing it.

**Provisions identify themselves.** A provision's record name was its clause number alone, so tabs
read "9.1" — or "1" — with nothing to say which agreement's 9.1 it was. `Title` is now a second
name field, and MJ's multi-field record naming concatenates in `Sequence` order to give
"9.1 Liability and indemnity". Metadata only: no schema change, no view change. Grid cells keep the
compact number, which is right for a cell.

**Removed:** the field-to-nav-section map on `ContractEntity`. It restated the Angular panels'
section keys inside a package the server imports, so it was a second copy of a fact it could not see
change — those keys were renamed while it existed, and a stale entry would have compiled, returned a
section that no longer exists, and pointed the indicator at the wrong rail item without failing.
Nothing consumed it yet. Aggregating validation errors onto the section that owns the field is a gap
in MJ's form chrome rather than an app concern, and is filed as such.

**Also:** the Templates rail item reads "All templates" (parallel with "All provisions" and "All
contracts") instead of naming a different noun than its own section; the modifications page passes
the toolbar configuration it had been declaring and discarding; and five docblocks that claimed MJ's
grid ships a filter toggle are corrected — `showFilterToggle`, `AllowColumnFilters` and
`_filterState` are all declared and read nowhere, and per-column filtering is hardcoded off, so the
only filtering available today is the toolbar's client-side quick search.
