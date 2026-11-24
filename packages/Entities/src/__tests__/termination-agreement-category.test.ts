/**
 * The termination-agreement file category has one spelling, in three places that must agree:
 *
 *   · the metadata record SHIPS the row by name (MJ metadata rows are never inserted by a migration),
 *   · the constant in this package is what any flow filing the document uses,
 *   · the contract form's panel LOOKS IT UP by name through that constant.
 *
 * Asserted against the source, like `executed-agreement-panel.test.ts`.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { EXECUTED_AGREEMENT_FILE_CATEGORY, TERMINATION_AGREEMENT_FILE_CATEGORY } from '../executed-agreement.js';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const strip = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

const PANEL = strip(readFileSync(root('packages/Angular/src/lib/form-panels/executed-agreement.panel.ts'), 'utf8'));
const SYNC = JSON.parse(readFileSync(root('metadata/file-categories/.mj-sync.json'), 'utf8')) as { entity: string };
const RECORDS = JSON.parse(readFileSync(root('metadata/file-categories/.file-categories.json'), 'utf8')) as {
    fields: { Name: string; Description: string };
}[];

describe('one spelling of the termination-agreement category name', () => {
    it('the constant is spelled as the other app files it', () => {
        expect(TERMINATION_AGREEMENT_FILE_CATEGORY).toBe('Termination Agreement');
    });

    it('the metadata record ships the row under the same name, on MJ: File Categories', () => {
        expect(SYNC.entity).toBe('MJ: File Categories');
        expect(RECORDS.map((r) => r.fields.Name)).toEqual([TERMINATION_AGREEMENT_FILE_CATEGORY]);
        expect(RECORDS[0].fields.Description.length).toBeGreaterThan(0);
    });

    it('the metadata does not repeat the category an applied migration already seeds', () => {
        // A record pushed without its primary key is inserted, so repeating it would add a second row
        // of the same name on every database that ran the seeding migration.
        expect(RECORDS.map((r) => r.fields.Name)).not.toContain(EXECUTED_AGREEMENT_FILE_CATEGORY);
    });

    it('no migration inserts the row', () => {
        const dir = root('migrations');
        const hits = readdirSync(dir)
            .filter((f) => f.endsWith('.sql') && !f.includes('Metadata_Sync'))
            .filter((f) => readFileSync(dir + '/' + f, 'utf8').includes(`N'${TERMINATION_AGREEMENT_FILE_CATEGORY}'`));
        expect(hits).toEqual([]);
    });

    it('the panel looks the category up BY NAME through the constant, never a literal', () => {
        expect(PANEL).toMatch(/ExtraFilter: `Name = '\$\{EscapeSQLString\(TERMINATION_AGREEMENT_FILE_CATEGORY\)\}'`/);
        expect(PANEL).not.toMatch(/Name\s*=\s*'Termination Agreement'/);
    });
});

describe('the termination-agreement controls show only where there is one to point at', () => {
    it('gates on a Terminated Date or a file already in the category', () => {
        expect(PANEL).toContain('this.Record?.TerminatedDate != null || this._files.some((f) => this.IsTerminationAgreement(f))');
        expect(PANEL).toContain('@if (ShowTermination) {');
    });

    it('marks and unmarks through the same file write as the executed agreement', () => {
        expect(PANEL).toMatch(/public async MarkTermination\([\s\S]*?setCategory\(file, this\.TerminationCategoryID,/);
        expect(PANEL).toMatch(/public async UnmarkTermination\([\s\S]*?setCategory\(file, null,/);
    });
});
