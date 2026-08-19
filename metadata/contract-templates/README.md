# `contract-templates/` and `contract-provisions/` — the agreement versions and their clauses

**Seeded: the Master Agreement dated 2026-02-02 — 16 sections, 71 numbered provisions, every one with
its verbatim text.** Captured from `https://bluecypress.io/masteragreement20260202/` on 2026-08-18.
This is plan item 4, and it is a prerequisite rather than a nicety:
`ContractTemplateProvisionID` is mandatory on a modification, so finance could not record a single
modification until this list existed.

## ⚠ If you ever recapture this, parse the SOURCE — never a summary

The clause text is the actual wording of a document the business signs, and a summarising pass over it
is not a smaller version of the truth, it is a different document that looks authoritative. Measured,
on this exact page: a summarised fetch returned 9.1's limitation of liability in **sentence case
instead of the original ALL CAPS**, and turned 1.1's *"shall mean the particular company"* into
*"means the company"*. Capitalisation in a liability clause can carry legal weight, and
`ProvisionText` exists so finance reads the standard clause **beside** the negotiated one (D-16) — so
a paraphrase there is worse than a null, because nothing downstream marks it synthetic.

The capture that shipped parses the page's HTML, joins inline tags so links inside a clause survive
(1.1 contains a URL), splits only on block elements, and then integrity-checks the result.

## Adding the NEXT version

Two files, same shape as what is here. `directoryOrder` in `metadata/.mj-sync.json` sequences them:
template types → templates → provisions. A new agreement is a **new template row**, never an edit to
this one — signed contracts reference this version, and rewriting it would silently change what they
say they incorporate.

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
