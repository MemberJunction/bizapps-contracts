import { afterEach, describe, expect, it } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { newestViewDefiner } from './helpers/view-definer.js';

/**
 * THE "REDEFINED LATER" GUARD FIRES ON REDEFINITION, NOT ON USE.
 *
 * A CodeGen capture that regenerates an entity built on a view reads that view in its procedures
 * (`SELECT ... FROM`, `GRANT SELECT ON`). That is correct history and must resolve. A later migration
 * that redefines the view in a form `newestViewDefiner` cannot match must still fail loudly.
 */

const DEFINE = 'CREATE VIEW [${flyway:defaultSchema}].[vwThings] AS SELECT 1 AS A\nGO\n';
let dir: string | null = null;

function migrations(files: Record<string, string>): string {
    dir = mkdtempSync(join(tmpdir(), 'view-definer-'));
    for (const [name, sql] of Object.entries(files)) writeFileSync(join(dir, name), sql);
    return dir;
}

afterEach(() => {
    if (dir) rmSync(dir, { recursive: true, force: true });
    dir = null;
});

describe('newestViewDefiner', () => {
    it('resolves past a later migration that only reads the view', () => {
        const d = migrations({
            'V1__define.sql': DEFINE,
            'V2__capture.sql':
                'CREATE PROCEDURE [s].[spGet] AS SELECT * FROM [${flyway:defaultSchema}].[vwThings]\nGO\n' +
                'GRANT SELECT ON [${flyway:defaultSchema}].[vwThings] TO [cdp_UI]\nGO\n',
        });
        expect(newestViewDefiner(d, 'vwThings').file).toBe('V1__define.sql');
    });

    it('fails on a later unbracketed redefinition', () => {
        const d = migrations({
            'V1__define.sql': DEFINE,
            'V2__redefine.sql': 'CREATE OR ALTER VIEW s.vwThings AS SELECT 2 AS A\nGO\n',
        });
        expect(() => newestViewDefiner(d, 'vwThings')).toThrow(/AFTER its newest recognised definer/);
    });

    it('fails on a later DROP that names the view second in its list', () => {
        const d = migrations({
            'V1__define.sql': DEFINE,
            'V2__drop.sql': 'DROP VIEW [s].[vwOther], [s].[vwThings]\nGO\n',
        });
        expect(() => newestViewDefiner(d, 'vwThings')).toThrow(/AFTER its newest recognised definer/);
    });

    it('ignores a later batch that defines a different view', () => {
        const d = migrations({
            'V1__define.sql': DEFINE,
            'V2__other.sql': 'CREATE VIEW s.vwOther AS SELECT * FROM [s].[vwThings]\nGO\n',
        });
        expect(newestViewDefiner(d, 'vwThings').file).toBe('V1__define.sql');
    });
});
