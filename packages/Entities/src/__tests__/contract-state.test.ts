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
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { CONTRACT_STATES, type ContractState } from '../contract-state.js';

/**
 * THE NEWEST MIGRATION THAT DEFINES `vwContracts`, RESOLVED — NOT PINNED.
 *
 * This was a hardcoded filename, and it had already been hand-repointed once when the view moved in
 * the 2026-08-23 flatten. On 2026-08-30 it silently went stale a second time: contracts#28 item 13
 * moved the Terminated branch to `<=` in a NEW migration, and every assertion below carried on
 * reading the old file and passing. A suite whose stated job is "the migration says what we think it
 * says" was describing a migration the database no longer runs last.
 *
 * Resolving the newest definer makes that impossible. Filename order is release order —
 * `migration-conventions.test.ts` proves the timestamps are zero-padded and strictly increasing, so a
 * plain sort is a real ordering rather than a hopeful one.
 */
const MIGRATIONS_DIR = fileURLToPath(new URL('../../../../migrations/', import.meta.url));
const DEFINES_VIEW = /CREATE\s+OR\s+ALTER\s+VIEW\s+\[\$\{flyway:defaultSchema\}\]\.\[vwContracts\]/i;
const definers = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .filter((f) => DEFINES_VIEW.test(readFileSync(MIGRATIONS_DIR + f, 'utf8')));
if (definers.length === 0) {
    throw new Error('No migration defines vwContracts — this suite would assert against nothing.');
}
const MIGRATION = definers[definers.length - 1];
const sql = readFileSync(MIGRATIONS_DIR + MIGRATION, 'utf8');
const squash = (s: string) => s.replace(/\s+/g, ' ').trim();
const flat = squash(sql);

/**
 * The rule as a person would describe it, written from the requirement rather than from the SQL:
 * which fact decides the state, and the predicate that fact has to satisfy.
 *
 * The predicates are matched against the migration text with whitespace normalised, so a reformat of
 * the view does not fail this — but a changed comparison operator does, which is the point. The
 * termination and expiry boundaries are `<` (not `<=`) because a period ending on a date runs through
 * the END of that date: an agreement "terminating on 31 December" is in force all of 31 December. The
 * effective boundary is `<=` for the mirror-image reason — a contract effective today is in force
 * today.
 */
const RULE: ReadonlyArray<{ state: ContractState; because: string; predicate: string }> = [
    {
        state: 'Terminated',
        because: 'somebody ended the agreement, and the termination has taken effect',
        // `<=`, not `<` — contracts#28 item 13. Terminated means terminated FROM that date, which is
        // what the Dates tab has always told the user. Its neighbour `Expired` stays `<` on purpose:
        // an END date is the last day the agreement covers, a TERMINATED date is the day it stops.
        predicate: "g.TerminatedDate IS NOT NULL AND g.TerminatedDate <= CAST(GETUTCDATE() AS date) THEN 'Terminated'",
    },
    {
        state: 'Superseded',
        because: 'the successor FK IS the superseded state — there is no second fact to disagree',
        predicate: "g.SupersededByContractID IS NOT NULL THEN 'Superseded'",
    },
    {
        state: 'Expired',
        because: 'the term ran out on its own',
        predicate: "g.EndDate IS NOT NULL AND g.EndDate < CAST(GETUTCDATE() AS date) THEN 'Expired'",
    },
    {
        state: 'Active',
        because: 'started, not ended, not replaced',
        predicate: "g.EffectiveDate IS NOT NULL AND g.EffectiveDate <= CAST(GETUTCDATE() AS date) THEN 'Active'",
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

    it('derives State in the VIEW and nowhere else', () => {
        // The regression guard for the mirroring that caused the divergence: if a TypeScript
        // derivation reappears, this fails. `contract-state.ts` is a value list, not a rule.
        const module = readFileSync(fileURLToPath(new URL('../contract-state.ts', import.meta.url)), 'utf8');
        expect(module).not.toMatch(/GETUTCDATE|function DeriveContractState|function StateSQL/);
    });
});
