# `migrations-pg/` — converter output, NOT working Postgres migrations

**Do not deploy these. They will not apply.** Generated 2026-08-24 by
`npm run mj:migrate:convert` (`mj migrate convert`) from the four MSSQL migrations, and
committed as a starting point so the gap is visible and reviewable — not because Postgres
support exists.

## The converter reports success. It is not success.

```
Files:   4 (4 OK, 0 errors)
Batches: 611 total, 525 converted, 102 skipped, 0 errors
```

Exit code 0, "0 errors" — and 102 skipped batches. `Functions: 0`, while the baseline
creates one. This is the shape of failure to watch for: the summary counts *conversion
attempts that did not throw*, not statements that will run.

## What is actually wrong

**1 · Every CRUD procedure and update trigger was dropped** — 22 procedures and 8 triggers,
left in the file as commented-out T-SQL under `-- SKIPPED: procedure (auto-conversion not
supported)`. MJ cannot write to an entity without its `spCreate`/`spUpdate`/`spDelete`, so a
database built from this is read-only at best.

This one is by design, and the converter has an answer: `--split --bake-codegen` generates
**native PG** CodeGen objects inline instead of translating the T-SQL ones. It requires a
**live Postgres** seeded to the state just before these migrations, which is why it has not
been run — see "What is needed" below.

**2 · The hand-written app objects survive as raw T-SQL.** `CREATE OR ALTER FUNCTION` (×3),
`WITH SCHEMABINDING`, and 83 `@parameter` references. None of that is valid Postgres:
no `CREATE OR ALTER`, no `@` parameters, no `SCHEMABINDING`. Affects
`fnProvisionSortKey`, `spAssignNextContractNumber` and
`trg_ContractTemplateProvision_Immutability` — all three need hand-authoring in PL/pgSQL,
including `RAISE EXCEPTION` in place of `THROW` / `ROLLBACK TRANSACTION`.

**3 · The persisted computed column was not translated.** It is emitted verbatim as
`ProvisionSortKey AS (…fnProvisionSortKey(ProvisionNumber)) PERSISTED`. Postgres spells this
`GENERATED ALWAYS AS (…) STORED` **and requires the function to be `IMMUTABLE`** — so the
PL/pgSQL rewrite in (2) has to be marked immutable or the column cannot be created at all.

**4 · Scalar functions were quoted into identifiers, which is worse than leaving them.**
`CHECK ("LEN"("LTRIM"("RTRIM"("ProvisionText"))) > 0)` makes Postgres look for
case-sensitive functions named `LEN` and `LTRIM`. The correct form is
`length(btrim("ProvisionText")) > 0`. Two occurrences.

**5 · Statement order is inverted, independent of syntax.** The baseline deliberately
creates `fnProvisionSortKey` and `seq_ContractNumber` **before** the tables, because a
computed column's expression resolves at `CREATE TABLE` time. The converter moved both to
the end of the file:

| object | line |
| --- | --- |
| `CREATE TABLE ContractTemplateProvision` | 117 |
| `CREATE TABLE Contract` | 210 |
| `fnProvisionSortKey` definition | **8871** |
| `CREATE SEQUENCE seq_ContractNumber` | **8922** |

So even with every syntax problem fixed, the table would fail on a missing function.

## Not tested against Postgres at all

There is no Postgres instance in this workspace. **Everything above is static review of the
generated SQL** — no statement here has been executed anywhere. Treat the list as "problems
visible by reading", not as a complete failure inventory. The real count only comes from an
apply.

## What is needed to finish this

1. A Postgres database with MJ core + `bizapps-common` at the matching version — the PG
   equivalent of the from-zero host the MSSQL train is verified against.
2. Re-run with `--split --bake-codegen` so CRUD objects are generated natively rather than
   translated.
3. Hand-author the three app-owned objects in PL/pgSQL, with `fnProvisionSortKey` marked
   `IMMUTABLE` so the generated column is legal.
4. Fix the `LEN`/`LTRIM` check constraints and the pre-table ordering.
5. Verify the way MSSQL is verified: apply from zero, then diff schema and seed against a
   reference. Not by reading.

## Why this is committed rather than deleted

`migrations-pg/` existing and populated implies Postgres support. It does not exist. This
file is here so that implication is contradicted in the same directory, and so the next
person starts from the converter's output plus a known defect list rather than from zero.

`bizapps-common` ships 8 converted files and `bizapps-orders` 2; `bizapps-accounting` has
the directory and it is empty. Postgres was explicitly deferred for v0.1.0.
