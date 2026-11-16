/**
 * Golive #490 — the executed agreement can be uploaded and marked in one step, and the Overview names
 * the step that is actually missing.
 *
 * The wording is a pure function and is tested directly. The panel and Overview wiring is asserted
 * against the source, like `executed-agreement-panel.test.ts`: rendering either needs Angular, a form
 * host and a provider, and what is pinned here is a config key, a gate and a call.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { ExecutedAgreementPrompt } from '../executed-agreement-prompt.js';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const strip = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

const PANEL = strip(readFileSync(root('packages/Angular/src/lib/form-panels/executed-agreement.panel.ts'), 'utf8'));
const OVERVIEW = strip(readFileSync(root('packages/Angular/src/lib/form-panels/contract-form.panels.ts'), 'utf8'));
const NG_PACKAGE = JSON.parse(readFileSync(root('packages/Angular/package.json'), 'utf8')) as {
    peerDependencies: Record<string, string>;
    devDependencies: Record<string, string>;
};

describe('ExecutedAgreementPrompt', () => {
    it('says nothing when the contract is not awaiting its agreement', () => {
        expect(ExecutedAgreementPrompt(false, 0)).toBeNull();
        expect(ExecutedAgreementPrompt(null, 3)).toBeNull();
        expect(ExecutedAgreementPrompt(undefined, null)).toBeNull();
    });

    it('asks for upload AND mark when no file is linked', () => {
        const p = ExecutedAgreementPrompt(true, 0)!;
        expect(p.Health).toBe('Executed agreement not uploaded and marked.');
        expect(p.NextMove).toMatch(/^Upload the signed agreement and mark it as the executed agreement/);
    });

    it('asks only for the mark when files are linked but none is marked', () => {
        const p = ExecutedAgreementPrompt(true, 2)!;
        expect(p.Health).toBe('Files are attached, but none is marked as the executed agreement.');
        expect(p.NextMove).toMatch(/^Mark the signed agreement as the executed agreement/);
    });

    it('names both steps when the file count could not be read', () => {
        expect(ExecutedAgreementPrompt(true, null)).toEqual(ExecutedAgreementPrompt(true, 0));
    });

    it('never tells anyone to "attach" alone, the wording that hid the mark step', () => {
        for (const n of [null, 0, 1]) {
            const p = ExecutedAgreementPrompt(true, n)!;
            expect(p.Health + p.NextMove).not.toMatch(/\battach the executed agreement\b/i);
            expect(p.Health + p.NextMove).toMatch(/mark/i);
        }
    });
});

describe('the Executed agreement panel uploads into the category', () => {
    it('opens MJ\'s attachments component with DefaultCategoryID set to the Executed Agreement row', () => {
        expect(PANEL).toContain("import { FileStorageModule, type RecordAttachmentsConfig } from '@memberjunction/ng-file-storage';");
        expect(PANEL).toContain('this.UploadConfig = { DefaultCategoryID: this.CategoryID };');
        expect(PANEL).toMatch(/<mj-record-attachments[\s\S]*?\[Config\]="UploadConfig"/);
    });

    it('offers the button only outside edit mode, with the category resolved', () => {
        expect(PANEL).toContain('return !this.ReadOnly && !!this.CategoryID && !this.LoadError;');
        expect(PANEL).toContain('Upload executed agreement');
    });

    it('carries the one-line hint naming both routes', () => {
        expect(PANEL).toContain('Upload the signed agreement here, or attach it from the toolbar and mark it below.');
    });

    it('re-reads the record when the upload closes, since it may clear IsAwaitingDocument', () => {
        expect(PANEL).toMatch(/public async OnUploadClosed\(\)[\s\S]*?await this\.reReadRecord\(\);/);
    });

    it('declares ng-file-storage as a caret peer with a matching dev entry', () => {
        expect(NG_PACKAGE.peerDependencies['@memberjunction/ng-file-storage']).toBe(NG_PACKAGE.peerDependencies['@memberjunction/core']);
        expect(NG_PACKAGE.devDependencies['@memberjunction/ng-file-storage']).toBe(NG_PACKAGE.devDependencies['@memberjunction/core']);
    });
});

describe('the Overview reads its executed-agreement wording from the shared function', () => {
    it('uses ExecutedAgreementPrompt for both the health line and the next step', () => {
        expect(OVERVIEW).toContain('out.push(executed.Health);');
        expect(OVERVIEW).toContain('if (executed) return executed.NextMove;');
        expect(OVERVIEW).not.toContain("'Executed agreement not attached.'");
        expect(OVERVIEW).not.toContain("'Attach the executed agreement.'");
    });

    it('counts linked files per record, so a reused form cannot show another contract\'s count', () => {
        expect(OVERVIEW).toContain('this.countedFor !== id');
        expect(OVERVIEW).toContain("ResultType: 'count_only'");
        expect(OVERVIEW).toContain('MJC_FOREIGN_ENTITIES.FileEntityRecordLink');
    });
});
