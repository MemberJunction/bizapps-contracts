/**
 * @fileoverview The contract lifecycle, stated ONCE.
 *
 * `State` is derived, not stored (D-19 / ERD R-18): four of the old `Status` column's five values
 * were projections of the dates and the two self-FKs, and a stored copy of a projection can only
 * agree or lie. But "derived" creates its own hazard — the rule now has to exist in SQL (the layered
 * base view), in TypeScript (chips, filters, a client deciding what to show), and in whatever a
 * `RunView` filter string says. Three copies of a six-branch precedence chain is three chances to
 * get the precedence subtly different, and the one that drifts is silently wrong.
 *
 * So this module is the single statement of the rule, and everything else RENDERS from it:
 * `DeriveContractState()` for TypeScript, `StateSQL()` for the view. `contract-state.test.ts` asserts
 * the two agree branch-for-branch, and asserts that `StateSQL()` still matches the SQL actually
 * committed in the migration — so a hand-edit to either one fails a test rather than shipping.
 *
 * Same pattern as orders' `overdue.ts`, adopted for the same reason: they had four hand-rolled copies
 * of "is this overdue" and the one in the collections view had forgotten the Status clause, so voided
 * orders appeared on a collections list for money nobody owed.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/** The six lifecycle states, in precedence order — first match wins (ERD §4.5). */
export const CONTRACT_STATES = ['Terminated', 'Superseded', 'Expired', 'Active', 'Executed', 'Draft'] as const;

export type ContractState = (typeof CONTRACT_STATES)[number];

/**
 * The facts the derivation reads. Deliberately a plain shape rather than the entity: the rule is
 * about six values, and taking the entity would make it untestable without a provider and unusable
 * from a row that came back as raw view data.
 *
 * Dates are `string | Date | null` because a view row hands back whatever the driver produced; the
 * comparison normalises to a calendar date, never a timestamp, so a contract effective TODAY is
 * Active regardless of the hour.
 */
export interface ContractStateFacts {
    TerminatedDate?: string | Date | null;
    SupersededByContractID?: string | null;
    EndDate?: string | Date | null;
    EffectiveDate?: string | Date | null;
    ExecutedDate?: string | Date | null;
}

/** Midnight-anchored calendar date, or null. Comparing dates, not instants, is the whole point. */
function asDate(value: string | Date | null | undefined): Date | null {
    if (value === null || value === undefined || value === '') return null;
    const d = value instanceof Date ? new Date(value.getTime()) : new Date(value);
    if (Number.isNaN(d.getTime())) return null;
    return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

/** Today, as a calendar date in UTC — matching the view's `CAST(GETUTCDATE() AS date)`. */
function todayUTC(now?: Date): Date {
    const n = now ?? new Date();
    return new Date(Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate()));
}

/**
 * Derive the lifecycle state. `now` is injectable so tests can pin a date rather than construct
 * fixtures relative to the clock — a test that says "next month" and passes only until the month
 * turns over is worse than no test.
 *
 * The branches, and why they are in this order:
 *
 *  1. `Terminated` outranks everything. Somebody ended this agreement; that is a fact about what
 *     happened, not a projection of the term. It stays Terminated after the end date passes, which is
 *     why `TerminatedDate` is stored even though it looks derivable.
 *  2. `Superseded` — the successor FK IS the state. R-18 dropped the tautological CHECK that used to
 *     tie a `Status` value to this column, because there is no longer a second fact to disagree.
 *  3. `Expired` — the term ran out on its own.
 *  4. `Active` — started, not ended, not replaced. In force.
 *  5. `Executed` (R-19) — signed but NOT YET in force. This branch is the whole reason the enum has
 *     six values: without it, a contract signed weeks before its term starts fell through to `Draft`,
 *     indistinguishable from one nobody had touched. That is the ordinary case in renewal season.
 *     `Draft` is a TASK (finish this); `Executed` is a WAIT (nothing to do until the date arrives),
 *     and a watchlist that merges them makes finance re-triage the same rows every week.
 *  6. `Draft` — everything else.
 *
 * Note branch 5 accepts a null `EffectiveDate`: a signed contract with no start date recorded is
 * `Executed`, because the signature is the fact that moved it on.
 */
export function DeriveContractState(facts: ContractStateFacts, now?: Date): ContractState {
    const today = todayUTC(now);
    const end = asDate(facts.EndDate);
    const effective = asDate(facts.EffectiveDate);

    if (asDate(facts.TerminatedDate) !== null) return 'Terminated';
    if (facts.SupersededByContractID) return 'Superseded';
    if (end !== null && end < today) return 'Expired';
    if (effective !== null && effective <= today) return 'Active';
    if (asDate(facts.ExecutedDate) !== null) return 'Executed';
    return 'Draft';
}

/**
 * The same rule as a T-SQL `CASE` expression, for the layered base view.
 *
 * @param alias the alias of the generated inner view in the wrapper (`g` in `vwContracts`).
 *
 * The returned text is what `V202608182001__…_derived_columns_outer_view.sql` contains, and
 * `contract-state.test.ts` asserts that it still does. If you change a branch here, the test fails
 * until the migration is regenerated from it — which is the point, because the alternative is a view
 * and a client that quietly disagree about what `Active` means.
 */
export function StateSQL(alias = 'g'): string {
    const a = alias;
    return (
        `CASE\n` +
        `        WHEN ${a}.TerminatedDate IS NOT NULL THEN 'Terminated'\n` +
        `        WHEN ${a}.SupersededByContractID IS NOT NULL THEN 'Superseded'\n` +
        `        WHEN ${a}.EndDate IS NOT NULL AND ${a}.EndDate < CAST(GETUTCDATE() AS date) THEN 'Expired'\n` +
        `        WHEN ${a}.EffectiveDate IS NOT NULL AND ${a}.EffectiveDate <= CAST(GETUTCDATE() AS date) THEN 'Active'\n` +
        `        WHEN ${a}.ExecutedDate IS NOT NULL THEN 'Executed'\n` +
        `        ELSE 'Draft'\n` +
        `    END`
    );
}

/** States a person can still act on — what the watchlist and the contract list default to. */
export const OPEN_CONTRACT_STATES: readonly ContractState[] = ['Draft', 'Executed', 'Active'];

/** Whether a state means the agreement is finished with, one way or another. */
export function IsClosedState(state: ContractState): boolean {
    return state === 'Expired' || state === 'Terminated' || state === 'Superseded';
}
