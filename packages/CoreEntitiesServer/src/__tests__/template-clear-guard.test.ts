/**
 * R-4, contract side: clearing a contract's template is refused while a modification anywhere in its
 * tree would be left citing a template nothing above it references (#147).
 *
 * The tree walk itself is SQL (covered by `rule-check-sql.test.ts` for shape and by the GS12/GS13
 * integration checks against a database). This exercises what TypeScript does with its result: the
 * ID guard, reading both counts from either driver, and which message the user sees.
 */
import { describe, expect, it, vi } from 'vitest';
import type { PlatformSQL } from '@memberjunction/core';
import {
    CountModificationsAgainstTemplate,
    TemplateClearRefusalMessage,
    type TemplateClearRow,
} from '../ContractEntityServer.js';

const CONTRACT = 'A1B2C3D4-0000-4000-8000-000000000001';
const TEMPLATE = 'A1B2C3D4-0000-4000-8000-0000000000AA';

function stub(rows: TemplateClearRow[] | undefined) {
    return vi.fn(async (_sql: PlatformSQL) => rows);
}

describe('CountModificationsAgainstTemplate', () => {
    it('reads both counts from SQL Server numbers', async () => {
        const run = stub([{ Hits: 2, ChildHits: 0 }]);
        expect(await CountModificationsAgainstTemplate(CONTRACT, TEMPLATE, run)).toEqual({ Hits: 2, ChildHits: 0 });
        expect(run).toHaveBeenCalledOnce();
    });

    it('reads both counts from PostgreSQL bigint strings', async () => {
        const run = stub([{ Hits: '0', ChildHits: '3' }]);
        expect(await CountModificationsAgainstTemplate(CONTRACT, TEMPLATE, run)).toEqual({ Hits: 0, ChildHits: 3 });
    });

    it('treats no row as nothing orphaned', async () => {
        expect(await CountModificationsAgainstTemplate(CONTRACT, TEMPLATE, stub(undefined))).toEqual({ Hits: 0, ChildHits: 0 });
        expect(await CountModificationsAgainstTemplate(CONTRACT, TEMPLATE, stub([]))).toEqual({ Hits: 0, ChildHits: 0 });
    });

    it('passes the tree-wide query for the given IDs', async () => {
        const run = stub([{ Hits: 0, ChildHits: 0 }]);
        await CountModificationsAgainstTemplate(CONTRACT, TEMPLATE, run);
        const sql = run.mock.calls[0]?.[0];
        expect(sql?.default).toContain(`'${CONTRACT}'`);
        expect(sql?.default).toContain(`'${TEMPLATE}'`);
        expect(sql?.default).toContain('ChildHits');
    });

    it('refuses to interpolate anything that is not a UUID, and runs nothing', async () => {
        const run = stub([{ Hits: 0, ChildHits: 0 }]);
        await expect(CountModificationsAgainstTemplate("x'; DROP TABLE y; --", TEMPLATE, run)).rejects.toThrow(/not a UUID/);
        await expect(CountModificationsAgainstTemplate(CONTRACT, 'nope', run)).rejects.toThrow(/not a UUID/);
        expect(run).not.toHaveBeenCalled();
    });
});

describe('TemplateClearRefusalMessage', () => {
    it('own modifications only: refuses with the original wording', () => {
        const msg = TemplateClearRefusalMessage({ Hits: 2, ChildHits: 0 });
        expect(msg).toContain('This contract records 2 modification(s) to provisions of the agreement version');
        expect(msg).not.toContain('child contracts');
    });

    it('child modifications only: refuses and says to look in the child contracts', () => {
        const msg = TemplateClearRefusalMessage({ Hits: 0, ChildHits: 3 });
        expect(msg).toContain("This contract's child contracts record 3 modification(s)");
        expect(msg).toContain('open the child contracts');
    });

    it('both: names each count separately', () => {
        const msg = TemplateClearRefusalMessage({ Hits: 1, ChildHits: 4 });
        expect(msg).toContain('This contract records 1 modification(s), and its child contracts record 4 modification(s)');
    });

    it('nothing orphaned (including a child that references the same template itself): allows the clear', () => {
        expect(TemplateClearRefusalMessage({ Hits: 0, ChildHits: 0 })).toBeNull();
    });
});
