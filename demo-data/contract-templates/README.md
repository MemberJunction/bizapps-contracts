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

Two files, same shape as what is here. `directoryOrder` in `demo-data/.mj-sync.json` pushes
templates before provisions; template types are vocabulary in `metadata/contract-template-types/`,
which an install already has. A new agreement is a **new template row**, never an edit to this one —
signed contracts reference this version, and rewriting it would silently change what they say they
incorporate.

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
    "primaryKey": { "ID": "33333333-0000-4000-8000-000000003002" }
  }
]
```

`…3001` and `…4001`–`…4071` are taken by the 2026-02-02 version; reusing one would overwrite it.

`SourceURL` is nullable (baseline, `ContractTemplate`). The rule is "a URL or an attached document",
and a document cannot attach to a row that does not exist yet, so the column cannot require it.
Publishing enforces it (`ContractTemplateEntityServer`), and `IsUsable` on `vwContractTemplates`
shows which versions can be read. Use the dated URL, not a "current" link that changes underneath
the record.

**`.contract-provisions.json`** — one record per numbered clause, in its own folder, naming its
template by the template's fixed ID (`@parent:` only resolves inside a parent record's nested
collection, which a separate folder is not):

```json
[
  {
    "fields": {
      "ContractTemplateID": "33333333-0000-4000-8000-000000003002",
      "ProvisionNumber": "4.2",
      "Title": "Limitation of Liability",
      "ProvisionText": "The full text of the clause, verbatim."
    },
    "primaryKey": { "ID": "33333333-0000-4000-8000-000000004072" }
  }
]
```

Four things that will bite:

- **Order comes from `ProvisionNumber`; there is no order column to set.** Provision numbers do not
  sort as text — `'1.10'` sorts before `'1.9'`, and real agreements use `4.2.1` forms — so the table
  carries `ProvisionSortKey`, a persisted computed column over `fnProvisionSortKey(ProvisionNumber)`,
  and the `Provisions` collection orders by it. Nothing can write it; get the numbers right.
- **`ProvisionText` is required**: `NOT NULL`, and `CK_ContractTemplateProvision_TextNotBlank` refuses
  text that is empty once spaces are trimmed. A partial capture cannot be pushed.
- **Push the template as `Draft` with all its provisions, then publish.** Once a version is
  `Published`, `trg_ContractTemplateProvision_Immutability` refuses any provision added to it and any
  change to a clause's number, title or text. A re-push of identical values still passes.
- **Fixed UUIDs, never `NEWID()`.** A re-push against a rebuilt database must UPDATE these rows rather
  than mint a second set. The blocks reserved here: templates `…3xxx`, provisions `…4xxx`.

## Entering it by hand instead

If there is no machine-readable source, item 7's registry UI is the sanctioned path — the template form
lists provisions in MJ's stock related-entity grid, and a provision added there is the same
`ContractTemplateProvision` row this seed writes, so a list typed once in the UI is indistinguishable
from a seeded one. A pull then captures it back into these files, which is the cheapest way to
produce them:

```bash
pnpm exec mj sync pull --entity "MJ_BizApps_Contracts: Contract Templates" --target-dir demo-data/contract-templates
pnpm exec mj sync pull --entity "MJ_BizApps_Contracts: Contract Template Provisions" --target-dir demo-data/contract-provisions
```
