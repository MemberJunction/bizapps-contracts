/**
 * Golive #213 item 1 — a linked file can be MARKED as the executed agreement, so "Awaiting document"
 * can actually clear.
 *
 * Contracts #36 (golive #203 item 16) made `vwContracts.IsAwaitingDocument` depend on a linked file
 * carrying the file category named 'Executed Agreement', and MJ's stock Attachments panel at
 * 6.1.0-edge.4 has no way to set a category. The fix is a contracts panel that sets `File.CategoryID`
 * to that row. What is worth pinning is structural and lives in three places that must agree:
 *
 *   · the migration SEEDS the row by name,
 *   · the view MATCHES it by name,
 *   · the panel LOOKS IT UP by name — through the one constant in this package.
 *
 * ASSERTED AGAINST THE SOURCE, like `supersede-panel-outlives-its-record.test.ts`: rendering the panel
 * needs Angular, a form host and a provider; what is being pinned is a spelling, a predicate and a
 * call, each readable without any of that.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { EXECUTED_AGREEMENT_FILE_CATEGORY } from '../executed-agreement.js';
import { newestViewDefiner } from './helpers/view-definer.js';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const strip = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

const PANEL = strip(readFileSync(root('packages/Angular/src/lib/form-panels/executed-agreement.panel.ts'), 'utf8'));
const PUBLIC_API = readFileSync(root('packages/Angular/src/public-api.ts'), 'utf8');
const ENTITY_NAMES = readFileSync(root('packages/Angular/src/lib/data/entity-names.ts'), 'utf8');

/**
 * The two subjects, resolved separately, because they are two different files and stopped being the
 * same one on 2026-09-20.
 *
 * The SEED is identified by the category INSERT — the one thing only item 16's migration contains
 * (see the flake note in dates-executed-doc-and-readonly.test.ts for why the match is on the INSERT
 * and not on the view predicate, which a later view rewrite would also carry).
 *
 * The VIEW is whatever migration defines `vwContracts` LAST, through the shared resolver. It has to
 * be resolved rather than pinned for the reason this whole helper exists: `V202609202354` re-created
 * the view without the category gate and `V202609211200` re-created it again, so "the migration that
 * seeds the row" has not been the migration that matches on it for some time.
 */
const MIGRATION_MARKER = 'INSERT INTO [${mjSchema}].[FileCategory]';
const VIEW = newestViewDefiner(fileURLToPath(new URL('../../../../migrations/', import.meta.url)), 'vwContracts');
const migration = (): string => {
    const dir = root('migrations');
    const found = readdirSync(dir)
        .filter((f) => f.endsWith('.sql'))
        .filter((f) => readFileSync(dir + '/' + f, 'utf8').includes(MIGRATION_MARKER));
    expect(found, 'exactly one migration seeds the FileCategory row').toHaveLength(1);
    return readFileSync(dir + '/' + found[0], 'utf8');
};

describe('one spelling of the category name', () => {
    it('the constant equals the name the migration seeds', () => {
        const m = /\[FileCategory\] \(\[ID\], \[Name\], \[Description\]\)\s*VALUES \(NEWID\(\), N'([^']+)'/.exec(migration());
        expect(m, 'the seed INSERT names the category').toBeTruthy();
        expect(m![1]).toBe(EXECUTED_AGREEMENT_FILE_CATEGORY);
    });

    it('and the name the view resolves on', () => {
        // THE NEWEST DEFINER, not the seeding migration. Pinned to the seed this read V202609010100
        // for ever and stayed green through V202609202354 dropping the predicate altogether — the
        // same trap `dates-executed-doc-and-readonly.test.ts` was in, and the third copy of it.
        expect(VIEW.flat).toContain(`fc.Name = '${EXECUTED_AGREEMENT_FILE_CATEGORY}'`);
    });

    it('the panel looks the category up BY NAME through the constant, never a literal or an id', () => {
        expect(PANEL).toContain('EXECUTED_AGREEMENT_FILE_CATEGORY');
        expect(PANEL).toContain('MJC_FOREIGN_ENTITIES.FileCategory');
        expect(PANEL).toMatch(/ExtraFilter: `Name = '\$\{EscapeSQLString\(EXECUTED_AGREEMENT_FILE_CATEGORY\)\}'`/);
        expect(PANEL).not.toMatch(/Name\s*=\s*'Executed Agreement'/);
    });

    it('the entity names it reads are the tables the view joins', () => {
        // The view: __mj.FileEntityRecordLink → __mj.File → __mj.FileCategory. Same three, by MJ name.
        expect(ENTITY_NAMES).toContain("File: 'MJ: Files'");
        expect(ENTITY_NAMES).toContain("FileCategory: 'MJ: File Categories'");
        expect(ENTITY_NAMES).toContain("FileEntityRecordLink: 'MJ: File Entity Record Links'");
    });
});

describe('the write goes to the FILE, and the RECORD is re-read afterwards', () => {
    it('sets CategoryID on the loaded MJ: Files entity and saves it', () => {
        const fn = PANEL.slice(PANEL.indexOf('private async setCategory('));
        const body = fn.slice(0, fn.indexOf('\n    }'));
        expect(body).toContain('file.Entity.CategoryID = categoryID;');
        expect(body).toContain('await file.Entity.Save()');
        // Save() returns false rather than throwing; the reason is on LatestResult, and it is
        // CompleteMessage, not Message (data-access rule).
        expect(body).toContain('LatestResult?.CompleteMessage');
        expect(body).toContain('file.Entity.Revert()');
    });

    it('re-reads the record through the form, because the chip reads the PERSISTED view column', () => {
        expect(PANEL).toContain('this.FormComponent.RefreshRecord()');
        expect(PANEL).toContain('public override OnRecordRefreshed()');
    });

    it('unmark clears the category rather than guessing a previous one', () => {
        expect(PANEL).toMatch(/public async Unmark\([\s\S]*?setCategory\(file, null,/);
    });
});

describe('the Re-papering rule — always visible, read-only while editing or unsaved', () => {
    it('gates the buttons on EditMode and IsSaved, with the two chips in #203 item 19’s words', () => {
        expect(PANEL).toContain('return this.EditMode || !this.Record?.IsSaved;');
        expect(PANEL).toContain("'Finish editing to change'");
        expect(PANEL).toContain("'Save this contract first'");
    });

    it('hides the buttons and says why when the user cannot update MJ: Files', () => {
        expect(PANEL).toContain('GetUserPermisions(user).CanUpdate === true');
        expect(PANEL).toContain('@if (CanMark)');
    });

    it('says plainly when the category row is missing rather than failing silently', () => {
        expect(PANEL).toContain('this.CategoryMissing = !this.CategoryID;');
        expect(PANEL).toContain('@else if (CategoryMissing)');
    });
});

describe('the list can be reloaded on demand', () => {
    it('has a refresh control, because attaching through the toolbar tells this panel nothing', () => {
        // Closing the stock Attachments panel refreshes only the toolbar count, so a file attached a
        // moment ago would otherwise stay unlisted until the record was reloaded.
        expect(PANEL).toContain('<mj-refresh-button');
        expect(PANEL).toContain('(Clicked)="Refresh()"');
        expect(PANEL).toContain('public async Refresh()');
    });
});

describe('registration', () => {
    it('is keyed on the record, so the form reusing the instance cannot show another contract’s files', () => {
        expect(PANEL).toContain('private loadedFor: string | null = null;');
        expect(PANEL).toContain('this.loadedFor !== id');
    });

    it('contributionKey equals SectionKey, as the chrome requires', () => {
        expect(PANEL).toContain("contributionKey: 'executedAgreement'");
        expect(PANEL).toContain('SectionKey="executedAgreement"');
    });

    it('is anchored in the client bootstrap, so a production build cannot drop the registration', () => {
        expect(PUBLIC_API).toContain("import { MJCContractExecutedAgreementPanel } from './lib/form-panels/executed-agreement.panel';");
        expect(PUBLIC_API).toContain('void MJCContractExecutedAgreementPanel;');
    });

    it('uses static imports only', () => {
        expect(PANEL).not.toMatch(/await import\(/);
    });
});
