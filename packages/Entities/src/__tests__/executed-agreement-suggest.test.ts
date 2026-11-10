/**
 * #117 — attaching the signed PDF left the contract "Awaiting document" until someone found the
 * Mark action. The Executed agreement panel now asks about the file just attached;
 * `SuggestExecutedAgreementFile` decides which file, if any, it asks about.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { IsExecutedAgreementCategory, SuggestExecutedAgreementFile } from '../executed-agreement.js';

const A = 'AAAAAAAA-0000-4000-8000-00000000000A';
const B = 'BBBBBBBB-0000-4000-8000-00000000000B';
const unmarked = (FileID: string) => ({ FileID, CategoryName: null });

describe('SuggestExecutedAgreementFile', () => {
    it('offers the file just attached while the contract awaits its document', () => {
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: true, files: [unmarked(A), unmarked(B)], justAttachedFileID: B })).toBe(B);
    });
    it('matches the attached file case-insensitively', () => {
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: true, files: [unmarked(A), unmarked(B)], justAttachedFileID: B.toLowerCase() })).toBe(B);
    });
    it('offers the only linked file when nothing was just attached', () => {
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: true, files: [unmarked(A)] })).toBe(A);
    });
    it('offers nothing among several files when none was just attached', () => {
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: true, files: [unmarked(A), unmarked(B)] })).toBeNull();
    });
    it('offers nothing when the contract is not awaiting its document', () => {
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: false, files: [unmarked(A)], justAttachedFileID: A })).toBeNull();
    });
    it('offers nothing once a file is marked', () => {
        const files = [{ FileID: A, CategoryName: 'Executed Agreement' }, unmarked(B)];
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: true, files, justAttachedFileID: B })).toBeNull();
    });
    it('does not offer a file someone filed under another category', () => {
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: true, files: [{ FileID: A, CategoryName: 'Invoice' }], justAttachedFileID: A })).toBeNull();
    });
    it('does not offer a file again after "Not this file"', () => {
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: true, files: [unmarked(A)], justAttachedFileID: A, dismissedIDs: [A.toLowerCase()] })).toBeNull();
    });
    it('falls back to the only file when the attached one is not listed (unreadable)', () => {
        expect(SuggestExecutedAgreementFile({ isAwaitingDocument: true, files: [unmarked(A)], justAttachedFileID: B })).toBe(A);
    });
});

describe('IsExecutedAgreementCategory', () => {
    it('matches the category name case- and whitespace-insensitively, as the view collation does', () => {
        expect(IsExecutedAgreementCategory(' executed agreement ')).toBe(true);
        expect(IsExecutedAgreementCategory('Invoice')).toBe(false);
        expect(IsExecutedAgreementCategory(null)).toBe(false);
    });
});

describe('the panel asks at attach time', () => {
    const PANEL = readFileSync(
        fileURLToPath(new URL('../../../Angular/src/lib/form-panels/executed-agreement.panel.ts', import.meta.url)),
        'utf8',
    );
    it('listens for file links to this contract and reloads, remembering a created one', () => {
        expect(PANEL).toContain('MJGlobal.Instance.GetEventListener(false).subscribe');
        expect(PANEL).toContain('MJC_FOREIGN_ENTITIES.FileEntityRecordLink');
        expect(PANEL).toContain("ev.saveSubType === 'create'");
        expect(PANEL).toContain('this.entityEvents?.unsubscribe()');
    });
    it('takes the decision from SuggestExecutedAgreementFile and leaves the mark to a click', () => {
        expect(PANEL).toContain('SuggestExecutedAgreementFile(');
        expect(PANEL).toContain('(click)="Mark(suggested)"');
        expect(PANEL).toContain('(click)="Dismiss(suggested)"');
    });
});
