/**
 * R-11 — nothing may order provisions by `Sequence` any more, because the column is gone.
 *
 * WHY THIS IS A SOURCE-SCANNING TEST RATHER THAN A LOGIC ONE. The sort key is computed in SQL — a
 * `PERSISTED` computed column over `fnProvisionSortKey` — so any TypeScript that reproduced the padding
 * would be a restatement, and a restatement of SQL is not an oracle for SQL. The ordering itself was
 * verified by running it (recorded in `testing.md`).
 *
 * What CAN regress silently, and what this catches, is a reader drifting back. `OrderBy: 'Sequence ASC'`
 * against a dropped column does not fail to compile and does not throw here — it fails at the provider,
 * as a runtime "invalid column" on one grid, which is exactly the kind of breakage that reaches a user
 * before it reaches a test. Three readers and one WRITER had to move (the collection's
 * `{"Field":"Sequence","From":1}` auto-numbering, which cannot survive at all: a computed column is
 * read-only), so "did we get all of them" is the real question.
 *
 * Cheap by construction: reads source files, no database, no MJ imports.
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const REPO = fileURLToPath(new URL('../../../../', import.meta.url));

/** Every file we own that could plausibly name a column, excluding generated output. */
function sourceFiles(dir: string, out: string[] = []): string[] {
    for (const entry of readdirSync(dir)) {
        if (entry === 'node_modules' || entry === 'dist' || entry === 'generated' || entry === '.git') continue;
        const full = `${dir}/${entry}`;
        if (statSync(full).isDirectory()) sourceFiles(full, out);
        else if (/\.(ts|json)$/.test(entry) && !entry.endsWith('.test.ts')) out.push(full);
    }
    return out;
}

const FILES = [
    ...sourceFiles(`${REPO}packages/Angular/src`),
    ...sourceFiles(`${REPO}metadata`),
];

it('there are files to scan at all', () => {
    // Guards against the whole suite passing vacuously if a path moves.
    expect(FILES.length).toBeGreaterThan(20);
});

describe('no reader orders provisions by the dropped Sequence column', () => {
    it('no OrderBy names Sequence', () => {
        const offenders = FILES.filter((f) => /OrderBy['"]?\s*[:=]\s*['"][^'"]*\bSequence\b/.test(readFileSync(f, 'utf8')))
            .map((f) => f.replace(REPO, ''));
        expect(offenders, `these still order by Sequence:\n${offenders.join('\n')}`).toEqual([]);
    });

    it('the provisions collection declares no Sequence auto-numbering', () => {
        // A computed column cannot be written. If this block came back, every save of a template's
        // provisions would try to set a read-only column.
        const decl = JSON.parse(readFileSync(`${REPO}metadata/entity-relationships/provisions-collection.json`, 'utf8'));
        expect(decl.Sequence).toBeUndefined();
        expect(decl.OrderBy).toBe('ProvisionSortKey ASC');
    });

    it('the provision seed carries no Sequence values', () => {
        const seed = JSON.parse(readFileSync(`${REPO}metadata/contract-provisions/.contract-provisions.json`, 'utf8'));
        const withSequence = seed.filter((r: { fields?: Record<string, unknown> }) => r.fields && 'Sequence' in r.fields);
        expect(withSequence).toHaveLength(0);
    });
});

describe('the migration that defines the key still says what it must', () => {
    // Folded into the baseline by the 2026-08-23 flatten (was
    // V202608200400__v0.1.x__Provision_sort_key.sql). Assertions unchanged on purpose: they
    // are what proves the function and the PERSISTED computed column survived the fold.
    const migration = readFileSync(
        `${REPO}migrations/B202608040001__v0.1.x__Baseline.sql`,
        'utf8',
    );

    it('the computed column is PERSISTED — without it there is no index', () => {
        // Matches the inline CREATE TABLE form as well as the ALTER ... ADD form the column
        // arrived in originally. What has to hold is that it is a PERSISTED computed column;
        // which DDL verb declares it is not the guarantee.
        expect(migration).toMatch(/\[?ProvisionSortKey\]?\s+AS\s+\(.*?\)\s+PERSISTED/s);
    });

    it('the function is WITH SCHEMABINDING — without it SQL Server refuses to persist it', () => {
        expect(migration).toContain('WITH SCHEMABINDING');
    });

    it('digit runs are padded and never truncated', () => {
        // RIGHT(pad + digits, 6) alone would drop the LEADING digit of a 7-digit run, sorting it wildly
        // wrong rather than merely imprecisely. The CASE is what prevents that.
        expect(migration).toMatch(/CASE WHEN LEN\(@digits\) > 6 THEN LEN\(@digits\) ELSE 6 END/);
    });

    it('the retired Sequence column is not declared at all', () => {
        // This replaced an assertion that the migration dropped Sequence's auto-named DEFAULT
        // constraint via a sys.default_constraints lookup rather than by literal name. That was
        // the right check while Sequence existed and had to be removed: auto-generated names
        // embed an object id, so they differ per database and a hardcoded one fails everywhere
        // but the instance it was copied from. The 2026-08-23 flatten removed the column from
        // the schema entirely, so there is no constraint to drop and no name to get wrong.
        // What still needs guarding is the outcome: a hand-maintained order column must not
        // come back — it had already collided in the seeded data, which is why it went.
        expect(migration).not.toMatch(/^\s*Sequence\s+INT/mi);
        expect(migration).not.toMatch(/ADD\s+\[?Sequence\]?\s+INT/i);
    });
});
