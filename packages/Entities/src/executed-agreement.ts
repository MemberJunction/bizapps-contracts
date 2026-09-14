/**
 * @fileoverview The file category that answers "is the executed agreement attached?"
 *
 * `vwContracts.IsAwaitingDocument` (migration V202609010100, golive #203 item 16) clears only when a
 * file linked to the contract carries MJ's file category named 'Executed Agreement'. The view matches
 * the category BY NAME, and the migration seeds the row by the same name, because both the Entity id
 * and the category id are minted per database and a hardcoded UUID stops matching the first time
 * either is rebuilt from zero.
 *
 * This is the THIRD place the name appears, and it must agree with the other two. It lives in the
 * shared entities package rather than in the Angular panel that uses it so that a server job, a
 * script or a test can mark a file the same way the form does — and so one test can pin all three
 * spellings to each other (`executed-agreement-panel.test.ts`).
 *
 * @module @mj-biz-apps/contracts-entities
 */

/**
 * The `MJ: File Categories` Name whose presence on a linked `MJ: Files` row clears
 * `IsAwaitingDocument`. Must equal the Name seeded by V202609010100.
 */
export const EXECUTED_AGREEMENT_FILE_CATEGORY = 'Executed Agreement';
