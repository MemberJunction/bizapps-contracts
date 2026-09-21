/**
 * The lifecycle rule lives in SQL — in the `CASE` in `V202608182001`. There is no TypeScript copy to
 * compare it against any more, deliberately (see `contract-state.ts`), so these tests do the only
 * useful DB-free thing: they state what the rule SHOULD be, in this file, and check the committed
 * migration against that statement.
 *
 * That distinction matters. The previous version of this file compared `StateSQL()` to the migration —
 * two renderings of the same source, so they agreed by construction and a semantic change on either
 * side stayed green. Here the expectation is written out by hand, independently, and the subject is the
 * single implementation. If someone edits the view's precedence, this fails; if someone edits it to
 * something these tests do not describe, this fails; and it costs no database.
 *
 * What these tests CANNOT do is prove the SQL evaluates the way we read it. That needs a database and
 * lives in `test-harnesses/state-equivalence.mjs`, whose fixtures assert the answers a person wrote
 * down against the deployed view.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { CONTRACT_STATES, type ContractState } from '../contract-state.js';
import { newestViewDefiner, sqlCode, squash } from './helpers/view-definer.js';

/**
 * THE NEWEST MIGRATION THAT DEFINES `vwContracts`, RESOLVED — NOT PINNED, AND RESOLVED BY THE ONE
 * SHARED HELPER rather than by a copy of the rule living here.
 *
 * This was a hardcoded filename, and it had already been hand-repointed once when the view moved in
 * the 2026-08-23 flatten. On 2026-08-30 it silently went stale a second time: contracts#28 item 13
 * moved the Terminated branch to `<=` in a NEW migration, and every assertion below carried on
 * reading the old file and passing. A suite whose stated job is "the migration says what we think it
 * says" was describing a migration the database no longer runs last. On 2026-09-20 it happened a
 * THIRD time, to a local pattern that matched `CREATE OR ALTER VIEW` and not the `DROP VIEW` +
 * `CREATE VIEW` that `V202609202354` used.
 *
 * Every one of those was a private copy of "which file is the definer" drifting on its own schedule,
 * so the rule is no longer written here. `helpers/view-definer.ts` owns it, for this file,
 * `dates-executed-doc-and-readonly.test.ts` and `executed-agreement-panel.test.ts` alike, and it
 * throws rather than falling back if a later migration mentions the view in a form it cannot read.
 *
 * `flat` is that file's SQL with BOTH comment forms stripped and whitespace normalised, so a reformat
 * of the view does not fail a predicate assertion and no assertion below can be satisfied — or
 * defeated — by the prose explaining the SQL. See `sqlCode` for why that matters in both directions;
 * `describe('sqlCode …')` at the bottom of this file measures it.
 */
const MIGRATIONS_DIR = fileURLToPath(new URL('../../../../migrations/', import.meta.url));
const VIEW = newestViewDefiner(MIGRATIONS_DIR, 'vwContracts');
const flat = VIEW.flat;

/**
 * The rule as a person would describe it, written from the requirement rather than from the SQL:
 * which fact decides the state, and the predicate that fact has to satisfy.
 *
 * The predicates are matched against the migration's SQL — comments stripped, whitespace normalised —
 * so a reformat of the view does not fail this and a comment cannot satisfy it, but a changed
 * comparison operator does fail, which is the point. The boundaries are compared against `bt.Today`,
 * the BUSINESS day (bc-aidp-next-golive#168), not against the server's UTC day.
 *
 * THE TWO BOUNDARIES ARE NOT THE SAME, and this preamble said they were. Expiry is `<`, because a
 * period ending on a date runs through the END of that date: an agreement whose term ends
 * 31 December is in force all of 31 December. TERMINATION is `<=` — contracts#28 item 13, which the
 * rule below has stated since V202608300100 — because setting a Terminated Date means terminated FROM
 * that date, which is what the Dates tab has always told the user. The effective boundary is `<=` for
 * the same reason termination is: a contract effective today is in force today.
 *
 * Saying "termination and expiry are both `<`" is not a wording slip. Item 13 has already been
 * reverted once by a migration whose author was reading a description of the rule rather than the
 * rule, so a preamble that contradicts the table below it is the beginning of the third oscillation.
 */
const RULE: ReadonlyArray<{ state: ContractState; because: string; predicate: string }> = [
    {
        state: 'Terminated',
        because: 'somebody ended the agreement, and the termination has taken effect',
        // `<=`, not `<` — contracts#28 item 13. Terminated means terminated FROM that date, which is
        // what the Dates tab has always told the user. Its neighbour `Expired` stays `<` on purpose:
        // an END date is the last day the agreement covers, a TERMINATED date is the day it stops.
        predicate: "g.TerminatedDate IS NOT NULL AND g.TerminatedDate <= bt.Today THEN 'Terminated'",
    },
    {
        state: 'Superseded',
        because: 'the successor FK IS the superseded state — there is no second fact to disagree',
        predicate: "g.SupersededByContractID IS NOT NULL THEN 'Superseded'",
    },
    {
        state: 'Expired',
        because: 'the term ran out on its own',
        predicate: "g.EndDate IS NOT NULL AND g.EndDate < bt.Today THEN 'Expired'",
    },
    {
        state: 'Active',
        because: 'started, not ended, not replaced',
        predicate: "g.EffectiveDate IS NOT NULL AND g.EffectiveDate <= bt.Today THEN 'Active'",
    },
    {
        state: 'Executed',
        because: 'signed but not yet in force — a WAIT, not the TASK that Draft means (R-19)',
        predicate: "g.ExecutedDate IS NOT NULL THEN 'Executed'",
    },
    { state: 'Draft', because: 'nothing has happened to it yet', predicate: "ELSE 'Draft'" },
];

describe('the view derives State, and the migration says what we think it says', () => {
    it.each(RULE)('$state — $because', ({ predicate }) => {
        expect(flat).toContain(squash(predicate));
    });

    it('evaluates the branches in the documented precedence order', () => {
        // Precedence IS the rule: every predicate can be individually correct and the answer still
        // wrong if a later fact outranks an earlier one. Terminated must beat Superseded must beat
        // Expired, and so on down.
        const positions = RULE.map((r) => flat.indexOf(squash(r.predicate)));
        expect(positions.every((p) => p >= 0)).toBe(true);
        expect(positions).toEqual([...positions].sort((a, b) => a - b));
    });

    it('exposes exactly the six states the client knows about', () => {
        // A seventh branch in the view, or a value the client cannot render, is a defect in whichever
        // side is behind. CONTRACT_STATES is the client's vocabulary; the view is the authority.
        expect([...CONTRACT_STATES]).toEqual(RULE.map((r) => r.state));
        const emitted = [...flat.matchAll(/THEN '([A-Za-z]+)'|ELSE '([A-Za-z]+)'/g)]
            .map((m) => m[1] ?? m[2])
            .filter((v) => (CONTRACT_STATES as readonly string[]).includes(v));
        expect([...new Set(emitted)].sort()).toEqual([...CONTRACT_STATES].sort());
    });

    it('takes "today" from the business zone, joined once, and never from the UTC clock', () => {
        // bc-aidp-next-golive#168: the server's UTC calendar day is already tomorrow for the whole
        // American evening, so a contract ending 31 December read as Expired from 6 PM Central (CST
        // is UTC-6; an hour later on CDT), and DaysToEnd, DaysUntilNoticeDeadline and the
        // cancellation window all moved an evening early.
        // ONE cross join, so every column in a row answers on the same day.
        expect(flat).toContain('CROSS JOIN [__mj_BizAppsCommon].[fnBusinessToday]() AS bt');
        expect(flat).not.toContain('GETUTCDATE');
        expect(flat).toContain('DATEDIFF(day, bt.Today, g.EndDate)');
        expect(flat).toContain('bt.Today >= DATEADD(day, -g.CancellationWindowDays, g.EndDate)');
        expect(flat).toContain('bt.Today <= g.EndDate');
    });

    it('publishes DaysUntilNoticeDeadline as the deadline measured from the business day', () => {
        /*
         * WHAT THE CLIENT FILTERS ON, AND WHY IT IS THIS COLUMN AND NOT A DATE.
         *
         * The Renewals page's notice pills, the dashboard's notice tile and the left-nav badge used to
         * compare `RenewalNoticeDeadline` against `CAST(GETUTCDATE() AS date)` — the server's UTC day,
         * already tomorrow all American evening — while this view judged the same deadline on
         * `bt.Today`, so from 6 PM Central a row the view said had notice time left was missing from
         * the pill (bc-aidp-next-golive#168). They now read `DaysUntilNoticeDeadline >= 0` / `< 0` /
         * `BETWEEN 0 AND n` instead, which cannot disagree with the view because the view computed it.
         *
         * That equivalence is what this pins. `DaysUntilNoticeDeadline >= 0` means
         * `RenewalNoticeDeadline >= bt.Today` ONLY while the two columns are built from the same
         * expression and the day-count is measured from `bt.Today`. Change either and three client
         * predicates quietly start meaning something else, in three files that mention neither this
         * migration nor each other — so the pairing is asserted here, where the newest definer of the
         * view is resolved rather than pinned.
         */
        const DEADLINE = 'DATEADD(day, -g.RenewalNoticeDays, g.EndDate)';
        expect(flat).toContain(`ELSE ${DEADLINE} END AS [RenewalNoticeDeadline]`);
        expect(flat).toContain(`DATEDIFF(day, bt.Today, ${DEADLINE})`);
        // And the NULL conditions must match, or `>= 0` stops standing in for `IS NOT NULL`.
        expect(flat).toContain('WHEN g.EndDate IS NULL OR g.RenewalNoticeDays IS NULL THEN NULL');
        expect(flat).toContain('WHEN g.EndDate IS NOT NULL AND g.RenewalNoticeDays IS NOT NULL THEN DATEDIFF(day, bt.Today,');
    });

    it('keeps IsAwaitingDocument narrowed to the Executed Agreement category', () => {
        // Item 16 (V202609010100) was silently reverted by V202609202354, which re-created the view
        // without the File/FileCategory joins — any linked file cleared the flag again. Nothing
        // caught it: the two tests that guarded this rule pinned themselves to the migration that
        // SEEDS the category row, not to the newest definer of the view, so they described the
        // 1 September file straight through the day the regression shipped. All three now resolve
        // the newest definer through the same helper, so the next re-creation that drops it fails.
        expect(flat).toContain("fc.Name = 'Executed Agreement'");
        expect(flat).toContain('JOIN [${mjSchema}].[FileCategory] fc');
    });

    it('is proved against a real database by fixtures anchored on the SAME day', () => {
        /*
         * `state-derivation.mjs` is the only thing that proves the SQL EVALUATES the way this file
         * reads it, and `V202609211200` broke its anchor. Its fixtures were placed at
         * `DATEADD(day, n, CAST(GETUTCDATE() AS date))` while the view judges them against
         * `bt.Today` — so for the whole American evening the row labelled "terminated TODAY" was
         * actually terminated TOMORROW, and three or more fixtures failed nightly against a correct
         * view. A harness that fails on a schedule stops being read.
         *
         * Checked here, and as SOURCE, because the harness needs a database and an instance `.env`,
         * so nothing in CI runs it. `GETUTCDATE` is deliberately NOT banned outright: the harness
         * prints the UTC day next to the business day when they differ, which is exactly the
         * information a person debugging an evening run wants. What is banned is a FIXTURE placed
         * on it.
         */
        const harness = readFileSync(
            fileURLToPath(new URL('../../../../test-harnesses/state-derivation.mjs', import.meta.url)),
            'utf8',
        );
        expect(harness).toContain("DECLARE @today date = (SELECT TOP 1 b.[Today] FROM [__mj_BizAppsCommon].[fnBusinessToday]() b)");
        expect(harness).not.toMatch(/DATEADD\(day,[^)]*,\s*CAST\(GETUTCDATE\(\) AS date\)\)/);
        // Every one of the four fixture dates, so a fifth column cannot be added on the UTC day.
        expect(harness.match(/DATEADD\(day, [^)]*, @today\)/g) ?? []).toHaveLength(4);
    });

    it('derives State in the VIEW and nowhere else', () => {
        // The regression guard for the mirroring that caused the divergence: if a TypeScript
        // derivation reappears, this fails. `contract-state.ts` is a value list, not a rule.
        const module = readFileSync(fileURLToPath(new URL('../contract-state.ts', import.meta.url)), 'utf8');
        expect(module).not.toMatch(/GETUTCDATE|function DeriveContractState|function StateSQL/);
    });
});

/**
 * THE STRIPPER ITSELF, because every assertion above is only as good as it is.
 *
 * `sqlCode` was `t.replace(/^\s*--.*$/gm, '')` — WHOLE-LINE comments only — and a TRAILING inline
 * comment walked through it in both directions. Measured against this very migration before the fix:
 * appending `-- was CAST(GETUTCDATE() AS date)` to a correct `Expired` branch failed
 * `not.toContain('GETUTCDATE')` (1 failed / 12 passed), and replacing the category predicate with
 * `AND 1 = 1 -- dropped, was: fc.Name = 'Executed Agreement'` kept the whole file green (13 passed)
 * with the gate gone from the executable SQL. The second is the regression the guard exists for,
 * passing.
 *
 * So the four cases below are the contract, not decoration: each one is a mutation the old helper
 * let through.
 */
describe('sqlCode — prose can neither satisfy nor defeat an assertion', () => {
    it('strips a TRAILING inline comment, not only a whole-line one', () => {
        const line = "        WHEN g.EndDate < bt.Today THEN 'Expired' -- was CAST(GETUTCDATE() AS date)";
        expect(sqlCode(line)).not.toContain('GETUTCDATE');
        expect(squash(sqlCode(line))).toBe("WHEN g.EndDate < bt.Today THEN 'Expired'");
    });

    it('a required predicate quoted in a trailing comment does not satisfy a presence check', () => {
        const line = "                   AND 1 = 1 -- dropped, was: fc.Name = 'Executed Agreement'";
        expect(squash(sqlCode(line))).not.toContain("fc.Name = 'Executed Agreement'");
        expect(squash(sqlCode(line))).toBe('AND 1 = 1');
    });

    it('strips block comments too, in both directions', () => {
        const banned = 'SELECT 1 /* the old view used CAST(GETUTCDATE() AS date) */ AS x';
        expect(sqlCode(banned)).not.toContain('GETUTCDATE');
        const claimed = "AND 1 = 1 /* was: fc.Name = 'Executed Agreement' */";
        expect(squash(sqlCode(claimed))).not.toContain("fc.Name = 'Executed Agreement'");
    });

    it('does not glue the tokens either side of a stripped comment together', () => {
        // Replacing with '' rather than ' ' would turn this into `ab` and invent a predicate.
        expect(squash(sqlCode('a--c\nb'))).toBe('a b');
        expect(squash(sqlCode('a/* c */b'))).toBe('a b');
    });
});
