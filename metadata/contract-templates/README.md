# `contract-templates/` and `contract-provisions/` — the agreement versions and their clauses

**These folders are wired and deliberately EMPTY of records.** Plan item 4 is the seed of the current
Master Agreement's provision list, and it is the one seed in this app that cannot be derived from the
plan, the transcript or the rulings: it is the **actual wording of a document the business signs**.
Committing plausible-looking clause text would install it into a real database and put it on screen
beside a customer's negotiated language, with nothing downstream marking it synthetic. That failure is
silent and its blast radius is legal, so the content is deferred rather than guessed —
`plans/QUESTIONS.md` **Q-5** asks for the document.

Nothing structural is blocked by the gap. The schema, the `Provisions` collection, the registry UI
(item 7) and the modification editor (item 8) are all built and testable against provisions created
through the UI. What IS blocked is real use: `ContractTemplateProvisionID` is mandatory on a
modification, so **finance cannot record a modification until the real list exists.**

## Dropping in the real list

Two files. `directoryOrder` in `metadata/.mj-sync.json` already sequences them: template types →
templates → provisions.

**`.contract-templates.json`** — one record per MA VERSION, ever. A version is never edited in place;
a new agreement means a new row, and the old one stays because signed contracts still reference it.

```json
[
  {
    "fields": {
      "Name": "Master Agreement — 2026 edition",
      "ContractTemplateTypeID": "@lookup:MJ_BizApps_Contracts: Contract Template Types.Name=Master Agreement",
      "VersionLabel": "2026.1",
      "IntroducedDate": "2026-01-01",
      "SourceURL": "https://…/master-agreement-2026-01-01.pdf",
      "Description": "The standard terms every Order Form and Payment Link incorporates from 2026-01-01."
    },
    "primaryKey": { "ID": "33333333-0000-4000-8000-000000003001" }
  }
]
```

`SourceURL` is **NOT NULL** on purpose (ERD): a template version nobody can open is a row that claims
to be the standard terms and cannot prove it. Use the dated URL, not a "current" link that changes
underneath the record.

**`.contract-provisions.json`** — one record per numbered clause, `@parent`-referenced to its template
so the file carries no copy of the template's id:

```json
[
  {
    "fields": {
      "ContractTemplateID": "@parent:ID",
      "ProvisionNumber": "4.2",
      "Title": "Limitation of Liability",
      "ProvisionText": "The full text of the clause, verbatim.",
      "Sequence": 12
    },
    "primaryKey": { "ID": "33333333-0000-4000-8000-000000004012" }
  }
]
```

Three things that will bite:

- **`Sequence` is what orders them, not `ProvisionNumber`.** Provision numbers do not sort as text —
  `'10'` sorts before `'2'`, and real agreements use `4.2.1` forms. The `Provisions` collection
  maintains `Sequence` gap-free (`{"Field":"Sequence","From":1}`), so set it to the reading order of
  the document and let the collection renumber after edits.
- **`ProvisionText` is nullable so an incomplete capture never blocks listing the provisions** — but
  the seed should be complete. A provision with a number and no text is a picker entry finance cannot
  read the standard clause from, which is half the point of D-16.
- **Fixed UUIDs, never `NEWID()`.** A re-push against a rebuilt database must UPDATE these rows rather
  than mint a second set. The blocks reserved here: templates `…3xxx`, provisions `…4xxx`.

## Entering it by hand instead

If there is no machine-readable source, item 7's registry UI is the sanctioned path — the template form
with its Provisions editor writes through the **same** collection this seed does, so a list typed once
in the UI is indistinguishable from a seeded one. `mj sync pull --dir metadata` then captures it back
into these files, which is the cheapest way to produce them.
