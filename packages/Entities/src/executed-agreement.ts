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

/** The view's predicate, in TypeScript: `fc.Name = 'Executed Agreement'` under a case-insensitive collation. */
export function IsExecutedAgreementCategory(categoryName: string | null | undefined): boolean {
    return (categoryName ?? '').trim().toLowerCase() === EXECUTED_AGREEMENT_FILE_CATEGORY.toLowerCase();
}

/** What {@link SuggestExecutedAgreementFile} needs to know about one file linked to the contract. */
export interface LinkedFileSummary {
    FileID: string;
    CategoryName: string | null | undefined;
}

/**
 * Which linked file to offer as the executed agreement, or null to offer nothing (#117).
 *
 * Attaching the signed PDF does not clear "Awaiting document": only a file marked with the
 * Executed Agreement category does, and MJ's Attachments panel cannot set a category. So the
 * Executed agreement panel asks "is this the executed agreement?" for the file most likely to be
 * it. It only ever offers; a person confirms the mark.
 *
 *   · nothing while the contract is not awaiting its document, or a file is already marked
 *   · a file with another category is not offered: someone filed it as something else
 *   · a file the person answered "no" for (`dismissedIDs`) is not offered again
 *   · the file just attached, when there is one and it qualifies
 *   · otherwise the only linked file, when exactly one is linked and it qualifies
 *
 * UUIDs are compared case-insensitively (MJ returns either casing).
 */
export function SuggestExecutedAgreementFile(state: {
    isAwaitingDocument: boolean;
    files: readonly LinkedFileSummary[];
    justAttachedFileID?: string | null;
    dismissedIDs?: readonly string[];
}): string | null {
    if (!state.isAwaitingDocument) return null;
    if (state.files.some((f) => IsExecutedAgreementCategory(f.CategoryName))) return null;

    const key = (id: string | null | undefined) => (id ?? '').trim().toLowerCase();
    const dismissed = new Set((state.dismissedIDs ?? []).map(key));
    const offerable = (f: LinkedFileSummary) => !(f.CategoryName ?? '').trim() && !dismissed.has(key(f.FileID));

    const attached = key(state.justAttachedFileID);
    if (attached) {
        const file = state.files.find((f) => key(f.FileID) === attached);
        if (file && offerable(file)) return file.FileID;
    }
    if (state.files.length === 1 && offerable(state.files[0])) return state.files[0].FileID;
    return null;
}
