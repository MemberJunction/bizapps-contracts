/**
 * The contract lifecycle, exhaustively — and the guard that the SQL and the TypeScript cannot drift.
 *
 * WHY THIS FILE MATTERS MORE THAN A TYPICAL DERIVATION TEST. `State` replaced a stored column
 * (D-19 / R-18), so the rule now lives in two renderings: the layered base view's CASE expression and
 * `DeriveContractState()`. Both are generated from `contract-state.ts`, and the last describe block
 * asserts the committed migration still contains what the module renders. Without that assertion the
 * two can be edited apart, and the failure is invisible: a grid chip says Active, a `RunView` filter
 * disagrees, and nobody finds out until finance acts on the wrong list.
 *
 * `now` is pinned in every case. A test that says "next month" relative to the clock passes until the
 * month turns over, which is the worst kind of test — it fails on a date nobody changed anything on.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
    CONTRACT_STATES,
    DeriveContractState,
    IsClosedState,
    OPEN_CONTRACT_STATES,
    StateSQL,
    type ContractState,
    type ContractStateFacts,
} from '../contract-state.js';

/** A fixed "today" for every case below. Mid-month, so month-boundary arithmetic cannot flatter us. */
const NOW = new Date('2026-08-18T13:45:00Z');

/**
 * The lifecycle as a person would describe it, written out independently of the implementation —
 * scenario, the facts, the state it must derive to, and WHY that is the right answer.
 */
const CASES: ReadonlyArray<{ scenario: string; facts: ContractStateFacts; expected: ContractState }> = [
    // ─── Terminated outranks everything ────────────────────────────────────────────────────────
    {
        scenario: 'terminated mid-term',
        facts: { ExecutedDate: '2026-01-01', EffectiveDate: '2026-01-01', EndDate: '2027-01-01', TerminatedDate: '2026-06-01' },
        expected: 'Terminated',
    },
    {
        scenario: 'terminated AND expired — termination is what happened, expiry is only a projection',
        facts: { ExecutedDate: '2025-01-01', EffectiveDate: '2025-01-01', EndDate: '2025-06-01', TerminatedDate: '2025-07-01' },
        expected: 'Terminated',
    },
    {
        scenario: 'terminated AND superseded — still Terminated; the earlier branch wins by design',
        facts: { EffectiveDate: '2025-01-01', TerminatedDate: '2025-07-01', SupersededByContractID: 'c0000000-0000-4000-8000-000000000001' },
        expected: 'Terminated',
    },
    // ─── The termination BOUNDARY, which is contract law and not a coding preference ────────────
    // A period ending on a date runs through the END of that date: an agreement "terminating on 31
    // December" is in force all of 31 December. So `TerminatedDate` TODAY is still in force today,
    // and reads Terminated from tomorrow. NOW is pinned to 2026-08-18, so today IS 2026-08-18.
    //
    // These three cases exist because the rule was wrong in both directions at different times. It
    // first read `TerminatedDate IS NOT NULL` — so a termination scheduled for next year made a
    // live contract read Terminated today. A later edit added an unreachable `> today` branch
    // asserting the opposite. Neither was caught, because nothing tested the boundary.
    {
        scenario: 'terminated YESTERDAY — the termination has taken effect',
        facts: { EffectiveDate: '2026-01-01', EndDate: '2027-01-01', TerminatedDate: '2026-08-17' },
        expected: 'Terminated',
    },
    {
        scenario: 'terminated TODAY — still in force through the end of the termination date',
        facts: { EffectiveDate: '2026-01-01', EndDate: '2027-01-01', TerminatedDate: '2026-08-18' },
        expected: 'Active',
    },
    {
        scenario: 'terminated TOMORROW — notice served, not yet effective; it is still a live contract',
        facts: { EffectiveDate: '2026-01-01', EndDate: '2027-01-01', TerminatedDate: '2026-08-19' },
        expected: 'Active',
    },
    {
        scenario: 'terminated far in the future, never started — Draft, not Terminated',
        facts: { TerminatedDate: '2027-01-01' },
        expected: 'Draft',
    },

    // ─── Superseded: the successor FK IS the state (R-18) ──────────────────────────────────────
    {
        scenario: 'replaced by newer paper, still inside its own term',
        facts: { ExecutedDate: '2026-01-01', EffectiveDate: '2026-01-01', EndDate: '2027-01-01', SupersededByContractID: 'c0000000-0000-4000-8000-000000000002' },
        expected: 'Superseded',
    },
    {
        scenario: 'superseded outranks expired',
        facts: { EffectiveDate: '2024-01-01', EndDate: '2025-01-01', SupersededByContractID: 'c0000000-0000-4000-8000-000000000003' },
        expected: 'Superseded',
    },

    // ─── Expired ──────────────────────────────────────────────────────────────────────────────
    { scenario: 'term ran out on its own', facts: { ExecutedDate: '2025-01-01', EffectiveDate: '2025-01-01', EndDate: '2025-12-31' }, expected: 'Expired' },
    {
        scenario: 'ended YESTERDAY — the boundary that decides whether the last day counts',
        facts: { EffectiveDate: '2026-01-01', EndDate: '2026-08-17' },
        expected: 'Expired',
    },

    // ─── Active ───────────────────────────────────────────────────────────────────────────────
    { scenario: 'in force now', facts: { ExecutedDate: '2026-01-01', EffectiveDate: '2026-01-01', EndDate: '2027-01-01' }, expected: 'Active' },
    {
        scenario: 'ends TODAY — still in force; a contract is live through its final day',
        facts: { EffectiveDate: '2026-01-01', EndDate: '2026-08-18' },
        expected: 'Active',
    },
    {
        scenario: 'effective TODAY — in force from the first day, not the day after',
        facts: { ExecutedDate: '2026-08-01', EffectiveDate: '2026-08-18', EndDate: '2027-08-17' },
        expected: 'Active',
    },
    {
        scenario: 'active with no end date — evergreen paper never expires into Draft',
        facts: { ExecutedDate: '2026-01-01', EffectiveDate: '2026-01-01' },
        expected: 'Active',
    },
    {
        scenario: 'effective in the past but never signed — in force regardless; Active does not require a signature',
        facts: { EffectiveDate: '2026-01-01', EndDate: '2027-01-01' },
        expected: 'Active',
    },

    // ─── Executed (R-19) — the branch this test exists for ────────────────────────────────────
    {
        scenario: 'R-19: signed in August, starts in September — the renewal-season case that used to read Draft',
        facts: { ExecutedDate: '2026-08-01', EffectiveDate: '2026-09-15', EndDate: '2027-09-14' },
        expected: 'Executed',
    },
    {
        scenario: 'R-19: signed, no start date recorded — the signature is the fact that moved it on',
        facts: { ExecutedDate: '2026-08-01' },
        expected: 'Executed',
    },
    {
        scenario: 'R-19 boundary: signed, effective TOMORROW — not yet in force',
        facts: { ExecutedDate: '2026-08-01', EffectiveDate: '2026-08-19' },
        expected: 'Executed',
    },

    // ─── Draft ────────────────────────────────────────────────────────────────────────────────
    { scenario: 'nothing recorded at all', facts: {}, expected: 'Draft' },
    {
        scenario: 'dates PLANNED but unsigned — must NOT be Executed; this is the inverse of R-19',
        facts: { EffectiveDate: '2026-09-15', EndDate: '2027-09-14' },
        expected: 'Draft',
    },
    { scenario: 'empty strings, as a view row can hand back', facts: { ExecutedDate: '', EffectiveDate: '', EndDate: '' }, expected: 'Draft' },
];

describe('DeriveContractState — every branch and both sides of every boundary', () => {
    for (const { scenario, facts, expected } of CASES) {
        it(`${expected}: ${scenario}`, () => {
            expect(DeriveContractState(facts, NOW)).toBe(expected);
        });
    }

    it('reaches every one of the six states across the case table', () => {
        const reached = new Set(CASES.map((c) => DeriveContractState(c.facts, NOW)));
        // A case table that never produces `Executed` would have passed happily before R-19 existed.
        expect([...reached].sort()).toEqual([...CONTRACT_STATES].sort());
    });

    it('accepts Date objects and ISO strings interchangeably', () => {
        const asString = DeriveContractState({ EffectiveDate: '2026-01-01' }, NOW);
        const asDate = DeriveContractState({ EffectiveDate: new Date('2026-01-01T00:00:00Z') }, NOW);
        expect(asString).toBe(asDate);
        expect(asString).toBe('Active');
    });

    it('compares calendar dates, not instants — a late-in-the-day clock cannot change the answer', () => {
        const facts: ContractStateFacts = { EffectiveDate: '2026-08-18' };
        const earlyMorning = DeriveContractState(facts, new Date('2026-08-18T00:00:01Z'));
        const lateEvening = DeriveContractState(facts, new Date('2026-08-18T23:59:59Z'));
        expect(earlyMorning).toBe('Active');
        expect(lateEvening).toBe('Active');
    });

    it('ignores an unparseable date rather than throwing', () => {
        // A malformed value must not take down a grid render. It degrades to "not set".
        expect(DeriveContractState({ ExecutedDate: 'not-a-date' }, NOW)).toBe('Draft');
    });
});

describe('state helpers', () => {
    it('classifies exactly the three finished states as closed', () => {
        const closed = CONTRACT_STATES.filter(IsClosedState);
        expect([...closed].sort()).toEqual(['Expired', 'Superseded', 'Terminated']);
    });

    it('treats the open states as the complement of the closed ones', () => {
        const open = CONTRACT_STATES.filter((s) => !IsClosedState(s));
        expect([...open].sort()).toEqual([...OPEN_CONTRACT_STATES].sort());
    });

    it('counts Executed as open — it is a wait, not a finished agreement', () => {
        expect(OPEN_CONTRACT_STATES).toContain('Executed');
        expect(IsClosedState('Executed')).toBe(false);
    });
});

/**
 * THE ANTI-DRIFT GUARD. Reads the committed migration and asserts it still contains what `StateSQL()`
 * renders. Whitespace is normalised — asserting exact indentation would fail on a reformat that
 * changes no behaviour, and a test that cries wolf gets deleted — but every predicate, every literal
 * and the branch ORDER are compared as-is, which is what can actually be wrong.
 */
describe('SQL and TypeScript render the same rule', () => {
    const MIGRATION = 'V202608182001__v0.1.x__Contracts_derived_columns_outer_view.sql';
    const squash = (s: string) => s.replace(/\s+/g, ' ').trim();

    const migrationSql = readFileSync(fileURLToPath(new URL(`../../../../migrations/${MIGRATION}`, import.meta.url)), 'utf8');

    it('the wrapper view contains the CASE that StateSQL() renders', () => {
        expect(squash(migrationSql)).toContain(squash(StateSQL('g')));
    });

    it('renders against whatever alias the caller uses', () => {
        expect(StateSQL('x')).toContain('x.TerminatedDate');
        expect(StateSQL('x')).not.toContain('g.TerminatedDate');
    });

    it('orders the SQL branches exactly as the TypeScript evaluates them', () => {
        const sql = StateSQL('g');
        const positions = CONTRACT_STATES.map((s) => sql.indexOf(`'${s}'`));
        // Every state present, and strictly increasing — precedence IS the rule here, so an
        // out-of-order branch is a real defect even though every individual predicate is correct.
        expect(positions.every((p) => p >= 0)).toBe(true);
        expect(positions).toEqual([...positions].sort((a, b) => a - b));
    });
});
