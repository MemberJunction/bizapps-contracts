/**
 * @fileoverview What the contract Overview says while the executed agreement is missing (golive #490).
 *
 * `IsAwaitingDocument` clears only when a linked file carries the Executed Agreement category, so the
 * missing step is often the MARK, not the upload: a person attaches the signed PDF from the toolbar and
 * the contract still reads "awaiting". The Overview used to say "attach" in both cases. It now tells the
 * two apart by whether any file is linked to the contract: none linked means upload and mark, files
 * linked but none marked means mark.
 *
 * Kept here, not in the Angular panel, so the wording is tested without a form host.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/** The Overview's health line and next step for a contract that is awaiting its executed agreement. */
export interface ExecutedAgreementPromptText {
    /** One line in the Overview's health list. */
    Health: string;
    /** The Overview's "Next step" sentence. */
    NextMove: string;
}

/**
 * The prompt for a contract's missing executed agreement, or null when nothing is missing.
 *
 * @param isAwaitingDocument `vwContracts.IsAwaitingDocument` as read on the record.
 * @param linkedFileCount how many files are linked to the contract; null when the count could not be
 *        read, which gets the upload-and-mark wording because it names both steps.
 */
export function ExecutedAgreementPrompt(
    isAwaitingDocument: boolean | null | undefined,
    linkedFileCount: number | null | undefined,
): ExecutedAgreementPromptText | null {
    if (!isAwaitingDocument) return null;
    if (linkedFileCount != null && linkedFileCount > 0) {
        return {
            Health: 'Files are attached, but none is marked as the executed agreement.',
            NextMove: 'Mark the signed agreement as the executed agreement in the Executed agreement section.',
        };
    }
    return {
        Health: 'Executed agreement not uploaded and marked.',
        NextMove: 'Upload the signed agreement and mark it as the executed agreement in the Executed agreement section.',
    };
}
