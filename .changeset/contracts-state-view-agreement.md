---
'@mj-biz-apps/contracts-entities': patch
---

The lifecycle view and the TypeScript derivation now agree, and a test can tell.

**The bug.** Contract state is derived twice — a T-SQL `CASE` in the layered base view and
`DeriveContractState()` in TypeScript — and they disagreed about termination. The view treated any
non-null `TerminatedDate` as `Terminated`, so a termination **scheduled for a future date** (notice
served, effective later) made a live contract read as already terminated. TypeScript had been
corrected to `terminatedDate < today`; the view had not, so the same contract read `Active` in the
browser and `Terminated` from any view-backed query — the watchlists, the dashboard counts and the
grid `State` column among them.

**Why `< today` is the right boundary**, rather than a coding preference: in contract law a period
ending on a date runs through the END of that date — an agreement "terminating on 31 December" is in
force all of 31 December. So a contract whose `TerminatedDate` is today is still in force today and
reads `Terminated` from tomorrow, which is also exactly how `EndDate` is already treated. A `date`
column carries no time, so end-of-day is the only available reading; a contract specifying a time, or
an immediate for-cause termination, would need `datetime2` and is out of scope.

**Why the existing guard missed it.** `StateSQL()` renders the `CASE` as text so a unit test can
assert the migration still contains it. That compares **text**, so changing only the TypeScript left
it green: all 77 tests passed while the two implementations disagreed for every contract terminated
today or later. Text cannot detect a semantic split; only running both against the same facts can.

**So this adds the test that can.** `test-harnesses/state-equivalence.mjs` (`npm run test:state`)
scores every contract through the deployed view AND through `DeriveContractState()`, then does the
same over its own fixtures covering all six states plus the three-way termination boundary
(yesterday / today / tomorrow). It asserts three things per fixture — the view, the function, and the
state a person says is correct — because two implementations agreeing on a wrong answer is exactly
what a text comparison would bless. Fixtures are created under a per-run token, never touch the
shared demo contracts, and are removed in a `finally`. Confirmed to actually fail: restoring the old
predicate makes it exit 1 naming both boundary rows.

**Two harness defects fixed on the way in**, both of which had made the committed suite unrunnable
rather than merely incomplete. `dotenv` and `mssql` were imported by `integration.mjs` and declared in
no manifest, so it died at module resolution; and its `.env` path counted four directories upward,
which was correct for the pre-6.x nested layout but resolves to the workspace root under the
parent-workspace topology — where `dotenv` silently loads nothing, `DB_PORT` stays undefined, and the
failure surfaces as "Failed to connect to localhost:1433", reading like Docker being down. Both
scripts now share `test-harnesses/load-env.mjs`, which walks up and asks the filesystem instead of
counting.

Four unit cases pin the boundary on the TypeScript side, including the future-dated termination that
the rule got wrong in both directions at different times.
