# migrations/ — Skyway (Flyway-compatible) migrations for `__mj_BizAppsContracts`

Applied in filename order against this app's schema at install/upgrade and during
development.

## Naming

    B<YYYYMMDDHHMM>__v<app-version>__<Description>.sql    baseline (first schema drop of a new app)
    V<YYYYMMDDHHMM>__v<app-version>__<Description>.sql    everything after

- Timestamps must be strictly increasing. **Not enforced by CI.** Flyway applies in filename
  order, so a migration numbered behind one already applied is skipped silently on an existing
  database and applied in the wrong order on a fresh one.
- Use `${flyway:defaultSchema}` for THIS schema; literal `__mj` for MJ core rows.
- Do **not** add `__mj_CreatedAt` / `__mj_UpdatedAt` columns or FK indexes — CodeGen does.

## The train, and why it is four files

| file | what it is |
| --- | --- |
| `B…__Baseline.sql` | schema, `__mj.SchemaInfo`, the sequence, the sort-key function, all seven tables + constraints, the two app-owned programmable objects, then the CodeGen capture |
| `V202608240100__…__Layered_base_view_flags.sql` | flips two entities to layered base views + the capture that re-points CodeGen to `vw*Generated` |
| `V202608240200__…__Layered_base_views_and_derived_fields.sql` | the two application-owned wrapper views + explicit registration of the 8 columns they add |
| `V202608240300__…__Metadata_Sync.sql` | the reference vocabulary `mj sync push` writes from `metadata/` |

**The count is forced, not stylistic.** Everything that CAN be folded into the baseline
has been — 22 incremental files collapsed into it on 2026-08-23 (see below). What remains
is a genuine sequence:

1. The layered-view flags live on `__mj.Entity` rows that **do not exist** until the
   baseline's own capture inserts them, so the flags cannot be in the baseline.
2. A wrapper view cannot be created before the view it selects `FROM` — SQL Server has
   deferred name resolution for procedure bodies but **not** for views — so the wrappers
   cannot share a file with the flags.
3. Seed data has to follow the schema and the metadata it references.

**An install runs migrations and NOTHING ELSE.** It never runs CodeGen and never runs
`mj sync push`, which is why both of their outputs are captured here. Skipping either
produces a database that looks installed and isn't: bare tables with no entity metadata,
or entities with no vocabulary.

### What the 2026-08-23 flatten collapsed

Pre-publish practice (below) was to edit the baseline in place; that slipped, and 22
incremental files accumulated. Folding them back in removed real garbage rather than
merely tidying: a `DEFAULT` added and reverted one file later (MJ#4000), a filtered
unique index replaced by a plain one, a `ParentStatusRequirement` column added and then
dropped for the `MustBeRoot`/`MustBeChild` flags that replaced it, a `ContractSequence`
counter table created and then retired for a real `SEQUENCE`, three successive versions
of one trigger, and two migrations patching `__mj.UserSetting` grid layouts that do not
exist on a fresh install.

It also **fixed three latent bugs**, all the same shape — a column added by `ALTER TABLE`
with no CodeGen capture behind it, so a fresh install got a column MJ could not see.
`ContractTemplate.Status`, `ContractTemplateProvision.ProvisionSortKey`, and
`ContractType.MustBeRoot`/`MustBeChild`/`TemplateRequired` were all invisible to MJ on a
from-zero install of the old train. They are registered now because their columns are
part of `CREATE TABLE`, which the baseline's capture sees.

Two CodeGen artifacts were **deliberately dropped**: `fnContractParentContractID_GetRootID`
and `fnContractSupersededByContractID_GetRootID`, with their `Root*ID` metadata rows.
Current CodeGen no longer generates them; the old train only had them because its captures
were frozen output from an earlier version. Nothing reads them. This takes the
"delete the metadata rows" branch of the open question in
`plans/backend-requirements.md` (ruled by Marcelo, 2026-08-23).

### Why the three V files are numbered Aug 24, not Aug 4

They were originally `V202608040002`-`0004`, chosen to sit immediately after the baseline so
the four files read as one sequence. **CI rejected that, correctly.** `changes.yml` compares
every newly added migration against the highest timestamp already on the base branch, and
`next` carried migrations up to `V202608192200` — so a file numbered Aug 4 sorts *behind*
migrations an existing database has already applied. Flyway applies in filename order, so such
a file is skipped silently on that database and applied in the wrong order on a fresh one. The
warning at the top of this file said exactly that and described it as "not enforced by CI";
it is enforced now, and it caught this on the first run.

The rule is that a migration filename must be monotonic against **everything the target branch
has ever shipped**, not just against its own train. Grouping numerically with the baseline is
cosmetic; ordering is not.

### ⚠ An existing database cannot migrate onto this train — it must be rebuilt

Independent of numbering, and the reason the flatten needed to happen before publish rather
than after. The baseline's contents changed, so its Flyway checksum changed, and any database
that already applied the old `B202608040001` will refuse to migrate — reporting a checksum
mismatch on a file it has no way to reconcile. The 22 collapsed V files are also gone from
disk while their history rows remain.

For a development database the fix is to rebuild from zero, which is routine and is how this
train is verified. There is no supported upgrade path from the old train, and there does not
need to be: nothing had shipped. **This is the last point at which that is true** — see
"Baseline edits are CLOSED" below.

## The 50-blank-line rule (where hand-written DDL stops and CodeGen output starts)

**In any migration that carries both, exactly 50 empty lines separate the hand-written DDL from the
CodeGen capture.** The hand-written half ends with its `GO`; then 50 blank lines; then the capture's
banner comment and the generated SQL. A migration with no capture has no separator; a capture-only file
puts the separator below its header comment so the boundary is still findable.

It reads like formatting and is not. A capture is **replaced wholesale** on regeneration, so anyone
re-capturing needs an unambiguous mark for "everything below here is generated — delete it and paste the
new run." A banner comment cannot be that mark, because banner comments appear *inside* CodeGen output
dozens of times. Fifty consecutive blank lines appear nowhere else in a SQL file, which is exactly why
the number is absurd.

Verify with a longest-blank-run check over `migrations/*.sql`. The two files carrying a capture —
the baseline and `V…0100` — must report **50**; `V…0200` (hand-written wrappers, no capture) reports
**1**. `V…0300` is entirely SQL-logger output and carries no separator. `bizapps-orders` is the
reference implementation — `V202608131541`, `V202608131542`, `V202607061432`.

## Baseline edits are CLOSED as of the 2026-08-23 flatten

Pre-publish practice was to **edit the baseline in place** and rebuild from zero, which is safe
only while no database anyone depends on has run it. The flatten above was the last exercise of
that licence.

**From here the rule inverts, and the repo's `CLAUDE.md` states it as binding: schema changes are
new `V` migrations.** An edit to the baseline is invisible to any database that already ran it —
the column simply never appears, and nothing reports a problem — and Flyway checksums the script,
so every existing database refuses to migrate until someone repairs the history by hand.

The authoring loop is therefore:

```bash
# write a new V migration, then:
npm run mj:migrate                         # apply it
npm run mj:codegen                         # regenerate entity metadata + SQL objects
                                           # fold the capture in below 50 blank lines
npm run mj -- sync push --dir metadata     # if the change is vocabulary, not schema
```

A CodeGen capture is **not optional** whenever a migration changes the shape of a table. Its
absence is exactly what produced the three latent bugs the flatten fixed: the column exists in
SQL and MJ cannot see it, on every fresh install, silently.

## Install-order dependency

**`bizapps-common` only.** The baseline's cross-app foreign keys reference
`__mj_BizAppsCommon.Organization` and `__mj_BizAppsCommon.Person`, plus `__mj.Company` and
`__mj.Entity` in MJ core — and nothing else. A clean host carrying MJ core + `bizapps-common` is
enough to apply this whole train, which is how it is verified.

This previously read "`bizapps-common`, `bizapps-accounting` and `bizapps-orders` must be installed
first", and also referred to a `ContractAmendment.ApprovalTaskID` soft reference and a `bizapps-tasks`
dependency. None of that is true of the current schema: there is no `ContractAmendment` table (the
v2 rebuild replaced it with `ParentContractID` on `Contract` itself), no soft reference anywhere, and
no FK into accounting, orders or tasks. Corrected 2026-08-23 after measuring the baseline's actual
`REFERENCES` clauses. Requiring two extra apps for an install that does not need them is not a
harmless overstatement — it is two more failure points in someone's first install.

## Cross-app reference hardness

References into an upstream app are **hard, nullable FKs** — not soft UUID columns. Dependency-order
install makes them safe and MJ's OpenApp publish policy expects them. The earlier
soft-ref-until-CodeGen-include-mode ruling was withdrawn (Amith, 2026-08-03); see
`bizapps-orders` PR #29.

A reference is soft **only** when the target app is genuinely absent from the chain — never as a
workaround for a tooling defect.

## Verification

The train is proven **from zero**, not by inspection. The method, which any change to
these files must repeat:

1. Build a clean host — an empty database with MJ core + `bizapps-common` migrated into
   it, and nothing else.
2. Apply the migrations with `mj migrate --schema __mj_BizAppsContracts --dir ./migrations`.
3. Compare against a from-zero replay of the previous train, object-by-object: columns
   with types/nullability/defaults, CHECK constraints, indexes with their filters,
   sequences, and every view/procedure/function/trigger; then the `__mj.Entity` and
   `__mj.EntityField` rows.
4. Prove the seed independently: apply the migrations to a second clean database, and
   diff its seeded rows against a database seeded by a real `mj sync push`.

Result on 2026-08-23 (MSSQL, MJ `6.1.0-edge.2`): **161 schema objects, zero differences**
against the previous train except the two intentionally-dropped root-ID functions;
**79 seed rows identical including every UUID**; `mj sync push` after migrating reports
`created: 0`. `mj baseline compare --left <a> --right <b> --fail-on-diff` is the shipped
MJ command for step 3 if you want it whole-database rather than schema-scoped.

**Do not verify by re-reading the SQL.** The flatten's one real error — `SourceURL`
silently reverting to `NOT NULL` — was invisible on inspection and caught immediately by
step 3, because the `ALTER COLUMN` that relaxed it was buried inside an `IF EXISTS` block
in a migration whose filename was about something else entirely.
