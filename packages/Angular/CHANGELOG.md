# @mj-biz-apps/contracts-ng

## 0.7.1

### Patch Changes

- @mj-biz-apps/contracts-entities@0.7.1

## 0.7.0

### Minor Changes

- b74653c: Contract lifecycle and dates are judged on the business day (bc-aidp-next-golive#168).

  `vwContracts` compared every date against the server's UTC calendar day, which is already tomorrow
  for the whole American evening: a contract ending 31 December read as Expired from 6 PM Central on
  the 31st (CST is UTC-6; on CDT the roll is an hour later), and `DaysToEnd`, `DaysUntilNoticeDeadline`,
  `NonRenewalOutcome` and the cancellation window all moved an evening early. The view now cross joins
  bizapps-common's `fnBusinessToday()` once and compares all nine boundaries against `bt.Today`, the
  calendar day in the instance's business time zone. The dates panel's `AsInput`/`SetDate` delegate to
  the shared calendar-day helpers, which also fixes an offset-bearing stored value rendering as the
  next day and an unreadable one being written as an `Invalid Date`. First dependency on
  `@mj-biz-apps/common-entities`.

  Every other reader of "today" moves with it, because half a fix is worse than none: before the
  migration the view and the UI were both on the UTC day and AGREED, so nothing looked broken. The
  "Notice window open"/"passed" pills, the dashboard's notice-deadline tile, the left-nav renewals badge
  and the overdue-task fragment took their day from `CAST(GETUTCDATE() AS date)`, and the Overview
  panel's `NoticeClock`, `NoticeTone`, `Health` and `NextMove` computed it from the UTC clock — so from
  6 PM Central a contract the view still gave notice time on had already dropped out of the pill, and
  one card printed `DaysToEnd` from the view next to a countdown a day ahead of it.

  They read the VIEW's own answer now, not a second clock. `DaysUntilNoticeDeadline` is
  `DATEDIFF(day, bt.Today, RenewalNoticeDeadline)` in the same row as the `DaysToEnd` and `State` beside
  it, so the four notice predicates become `>= 0` / `< 0` / `BETWEEN 0 AND n` (`lib/data/business-day.ts`,
  stated once for the pill, the tile and the badge) and the Overview reads the column instead of
  recomputing it. A predicate with no clock in it has no hour at which it can be a day out, and no
  dependence on a browser clock or a cached engine setting. `Tasks.DueAt` is the one column with no
  day-count of ours to read, so its comparison resolves `fnBusinessToday()` in SQL — the same function,
  the same configuration row, evaluated per query exactly as `GETUTCDATE()` was.

  Read-only dates stop rendering a day early too. The four `DATE` columns, the hero's three date stats
  and the renewal deadline hint went through Angular's `| date` pipe, which formats in the VIEWER'S
  zone — so one screen showed 31 Dec in the date input and 30 Dec in the read-only field beside it.
  They render from UTC parts now, like every other calendar-day reader.

  The same migration restores issue #28 item 16, which `V202609202354` reverted when it re-created the
  view: `IsAwaitingDocument` counts only a file in the 'Executed Agreement' category again, and
  `contract-state.test.ts` now resolves the newest definer whichever spelling it uses, so the next
  re-creation that drops a decision fails instead of passing silently.

  ⚠ Requires `[__mj_BizAppsCommon].[fnBusinessToday]()` from bizapps-common; the migration fails with a
  readable message if it is not applied first.

### Patch Changes

- Updated dependencies [b74653c]
  - @mj-biz-apps/contracts-entities@0.7.0

## 0.6.0

### Patch Changes

- Updated dependencies [19038df]
  - @mj-biz-apps/contracts-entities@0.6.0

## 0.5.0

### Minor Changes

- 8b87cd4: Rebuild the Contracts dashboard as four tiles over the book of agreements (#30).

  The page now extends MJ's `BaseDashboard` — the pattern MJ itself uses for sub-pages of a
  left-nav shell — so it gets `loadData()`/`Refresh()`, an `Error` output the section renders,
  and a guaranteed `NotifyLoadComplete()` it previously never called at all. Charts, funnel,
  horizon buckets and the hot list are gone; what replaces them is four counts (to process,
  awaiting executed document, notice deadlines, clients with special terms) over a grid of
  active and executed contracts, filtered by a multi-select Company chip group.

  Tile clicks carry a filter preset to the destination worklist, so a tile lands on the list it
  just counted rather than on an unfiltered one. Declares `mj-bizapps-tasks` as a dependency:
  the "to process" tile and the new "Has open task" pill read Tasks, and the finance flow is
  task-driven.

  `query-categories` and `queries` join `directoryOrder`. An unlisted folder is pushed in alphabetical
  order, which put the queries ahead of the category they look up by name and broke a push against an
  empty database — the exact shape of the release capture.

  The tile-4 count's `CompanyIDs` parameter row is left to the server's query-extraction pipeline
  rather than declared in `metadata/`. Declaring it cannot work: extraction runs synchronously inside
  the query's own save and writes the row first, so a declared row collides on
  `UQ_QueryParameter_QueryID_Name`, and extraction would overwrite its fields on the next SQL change
  in any case. The row still reaches a host, because the release `Metadata_Sync` capture is the SQL
  logger's output from an in-process push and includes extraction's writes.

- 19f851d: Default a new contract's template to the current published version (golive #218).

  Story C-US1 says `ContractTemplateID` starts on the current template and the user corrects it
  if the executed document cites an older version. Nothing defaulted it, so every new Order Form,
  Statement of Work and Payment Link opened with the field empty — and all three carry
  `TemplateRequired = 1`, so the save was refused until the user found the picker themselves.

  The Agreement panel now fills the field when a new contract is opened with a type already set,
  and again whenever the type is changed on an unsaved one. The candidate is the newest
  `Published` template with `IsUsable = 1`, ordered by `IntroducedDate` — both clauses restate what
  `ContractEntityServer.refuseUnusableTemplate()` enforces on save, so the default can never offer
  something the server then rejects.

  A default also LEAVES with the type that supplied it: change an Order Form to a Change Order and
  the template the form filled in is withdrawn. Nothing downstream would have caught it otherwise —
  the server refuses a MISSING template on a type that requires one and says nothing about a present
  one on a type that does not, so the contract would have saved claiming to incorporate standard
  terms nobody chose.

  What it will not do: touch a saved contract, or touch a template the user picked by hand — that one
  is neither overwritten nor withdrawn. It never defaults onto a Change Order, which carries
  `TemplateRequired = 0` and no template of its own. A contract type that cannot be READ decides
  nothing in either direction, which is why the type read is three-way rather than a boolean: folding
  a failed query into "does not require one" would quietly withdraw a legitimate default. A failed or
  empty template read is silent — the field stays empty and the picker still works.

  Scoping was the issue's one open decision: the newest published usable template wins regardless
  of template type. `ContractType` carries no `ContractTemplateTypeID`, so there is nothing in the
  data to scope by, and of the two seeded template types only Master Agreement has templates behind
  it — Statement of Work is seeded deliberately unused.

  The four decisions (`CurrentTemplateFilter`, `CurrentTemplateOrderBy`, `ShouldDefaultTemplate`,
  `ShouldWithdrawDefaultTemplate`) live in `contracts-entities`, where a unit test reaches them
  without standing up Angular's DI — the same split as `supersede-candidates.ts`. Defaulting and
  withdrawing read one shared comparison for "is this value ours", so the two directions cannot
  drift apart.

- e0d98c4: Contract Types carry renewal defaults, and a new contract starts from them (golive #217 / C-US1).

  Story C-US1 says the renewal-obligation fields on a new contract are seeded from the selected
  Contract Type. Nothing implemented it: `ContractType` had no default columns at all, so finance
  typed `AutoRenew`, `RenewalNoticeDays`, `CancellationWindowDays` and `AnnualIncreasePercent` by hand
  on every contract, including the ones whose type already determines the answer.

  `ContractType` gains four nullable columns — `DefaultAutoRenew`, `DefaultRenewalNoticeDays`,
  `DefaultCancellationWindowDays`, `DefaultAnnualIncreasePercent` — editable on its generated form
  (reached from Configuration) in a new **Default Contract Terms** section. The three numeric ones
  mirror the contract's own columns exactly, precision and `>= 0` check included, so a default that is
  legal on the type can never seed a contract that will not save.

  **`DefaultAutoRenew` is nullable although the column it seeds is not.** A type needs three answers —
  renews, does not renew, and _no opinion_ — and NULL is the third. Every existing row starts there,
  so an install that never opens Configuration behaves exactly as it does today.

  On an **unsaved** contract, choosing or changing the type copies those defaults onto the four fields.
  Three rules govern it: a field the user has typed into is never overwritten; a field the new type
  says nothing about is restored to what it held before any seeding, so a default leaves with the type
  that supplied it; and saved contracts are untouched entirely, because every value on one — blanks
  included — was entered by somebody reading the paper.

  Nothing reads these columns at save time and nothing validates against them. They are a starting
  point, unlike the type's `MustBeRoot` / `MustBeChild` / `TemplateRequired`, which are rules the
  server enforces. The seeding trigger watches the record rather than a field-change event, because
  `ContractTypeID` is editable both in the Agreement panel and in the generated Details section and a
  hook on one of them would seed from one path and not the other.

### Patch Changes

- Updated dependencies [19f851d]
- Updated dependencies [e0d98c4]
  - @mj-biz-apps/contracts-entities@0.5.0

## 0.4.2

### Patch Changes

- 3f0d3b1: Contract form: associate a manually created contract with an existing deal (golive #219, story C-US1).

  A contract's provenance is the polymorphic pair `CreatingEntityID` / `CreatingRecordID`, and both
  fields have rendered read-only since contracts #28 item 18 — for a reason that still holds. They sit
  under `CK_Contract_CreatingPairBothOrNeither`, so editing one alone is a save the database refuses,
  and editing both silently re-points a contract's history at an unrelated record. `CTR-000026` still
  carries the evidence: a hand-typed pair naming `MJ: Explorer Navigation Items` with a record id that
  is not a UUID. The cost was that the Close Won automation became the only writer, so a contract
  entered by hand could never show the deal it belongs to, and the hero's Source Deal stat — which
  renders only when both columns are set — never appeared for one.

  The Provenance panel now carries a **Source deal** lookup above those fields. Choosing a deal writes
  **both** halves from the one choice, and **Clear** empties both; no path through the form sets one
  alone. The list starts with the deals for the contract's own customer organization — a sales account
  shares its primary key with the common organization it represents, so that is a direct compare —
  and typing searches every deal by name, number or customer, on the server, with the combobox's own
  client-side filtering off. The deal a contract is already pointed at is kept in the list, so a
  contract linked to a deal outside its customer shows what it is pointed at rather than a blank box.
  The raw ids stay visible and read-only beneath, which is what keeps the provenance auditable.

  A contract that arrives with provenance already recorded shows it locked behind **Change source**,
  so a link written by Close Won is never re-pointed by an accidental click. The pair stays
  polymorphic: the picker pre-selects only when the entity half actually names Deals, and says so when
  the source is some other kind of record rather than rendering an empty control beside set ids.

  **contracts still does not depend on sales.** Sales depends on this app — its Close Won seam is what
  creates contracts — which is why the link is polymorphic in the first place. The Deals entity is
  resolved from provider metadata by name at runtime: no import, and no entry in `mj-app.json`. An
  installation without sales finds no such entity, renders no picker, and says why.

  No schema, migration or metadata change; the constraint and the validator CodeGen derives from it
  are unchanged and remain the last word. `Deal.ContractID` — sales' own column, which Close Won also
  maintains — is deliberately not written from here, for the same dependency reason.

- Updated dependencies [3f0d3b1]
  - @mj-biz-apps/contracts-entities@0.4.2

## 0.4.1

### Patch Changes

- 45dccaa: Contract form: mark a linked file as the executed agreement (golive #213, item 1).

  Since contracts #36 (golive #203 item 16), `vwContracts.IsAwaitingDocument` clears only when a file
  linked to the contract carries the `Executed Agreement` file category — but MJ's stock Attachments
  panel at 6.1.0-edge.4 has no way to set a file's category, so a contract whose type requires an
  executed document read **Awaiting document** no matter what was attached.

  A new **Executed agreement** field panel on the Contract form lists the files linked to the contract
  with their category and offers **Mark as executed agreement** / **Unmark** per file. Mark sets the
  file's `CategoryID` to the `MJ: File Categories` row named `Executed Agreement`, looked up by name
  (the same way the view resolves it); Unmark clears it. After either write the form reloads the
  record, so the header chip and the Overview health line follow the database rather than the panel's
  opinion. A refresh control on the panel reloads the list, because attaching a file through the
  toolbar's Attachments panel does not otherwise reach it.

  The panel follows the Re-papering rule: always visible, and while the form is editing or the contract
  is unsaved it shows the list read-only with **Finish editing to change** / **Save this contract
  first** in place of the buttons. It hides the buttons and says why when the user lacks update
  permission on `MJ: Files`, and it says plainly when the `Executed Agreement` category row is missing
  from the database rather than failing silently.

  The category name now has one spelling in code — `EXECUTED_AGREEMENT_FILE_CATEGORY` in
  `@mj-biz-apps/contracts-entities` — and a test pins it to the migration's seed. No schema, migration
  or metadata change. Attaching files, removing them and opening them stay with MJ's stock Attachments
  panel; the upload-time checkbox and a category picker in its Edit Details are MJ gaps and are not
  addressed here.

- Updated dependencies [45dccaa]
  - @mj-biz-apps/contracts-entities@0.4.1

## 0.4.0

### Minor Changes

- 0c6981a: Three fixes to what the contract form asserts and what it lets you type (#28 items 16, 18 and 20).

  **"Awaiting document" cleared as soon as any file was linked**, so an exhibit, a draft or the wrong PDF silenced the warning — the system could not tell the executed agreement from a scan of a business card, which makes the chip worse than absent. `vwContracts.IsAwaitingDocument` now requires a linked file carrying MJ's file category **Executed Agreement**, and the migration seeds that category idempotently by name. A category rather than a column on `Contract`, because ERD R-8 ships no `ExecutedDocumentFileID` FK and "what kind of document is this" is a property of the file.

  **Contract Number, Has Modifications and Superseded By Contract** rendered as editable inputs even though the server assigns all three — the number is minted under a lock, the flag is settled in `ValidateAsync()`, and the supersession FK is written only by `Contracts.Supersede` on the successor, so editing it here sets the opposite direction from the Re-papering panel. All three are now read-only. Parent Contract stays editable, as item 11 requires.

  **The term countdown** appeared in both the header and the Dates tab, computed separately in each. The header keeps it.

  The migration re-creates `vwContracts` in full, as `CREATE OR ALTER` requires, so it also carries forward the inclusive `Terminated` boundary that item 13 set in `V202608300100`. Sorting later than that file, it would otherwise have reverted it.

  Minor: the branch carries a versioned migration.

### Patch Changes

- 14eebae: The contract header showed **Company twice**. `next` already carried the Company stat and the rebase re-applied this branch's version next to it; the two insertions were adjacent rather than overlapping, so nothing conflicted and a build-only CI had nothing to fail on. One block now, and a test asserts no stat label is rendered twice — generalised, because a duplicated stat is exactly what a rebase against a branch solving the same issue produces.

  The **Re-papering read-only chips** now read "Finish editing to change" / "Save this contract first", as #203 item 19 specified. They were missed because the commit carrying that copy also carried supersede work `next` had solved its own way, so the whole commit was dropped in the rebase.

- 2fefe94: The hero names its two parties the way the rest of the app does, and the form stops explaining itself (#28 items 8 and 19).

  The selling company's stat was labelled "Selling", a word that appeared on no other surface and matched no field a user could go looking for — the column is `CompanyID` and every grid calls it Company. It is now **Company**, and it comes before **Customer**: our company first, then the counterparty, which is how the agreement itself reads. No metadata change is needed; CodeGen strips a trailing `ID` from a foreign key and already derives "Company", the same rule that makes `CustomerOrganizationID` read "Customer Organization".

  Eight pieces of prose described how the software works rather than what the reader should do. The hero's flag becomes "Contract number is assigned on save." — how the counter avoids a collision is not a fact about this contract. The Terminated hint says what setting the date _does_ rather than characterising it as "a fact about what happened". The derived-lifecycle note, the executed-date-may-precede reassurance, the orders-subscription ruling and the auto-renew aside are deleted. The Renewal and Lineage empty states name what is absent instead of characterising the contract. The "as stated in the agreement" chip stays, as specified.

  Both items shipped once before and were reverted when `origin/next` rewrote the contract form; this re-applies them against its collapsible hero and stat grid. Item 19's three Documents replacements are **not** included: next replaced the custom Documents panel with MJ stock attachments, so they need re-scoping against the new mechanism rather than porting.

- 4a710c1: Contract form Overview panel and header chips: plain-English copy.

  The Overview panel landed after golive #203 item 19 was written, so its strings were never put through
  that copy pass and still read in developer voice — health alerts arguing why a condition matters
  ("the watchlist cannot see this", "a customer can walk without renewing"), a card titled "What needs a
  person", and an Auto-renew subtext of "as the paper states" / "someone must act". The header chip
  tooltips in `contract.panels.ts` carried duplicate wording of their own.

  Each message is replaced with the verbatim copy specified on the issue: the alert states the condition,
  the next-step card states the action. The card header becomes **Next step**, the Auto-renew subtext line
  is dropped, the Parties card label **Selling as** becomes **Company** (golive #203 item 8) and its empty
  Agreement value becomes **None**, and the Obligation card's **Created from** row is hidden when there is
  no source record rather than reading "Entered directly" (golive #203 item 1).

  Copy only. No getter decides differently than it did before — which messages appear, and when, is
  unchanged. The one structural edit is the hidden **Created from** row, which added a `HasSource` getter
  and left `CanOpenSource` alone; `SourceLabel` no longer carries the "Entered directly" fallback because
  nothing renders it without a source any more.

  Dates, Renewal terms, Lineage and Re-papering copy are golive #203 item 19 / contracts #36 and are not
  touched here, and the dashboard intro paragraph is contracts #42.

  Also fixed in passing: `Term ends ${endsInText(d)}` doubled the verb on the day a term ends — "Term ends
  ends today." — and read "Term ends ended 3 days ago" behind it. The alert and the next-step line now
  compose the clause through `termEndsText`, which carries the verb so it agrees with the tense
  `endsInText` picked. Andrew's copy for every other day ("Term ends in 5 months.") is unchanged, and
  `EndClock` still calls `endsInText` directly.

- 8d9983c: The polymorphic provenance pair can no longer be typed over (#28 item 18, completing it).

  `CreatingEntityID` and `CreatingRecordID` rendered as ordinary inputs in Edit mode even though the server owns them — `LiveContractsSeam.setProvenance` sets the pair on Close-Won and nothing else should. `CreatingEntityID` is a real FK to `__mj.Entity` and `CreatingRecordID` is the row it names, with `CK_Contract_CreatingPairBothOrNeither` requiring both or neither, so editing one field alone produced a save the constraint refused and editing both silently re-pointed a contract's provenance at an unrelated record — which is then what the header's Source Deal link displays. Both are now read-only, joining Contract Number, Has Modifications and Superseded By Contract.

  **The Provenance section is kept, which item 18 says to hide.** Its stated reason is that item 1's Source Deal link replaces the section, and that is not yet true: the link renders only when both provenance columns are set, and one contract of eleven has them — a hand-typed pair naming `MJ: Explorer Navigation Items` with a record id that is not a valid UUID. On every contract a person can currently open, the replacement is invisible, so hiding the section would remove the only visible provenance in exchange for a stat that does not appear. Worth revisiting once a contract created by a real Close-Won deal exists to verify item 1 against.

- abba50e: The header names the record that created a contract, a recorded zero stops reading as "not recorded", and edit-mode controls get their width from the kit (#28 items 1, 21 and 5's panel half).

  The "Created from" stat rendered `CreatingEntity` — the name of an entity, not a record — so a contract raised from a Close-Won deal read "Deals" and one entered by hand read "Entered directly". Neither told the reader which deal. It is now a **Source Deal** stat carrying the deal's own name, clickable through to the record, and absent entirely when there is no source. Nothing is hardcoded to Deals: `CreatingEntityID`/`CreatingRecordID` is a polymorphic pair, so the entity is resolved from the id and the label takes that entity's own singular name — an Order would read "Source Order" with no code change. Navigation reuses the panel's existing `open()` helper, the one Customer and Contact use, so ctrl/cmd-click opens a new tab like every other link on the form.

  A recorded `0` now reads "0 days" and "0%". `Record.X ? … : '—'` conflated zero with absent, so the panel reported holding no figure about a figure that says no notice is required. The "No renewal terms recorded." empty state now also requires Auto-renews to be No — it previously appeared directly beneath a field reading Yes.

  The seven inline `style="width:100%"` attributes are gone; the kit's `.mjc-field input, .mjc-field select` rule carries the width along with everything else that makes edit mode match read mode.

  All three shipped once before and were reverted when `origin/next` rewrote the contract form; this re-applies them against its stat grid.

- 533f873: The Source stat hides itself when the provenance names a record that does not exist.

  `CreatingEntityID`/`CreatingRecordID` can point at nothing — a hand-typed pair, a deleted row — and the stat rendered an "Open" button that navigated nowhere. A link that cannot work is worse than an absent stat: it invites a click and spends the reader's trust.

  The fix distinguishes two cases the code had conflated. A name read that **succeeds and matches nothing** means the record is not there, so the stat hides. A read that **throws** means the record may exist and simply be unreadable by this user, so the link stays and the value falls back to "Open" — which is what the original fallback was written for. Treating both as "no name" is what made a dead button look deliberate.

- 92a377d: Three places where the Re-papering panel described something other than what was on screen (#28 item 23).

  **Changing the selection left the previous outcome up.** "Linked — that contract is now superseded by this agreement." stayed on screen while the user picked a different contract, reading as a description of the new selection. A success message that reports an action nobody took is worse than no message; both banners now clear when the selection changes.

  **The candidate list was keyed on a boolean.** The form reuses the panel instance when it navigates, so the flag stayed true and the picker went on offering the previous contract's candidates — filtered to the previous customer and the previous level, which is a wrong list rather than a stale one. It is now keyed on the record's ID.

  **A failed read stayed reported after a later one succeeded**, so the panel showed candidates and told the reader it could not read any.

- Updated dependencies [0c6981a]
  - @mj-biz-apps/contracts-entities@0.4.0

## 0.3.0

### Patch Changes

- 84fc58c: License declarations now agree on BUSL-1.1 everywhere.

  Every machine-readable declaration was already correct. The README footer was not: it linked
  the text "ISC" to `LICENSE`, a file whose first line reads "Business Source License 1.1", so
  the one place a human is told the license contradicted the file it pointed at. The link text
  now names the license the file actually grants.

- 3668a84: Files on a contract use MJ's standard attachments (form toolbar). The custom Documents panel is removed.
- f6452c4: Re-papering: linking adds, releasing targets one contract. Terminated is inclusive of its date. End Date is validated in words.

  The first four items of contracts#28, all in the same area of the form.

  **`Contracts.Supersede` no longer replaces (items 9 and 10).** Two reported defects turned out to be
  opposite halves of one wrong idea, and it was a deliberate one — `SupersedeOperation` argued REPLACE,
  NOT ADD from the fact that the picker is a single-select. So linking CTR-0002 quietly released
  CTR-0001, and clicking "Unlink CTR-0001" released every predecessor, because the panel passed the
  clicked ID to a handler that discarded it. A contract may legitimately supersede several earlier ones,
  so **linking now adds** and leaves existing predecessors alone, and **releasing takes an explicit
  `ReleasePredecessorID`** that clears exactly the contract named. The module's docstring is rewritten
  rather than left arguing the old case.

  **A note on the input shape.** `SupersedeInput.PredecessorID` was required and `null` meant "release
  every predecessor". Both `PredecessorID` and the new `ReleasePredecessorID` are now optional, and a
  call carrying neither is **refused with an error** rather than treated as the old release-everything.
  That is the one behaviour worth flagging: a stale caller sending the old shape gets told, instead of a
  green result that changed nothing. The only caller in the workspace is the panel, which is updated in
  the same change; the type is exported, hence `minor` rather than `patch`.

  **Terminated is inclusive (item 13).** `vwContracts` derived Terminated from `TerminatedDate < today`,
  so a contract terminated today read Active until midnight — while the Dates tab told the user that
  setting the date marks it Terminated _from_ that date. `V202608300100` moves that one branch to `<=`.
  `Expired` deliberately stays `<`: an End Date is the last day the agreement covers, a Terminated Date
  is the day it stops, and making them symmetric would expire every contract a day early.

  **End Date before Effective Date says so (item 12).** The pair was guarded only by `CK_Contract_Dates`,
  so the user got raw constraint text naming no field. `ContractEntity.Validate()` now reports
  "End Date must be on or after the Effective Date." on the End Date field, in the browser and on the
  server. The constraint stays as the backstop. The rule mirrors the constraint exactly — equal dates
  pass, because a one-day agreement is real and a validator stricter than the database is a worse defect
  than the error it replaces.

  **A test that was green and wrong.** `contract-state.test.ts` reads the migration and asserts the view
  says what we think it says, but it read a _pinned_ filename — so item 13's new migration left it
  passing while describing a superseded one. It had already been hand-repointed once before. It now
  resolves the newest migration that defines the view, which removes the whole class of failure.

- Updated dependencies [84fc58c]
- Updated dependencies [f6452c4]
  - @mj-biz-apps/contracts-entities@0.3.0

## 0.2.0

### Minor Changes

- 4e8c1ce: Raise the platform floor to MJ 6.1.0-edge.4 and the bizapps-common dependency
  floor to 5.36.0 — the versions actually exercised together. All
  @memberjunction/\* dependencies pin ^6.1.0-edge.4 (caret, never exact).

### Patch Changes

- Updated dependencies [4e8c1ce]
  - @mj-biz-apps/contracts-entities@0.2.0

## 0.1.1

### Patch Changes

- @mj-biz-apps/contracts-entities@0.1.1

## 0.1.0

### Patch Changes

- 80ac891: Enforce the eight backend rules the schema promised and nothing checked.

  `plans/backend-requirements.md` audited every rule the ERD claims and found that most of them existed
  only as prose. **All ten ready items are now done**, each at the cheapest tier that can hold it — CHECK constraint
  where the rule reads one row, trigger where a bypass would be silent corruption, entity subclass where
  the point is a message a person can act on.

  - **R-1** a referenced template's provisions are immutable — trigger plus a subclass that explains it.
    The trigger compares OLD to NEW values, without which an identical `mj sync push` of the 73 seeded
    provisions would start failing the moment any contract referenced the agreement.
  - **R-3** lineage cycles are refused on both `ParentContractID` and `SupersededByContractID`, naming
    the ring. A cycle was not merely untidy: `vwContracts` computes root pointers by walking the chain,
    and a ring makes those columns silently NULL on every read.
  - **R-4** `ParentStatusRequirement` becomes `MustBeRoot` / `MustBeChild` / `TemplateRequired`, and a
    modification may cite any provision of a template **at or above its contract in the tree**. That
    second half is what makes change orders work at all — a change order carries no template of its own,
    so every modification recorded on one was previously refused.
  - **R-5** a retired contract type or template type cannot be _newly_ selected, while contracts already
    using one keep saving. Order Form and Payment Link are retired accordingly.
  - **R-6** `ModificationText` is required — `NOT NULL` **and** a not-blank CHECK, because `NOT NULL`
    accepts the empty string and MJ's nullability check only tests null.
  - **R-7** the `ContractSequence` counter table becomes a SQL `SEQUENCE`. The table existed only because
    CodeGen registers tables as entities, which made the counter API-writable; a sequence is not a table,
    so the entity, the grid and the hole all disappear together.
  - **R-8** deletes explain themselves instead of surfacing a foreign-key constraint name, counting what
    blocks them.
  - **R-10** one modification per provision × contract combo. `UQ_ContractTemplateModification_Contract_Provision`
    already made this the rule; it now explains itself instead of surfacing a raw unique-index violation.
    Caught in the picker, among staged rows, and against saved rows.

  Four migrations, all idempotent and written for a database that already has data.

  - **R-11** provision ordering comes from `ProvisionNumber` via a derived, indexed collation key. The
    hand-maintained `Sequence` column it replaces had **already collided** in the seeded data — `1` and
    `1.1` both claiming position 1 — which is the failure mode of a second copy of an order the number
    already states.
  - **R-12** `SourceURL` becomes nullable and a derived `IsUsable` says whether the standard terms can
    actually be read. A template with neither a URL nor a file is _incomplete_, not invalid, so it gets a
    chip rather than a refusal; the refusal lives one step downstream, where a contract would incorporate
    terms nobody can read.

  Seven migrations, all idempotent and written for a database that already has data.

- 2aa3ace: Move every MemberJunction dependency from `6.1.0-edge.2` to `6.1.0-edge.3`.

  **Why:** `@memberjunction/ng-hierarchy-tree` — which the Lineage panel uses — is published only from
  `6.1.0-edge.3`. There is no `edge.2` of it, so a standalone build could not resolve it and CI failed
  with `TS2307: Cannot find module`. It resolved locally only because the mjdev parent workspace links
  the MJ source directly, which is exactly why this was invisible until CI.

  **The mixed state is the thing to avoid.** An earlier attempt updated only the lockfile, which left
  some packages on edge.2 and pulled others to edge.3; that combination failed differently, with
  `TS2554: Expected 1 arguments, but got 2` inside three CodeGen-generated form components. With every
  pin moved together the build is clean — **6/6 packages, 180/180 unit tests, no regeneration required.**
  So those errors were a symptom of version skew, not a real signature break, and no CodeGen run is part
  of this change.

  Bumped: the root `devDependencies` (17 packages), `mj-app.json`'s `mjVersionRange`, and the peer ranges
  on all six workspace packages — plus `@memberjunction/ng-hierarchy-tree` added to the root
  `devDependencies`, which is the convention this repo already follows for every other MJ Angular peer
  (peer on the package, devDependency at the root, because `.npmrc` sets `auto-install-peers=false`).

- 00e11b3: MJ 6 and pnpm, matching the family baseline.

  Contracts was the last app in the estate still on **npm** and **MJ 5.44** — common, tasks,
  accounting and orders had all moved. That gap is not cosmetic: an npm-locked member cannot join a
  pnpm cross-repo workspace on equal terms, and 5.44 peer pins against a 6.1 host are a resolution
  accident waiting to happen rather than a declared contract.

  **The manifest now says what it needs.** `mjVersionRange` is `>=6.1.0-edge.2 <7.0.0` — a
  **same-tuple prerelease bound**, because standard semver excludes a prerelease from any comparator
  that does not share its `major.minor.patch`, so `>=6.0.0 <7.0.0` would reject `6.1.0-edge.2` under
  every tool except MJ's own gate (which coerces to the base tuple first). Every sub-package's
  `@memberjunction/*` peer moved `^5.44.0` → `^6.1.0-edge.2`, and `ng-ui-components` `^5.50.0` → the
  same.

  **pnpm, configured like its siblings.** `packageManager` is `pnpm@10.33.0`; `pnpm-workspace.yaml`
  carries `linkWorkspacePackages: true` (without it, internally-pinned exact versions resolve from the
  registry instead of linking locally) and the 16-name build-scripts allowlist; the npm `overrides`
  block became `pnpm.overrides` with the family's Angular 21.1.3 set plus `@memberjunction/core` and
  `global`. `package-lock.json` is gone and `pnpm-lock.yaml` replaces it.

  **One deliberate divergence from common/accounting**, and the same one orders carries: `.npmrc` sets
  `auto-install-peers=false`. With it on, every unsatisfied peer becomes an install instruction — and
  `contracts-ng` declares the **unpublished** `@mj-biz-apps/accounting-ng` as a mandatory peer, so the
  install would 404 and no lockfile could exist. It flips to the family default when accounting
  publishes. That peer's range also tightened from `*` to `>=0.1.0`, matching how the converted apps
  declare each other.

  `.npmrc` is no longer git-ignored. It was, via a scaffold-template rule that grouped it with the
  `.mjrc.*` files — which would have left CI installing on pnpm defaults while local ran on these
  settings. Both sibling repos track theirs.

  CI moved with it: `pnpm/action-setup` before `setup-node` (the `cache: 'pnpm'` option needs pnpm on
  PATH first), `pnpm install --frozen-lockfile` in place of `npm ci`, lockfile paths and cache keys
  repointed, `pnpm exec changeset publish`, and the case-sensitivity validator replaced with the pnpm
  version already proven in accounting.

  **The tab strip no longer asks for a disabled state, because MJ has none.** `ToTabConfigs` used to
  set `disabled` and `disabledReason` on every `not-yet` tab. MJ's `TabConfig` is
  `key | label | icon | badge | badgeVariant`, and `mj-tab-nav` renders every tab as a plain clickable
  button — so **those two fields were already being discarded**. A blocked tab has always rendered
  enabled and unexplained at runtime; type erasure was the only reason nobody saw it, and MJ 6 turned
  it into three `TS2339` that finally said so.

  Nothing regressed by removing them. The gating still lives in `ContractTabDef.State` / `.Reason`,
  `ResolveActiveTab` still refuses to land on an unreachable tab, and `SelectTab` still rejects a click
  on one — that rejection is now correctly documented as the ONLY guard rather than "the second of
  two". What is missing is the visual affordance: a user can click a blocked tab and nothing happens,
  with no explanation. Restoring it is two lines once MJ's disabled state lands (`2acd4dc7cb`,
  unmerged) — `plans/BACKLOG.md` B-2. Contracts is moving to custom forms and the MJ record system, so
  the treatment gets revisited there rather than rebuilt against this component.

  The two tests that asserted on `TabConfig.disabled` now assert the same invariants against
  `ContractTabDef`, the layer that still carries them — left pointed at `TabConfig` they would have
  filtered on a property nothing sets and passed while testing nothing. A new test pins the emitted
  key set to what MJ actually supports, so the next silently-ignored field fails instead of shipping.

  All six packages build clean on MJ 6; the Angular suite is 56/56. The other five packages' `test`
  scripts are still `echo "No tests configured yet"` stubs — that green is vacuous and is not coverage.

- 6315add: A contract can be created without hand-typing its number, and re-papering runs as a remotable operation.

  **`ContractNumber` is now nullable, and the server holds the invariant.** MJ has no way to express
  "NOT NULL, assigned by the server on insert" (MJ#4001), and both available workarounds break creation
  in opposite directions: a DB `DEFAULT` makes CodeGen emit an expression as a quoted literal, so
  `spCreateContract` fails to compile and is left **dropped** (MJ#4000, added and reverted in
  `V202608211000`/`1100`); and `AllowUpdateAPI = false` silences the validator but makes the field
  read-only, which **omits it from the insert payload** so the procedure fails with "expects parameter
  '@ContractNumber', which was not supplied".

  So `V202608211200` relaxes the column and `ContractEntityServer.Save()` mints whenever the incoming
  value is null **or blank** — blank matters because a form posting an empty string, a seed script or an
  import would otherwise persist `''` as a contract number. `test-harnesses/contract-number-mint.mjs`
  covers both cases and is load-bearing now that the database no longer holds this rule.

  **Uniqueness stays the database's job, with a plain unique index.** `V202608211300` replaces the
  filtered index `V202608211200` created. Both guarantee that every real number is unique; the plain one
  additionally permits only **one** un-numbered row, so the multi-NULL state that only raw SQL could
  create is refused at the floor rather than accumulating. No application-level null check was added and
  none is needed: the entity guarantees a number on the way in and the index is the floor beneath it.
  The plain index also removes a trap the filtered one introduced, where every INSERT depended on
  `QUOTED_IDENTIFIER ON` and failed with a message naming neither the table nor the cause.

  **Re-papering is a remotable operation.** `Contracts.Supersede` replaces the panel loading and saving a
  foreign contract itself — server work that was being done in the client, and which could not work
  anyway: in the browser MJ resolves the CodeGen-generated entity class rather than the app subclass, so
  `ContractEntity.Supersede()` is simply absent client-side (MJ#4002). Server-side the app subclass
  resolves correctly and the same-level, self-reference and lineage-cycle guards actually run. The
  operation does replace-not-add, reports refusals with the entity's own prose, and **returns the live
  list** — which is what fixes an Unlink button that lingered after the link was cleared elsewhere,
  because the panel no longer keeps its own cached idea of what a contract supersedes.

  It routes through `RouteOperation` rather than a generated typed client: the server resolves an
  operation purely from the ClassFactory by key, so this needs no `MJ: Remote Operations` metadata row
  and no file-generating CodeGen run.

  **Supersession now lives in three places, each doing one job:** the `Supersedes` grid (see and remove),
  the Re-papering picker in Details (add), and the derived `State` chip (that it happened). The picker is
  available when NOT editing and only on a saved contract — it writes another record, so it needs this
  one to exist. `test-harnesses/supersede.mjs` proves the entity path end to end.

- dc55dd0: Contract types decide whether a parent is allowed, lifecycle state is derived in one place, and Details leads the rail.

  **`ContractType.ParentStatusRequirement` replaces a string comparison.** "A change order must name the contract it changes" was enforced by comparing the type row's _name_ to `'Change Order'`. A display name is not a rule — renaming that lookup row silently stopped the check from ever firing. The type now carries the constraint: `'Required'`, `'Prohibited'`, or NULL for no restriction, modelled as `NVARCHAR` + `CHECK` so CodeGen's `ParseCheckConstraints` renders it as a dropdown and the grid picks it up from `DefaultInView` with no app code. Both directions are enforced; the value is seeded through metadata sync rather than a migration, so it has one owner.

  **The derived `IsChangeOrder` column is gone.** It restated `ParentContractID IS NOT NULL` under a name implying a type distinction it never read: a Change Order whose parent was not yet set reported `0`, and an Order Form beneath a master agreement reported `1`.

  **Lifecycle state is derived in the view and nowhere else.** The rule was rendered twice — a T-SQL `CASE` and a TypeScript function generated from one module — on the theory that a single source could not drift. It drifted anyway, on the termination boundary, and the guard missed it because it compared the two renderings as _text_. TypeScript no longer derives state; it reads `contract.State`, and the module keeps only the value list the client needs for chips and typing. The tradeoff is stated rather than hidden: the rule's semantics can no longer be tested without a database, so `state-derivation.mjs` covers all six states plus the three-way termination boundary against the deployed view, and the DB-free test checks the migration against a hand-written statement of the rule that lives in the test.

  A contract being edited now shows its last-saved state instead of a live projection of unsaved dates — deliberate, since a chip reacting to an unsaved date asserts something no query would agree with.

  **Every read goes through `RunView`**, including the modification `EXISTS` check (`count_only`) and a cross-template check that had been a four-table join. Where a provider is still needed it is MJ's own `BaseEntity.RunViewProviderToUse`. The one thing that cannot be a view — the atomic number counter — moved into `spAssignNextContractNumber`, following accounting's pattern, which leaves no dialect-specific SQL in the application at all.

  **Details is first in the form rail.** The rail is assembled as fixed bands — leads, then Details, then related, then More — and a panel joins the lead band purely by declaring `inclusion: 'Primary'`, which is why Details sat fourth. Reordering the groups from a form policy cannot fix it: the band order is re-imposed after any policy runs, silently. Dropping `Primary` puts the panels in the related band, ordered by sort key: Details, Dates, Renewal terms, Documents, Modifications, Lineage.

- 668fa6d: Contracts can be re-papered, Order Form and Payment Link are back, and three hand-rolled panels are now MJ components.

  **Re-papering (C-US9).** A contract can now name the agreement that replaces it, from the successor's
  own form, while the successor is still being created. `SupersededByContractID` stays on the
  PREDECESSOR — the direction was reviewed and kept, because one column there makes "superseded at most
  once" structurally true, it lets several agreements consolidate into one, and it keeps `Superseded`
  derivable from a column on the row the base view already projects rather than an `EXISTS` subquery on
  the app's hottest read path. No `SupersedesID` was added: a second FK would store one relationship
  twice, which is the defect D-19/R-18 removed when it deleted the stored `Status`.

  The operation is two steps in one order — save the successor, then set the predecessor's field. A
  `TransactionGroup` was tried and removed: it defers writes until `Submit()`, so the predecessor
  validated against a successor that had an ID and no row, and the guard could not tell an unwritten
  sibling from a bad reference. That ambiguity was the only thing making a genuinely missing contract
  read as success.

  **Supersession is scoped to the same level of the tree**, not to root contracts. "Root only" would
  forbid a change order superseding another change order under one agreement — real, and the alternative
  is deleting history — while still permitting a change order to claim it replaced the agreement it
  hangs off. Type is deliberately unconstrained, so `Payment Link → Order Form` remains a legal upgrade.

  **Self-reference is now checked in full, in one place.** `refuseSelfReferences` reports self-parent and
  self-supersession unconditionally, comparing by value. Previously the cycle guard detected `A → A` and
  declined to report it, deferring to the generated validator — and `ParentContractID → self` had no
  other check at all. Those validators are LLM-authored and both emitted `===` on a `uniqueidentifier`,
  so they miss two ids differing only in casing (MJ#3984). A rule worth checking is checked whole.

  **Order Form and Payment Link are Active again**, reversing R-4's retirement. Both now require a
  template, which their own descriptions already implied: each says its terms live in the Master
  Agreement it references. Payment Link remains the only type with `RequiresExecutedDocument = 0` — the
  reason that column exists, and what keeps a self-serve sale off the Awaiting-documents worklist.

  **Three hand-rolled UI surfaces are gone.** Provisions, Modifications and the lineage children table
  each re-implemented something MJ ships, and each lost functionality doing it. Provisions and
  Modifications now use MJ's stock related-entity grid — which also fixes a silent clip, where a plain
  table inside `Variant="related-entity"` had all 73 provisions in the DOM and only the first few
  reachable, with no scrollbar to suggest otherwise. Lineage uses `mj-hierarchy-tree`, so the panel
  declares a config instead of querying, and its nodes NAVIGATE: the old table could show a change
  order's number and give no way to reach it.

  `@memberjunction/ng-hierarchy-tree` is added as a peer at the same range as every other MJ peer, and
  deliberately not pinned.

- bab2cc5: Re-papering gets two surfaces, the lineage tree gets MJ's hierarchy control, and a contract number is no longer stripped out of its own validation.

  **Two surfaces, one each for the two halves.** "What this agreement supersedes" is now a stock
  related-entity grid on its own rail section (`Supersedes`) — see every superseded contract, open any of
  them, un-supersede one — enabled by flipping `DisplayInForm` + `Configuration.UI.inclusion` on the
  `SupersededByContractID` self-relationship in `.form-chrome.json`. That row previously set
  `inclusion: 'None'`, reviewed twice, on the argument that a grid meaning "contracts naming me as their
  successor" needs explaining. The argument was right about the label and wrong about the need; the label
  is now `Supersedes` and the original reasoning is preserved in the row's comments.

  A related grid cannot LINK an existing record (its New creates a new one), so the picker keeps exactly
  one job: **add**. It moved out of Lineage into a `Re-papering` field panel in Details, because the
  related-entity panel variant renders any non-AG-Grid child blank (MJ#3999) — which is what made it
  invisible. It is always visible rather than edit-mode-gated, uses `mj-combobox` / `mjButton` /
  `mj-alert` instead of hand-rolled controls, and reads as an ordinary form line via MJ's own
  `mj-forms-field` markup. `Superseded by` moved to Details alongside it, so both directions of the
  relationship read together.

  **Changing the pick now un-points the previous one.** The schema deliberately permits many predecessors
  to name one successor (consolidation), so setting the new one alone left the old one still pointing here
  and the agreement quietly superseded both. A single-select control means one predecessor: release, then
  link, with each failure reporting what actually landed.

  **Lineage uses `mj-hierarchy-tree`.** `ParentContractID` is an ordinary self-referential hierarchy, so
  the panel declares a config instead of querying — and its nodes NAVIGATE, which the hand-rolled table
  could not. `@memberjunction/ng-hierarchy-tree` is a peer at the same range as every other MJ peer.

  **`dropSavePopulatedFieldErrors` is deleted.** It searched the validation result for
  `Source === 'ContractNumber'` and removed it, so a new contract saved despite MJ correctly reporting a
  NOT NULL field as null — a real error suppressed on the belief that something later would fix it. In its
  place, `refuseReservedContractNumber` refuses a hand-typed `CTR-<digits>`, because that shape is what the
  sequence mints and a hand-typed one can collide with a value the sequence has not reached yet — surfacing
  months later on somebody else's save. `ContractEntityServer` marks its own minted numbers so the rule
  cannot refuse them.

  **The `ContractNumber` DEFAULT was added and reverted in the same batch, deliberately kept as two
  migrations.** It was valid SQL and would have satisfied MJ's client-side validator, but CodeGen
  string-quotes an expression default into the generated create procedure, which then fails to compile and
  leaves `spCreate<Entity>` dropped — contracts could not be created at all (MJ#4000). Reverted
  forward-only rather than by editing an applied migration. The underlying problem is still open.

  Also: the contract-number failure message named a table dropped two migrations ago, and
  `@mj-biz-apps/accounting-ng` was declared as a dependency and imported nowhere.

- 3b2edc7: Contracts is rebuilt from a clean sheet: a record of agreements, not a billing engine.

  **What changed, and why it is a rebuild rather than a refactor.** v1 modelled contracts as the
  thing that decides what to charge — ten tables carrying terms, lines, billing schedules,
  commitments, billing events and amendments, plus a billing engine, seven remote operations and a
  client-side draft object to compose it all. That was the wrong job. Orders bills; sales sells;
  contracts is the **source of truth for what we agreed and where the paper is**. Nothing in the v1
  schema survived except the words on a few columns, so the baseline was rewritten in place (this
  repo's pre-production practice) rather than migrated forward.

  **The schema is seven tables.** `Contract` is the agreement — its counterparty organisation, which
  of our companies is party to it, the dates, the renewal terms _as the paper states them_, and
  lineage to the contract it changes or supersedes. `ContractType` and `ContractTemplateType` are
  lookups. `ContractTemplate` is one dated version of a standard-terms document (a Master Agreement)
  and `ContractTemplateProvision` is one numbered clause of it, text included.
  `ContractTemplateModification` is the point of the app: _this contract deviates from that
  provision, and here is the negotiated language_. `ContractSequence` mints contract numbers.

  Both texts are stored and read as a pair — the standard clause on the template, the negotiated one
  on the modification — so a reader sees what was agreed against what was offered without opening two
  records.

  **There is no `Status` column.** Four of its five values were projections of the dates and the two
  self-FKs, and a stored copy of a derivable fact can only agree or lie. Lifecycle is a derived
  `State` on an app-owned layered base view, alongside `IsAwaitingDocument` (the contract _type_
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

- 94e73d3: Modifications are editable, foreign-key links navigate, and provisions read by name.

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

- Updated dependencies [80ac891]
- Updated dependencies [2aa3ace]
- Updated dependencies [b373233]
- Updated dependencies [00e11b3]
- Updated dependencies [6315add]
- Updated dependencies [dc55dd0]
- Updated dependencies [668fa6d]
- Updated dependencies [4d190f5]
- Updated dependencies [bab2cc5]
- Updated dependencies [3b2edc7]
- Updated dependencies [94e73d3]
- Updated dependencies [1aa3c88]
  - @mj-biz-apps/contracts-entities@0.1.0
