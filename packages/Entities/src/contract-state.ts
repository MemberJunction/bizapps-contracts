/**
 * @fileoverview The contract lifecycle — the VALUES only. The rule itself lives in SQL.
 *
 * `State` is derived, not stored (D-19 / ERD R-18): four of the old `Status` column's five values
 * were projections of the dates and the two self-FKs, and a stored copy of a projection can only
 * agree or lie. It is derived in exactly ONE place — the `CASE` in the app-owned layered base view
 * (`V202608182001`) — and application code READS `contract.State`. It does not re-derive it.
 *
 * WHY THIS FILE NO LONGER CARRIES THE RULE (Marcelo, 2026-08-19). It used to hold
 * `DeriveContractState()` for TypeScript and `StateSQL()` to render the same rule as T-SQL, on the
 * reasoning that one module rendering both copies could not drift. That reasoning was wrong, and it
 * failed in the most direct way available: the TypeScript branch for termination was tightened to
 * "terminated before today", the view was not, and for several hours the same contract read `Active`
 * in the browser and `Terminated` from every view-backed query. The guard did not fire because it
 * compared the two renderings as TEXT, and text cannot see a semantic split.
 *
 * The lesson is not "write a better guard" — a guard that has to be right about two implementations
 * is a third thing to get wrong. It is: **do not mirror a rule.** One definition, in one language.
 * SQL wins here because the rule is time-dependent (`Expired` and `Active` turn over at midnight with
 * no write to trigger them), so it must be evaluated at READ time, which is what a view does and what
 * no amount of TypeScript can do for a row nobody has loaded.
 *
 * WHAT THAT COSTS, stated plainly: the rule can no longer be tested without a database, so
 * `npx vitest run` cannot cover its semantics. Two things stand in for it. `contract-state.test.ts`
 * asserts the committed migration's `CASE` matches the branches and precedence THIS TEST declares —
 * an expectation owned by the test, checked against the single implementation, so it is not two
 * implementations agreeing with each other. And `test-harnesses/state-equivalence.mjs` runs fixtures
 * covering every state and the termination boundary through the deployed view and asserts the answers
 * a person wrote down.
 *
 * A contract being EDITED therefore shows its last-saved state, not a live projection of unsaved
 * dates. That is deliberate: a chip reacting to an unsaved date asserts something no query would
 * agree with.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/**
 * The six lifecycle states, in precedence order — first match wins (ERD §4.5).
 *
 * Kept in TypeScript because the CLIENT needs the vocabulary (chip colours, a filter pill, a typed
 * `State` accessor) even though it does not own the rule. This is a value list, not a second
 * implementation: nothing here decides which state a contract is in.
 *
 * The order is load-bearing documentation of the view's precedence, and
 * `contract-state.test.ts` asserts the migration's `CASE` still matches it.
 */
export const CONTRACT_STATES = ['Terminated', 'Superseded', 'Expired', 'Active', 'Executed', 'Draft'] as const;

export type ContractState = (typeof CONTRACT_STATES)[number];
