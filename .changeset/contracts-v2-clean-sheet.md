---
'@mj-biz-apps/contracts-entities': minor
'@mj-biz-apps/contracts-actions': minor
'@mj-biz-apps/contracts-server': minor
'@mj-biz-apps/contracts-core-entities-server': minor
'@mj-biz-apps/contracts-ng': minor
---

Contracts is rebuilt from a clean sheet: a record of agreements, not a billing engine.

**What changed, and why it is a rebuild rather than a refactor.** v1 modelled contracts as the
thing that decides what to charge — ten tables carrying terms, lines, billing schedules,
commitments, billing events and amendments, plus a billing engine, seven remote operations and a
client-side draft object to compose it all. That was the wrong job. Orders bills; sales sells;
contracts is the **source of truth for what we agreed and where the paper is**. Nothing in the v1
schema survived except the words on a few columns, so the baseline was rewritten in place (this
repo's pre-production practice) rather than migrated forward.

**The schema is seven tables.** `Contract` is the agreement — its counterparty organisation, which
of our companies is party to it, the dates, the renewal terms *as the paper states them*, and
lineage to the contract it changes or supersedes. `ContractType` and `ContractTemplateType` are
lookups. `ContractTemplate` is one dated version of a standard-terms document (a Master Agreement)
and `ContractTemplateProvision` is one numbered clause of it, text included.
`ContractTemplateModification` is the point of the app: *this contract deviates from that
provision, and here is the negotiated language*. `ContractSequence` mints contract numbers.

Both texts are stored and read as a pair — the standard clause on the template, the negotiated one
on the modification — so a reader sees what was agreed against what was offered without opening two
records.

**There is no `Status` column.** Four of its five values were projections of the dates and the two
self-FKs, and a stored copy of a derivable fact can only agree or lie. Lifecycle is a derived
`State` on an app-owned layered base view, alongside `IsAwaitingDocument` (the contract *type*
expects paper and none is linked) and `IsChangeOrder`. `State` has six values: the sixth,
`Executed`, is signed-but-not-yet-effective, which the first cut of the derivation dropped into
`Draft` — hiding every contract signed weeks before its term starts, the ordinary case in renewal
season, behind the word for "unfinished".

**Composition is MJ's, not ours.** `Contract.Modifications` and `ContractTemplate.Provisions` are
declared as related-record collections in metadata, so CodeGen emits typed accessors on the
generated entity classes and one `contract.Save()` writes the header and its modifications in one
transaction, validated whole, in the browser and on the server alike. That is what let this release
delete `Contracts.SaveContract`, `ContractDraft` (688 lines), `ChildCollection` and the hydration
layer whose only job was carrying child rows over the wire. **The app now ships zero remote
operations.**

**Documents are assembly, not construction.** MJ already has seven storage drivers including
SharePoint, an in-app PDF viewer, and a PandaDoc eSignature driver. The one missing piece is a
record-scoped "documents on this record" panel — nothing in MJ queries `FileEntityRecordLink` at
runtime — so that panel is the only file-handling code here, and it is written entity-agnostic to
be offered upstream. Executed PDFs arrive in SharePoint by a route MJ knows nothing about, so the
flow registers an existing object rather than uploading one, with the signing provider's URL as the
always-works fallback.

**Also in this release:** contract types are now Order Form / Statement of Work / Payment Link /
Change Order, describing what the document is rather than a commercial shape; the Explorer nav is
three sections (Contracts, Templates, Configuration); and `pnpm-lock.yaml` is refreshed so
`--frozen-lockfile` resolves `vitest`, which had been declared without being locked and was failing
CI for every branch off `next`.
