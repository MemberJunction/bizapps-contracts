/**
 * The executed-agreement rule, the locked fields, and the countdown —
 * issue #28 items 16 (database half), 18 (read-only half) and 20.
 *
 * These are structural — a view's SQL, a field flag, a deleted template line — and none needs a
 * database to be true.
 *
 * ITEM 12 IS NOT HERE, and neither is item 13. Both shipped separately on `next`: the date-order
 * rule in `ContractEntity.IsEndBeforeEffective`, covered by `contract-date-order.test.ts`, and the
 * inclusive Terminated boundary in `V202608300100`, covered by `contract-state.test.ts` and
 * `state-derivation.mjs`. An earlier draft of this file asserted its own competing implementation of
 * item 12 against the source text, which is exactly the sort of assertion that fails the moment the
 * behaviour is delivered by a different, equally correct implementation.
 *
 * WHAT IS STILL WORTH HAVING HERE about item 13 is narrower: item 16's migration re-creates the whole
 * view, so it must carry item 13's boundary forward rather than reverting it. Two files editing the
 * same predicate is how one silently wins, and the later migration is the one that does.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const strip = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

const PANELS = strip(readFileSync(root('packages/Angular/src/lib/form-panels/contract.panels.ts'), 'utf8'));
const FORM_FIELDS_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/contract-form.panels.ts'), 'utf8');

/** SQL with `--` line comments removed. Item 16's migration header discusses both date boundaries at
 *  length, in order to explain why a file about executed documents sets the Terminated predicate at
 *  all — so an absence check against the raw text reports the explanation as the defect. */
const sqlCode = (t: string) => t.replace(/^\s*--.*$/gm, '');

/**
 * The item-16 migration, identified by the one thing only IT contains.
 *
 * ⚠ THIS USED TO FLAKE, and the failure mode is worth stating because the obvious fix does not fix
 * it. The helper matched `fc.Name = 'Executed Agreement'` and returned the FIRST hit from an
 * unsorted `readdirSync` — but item 13's migration carries the whole view, category gate included,
 * so BOTH files match. Directory order is not guaranteed (a plain `grep -l` on this repo already
 * lists them 0200-first), so on CI the helper could read item 13's file and fail the two
 * Terminated-boundary assertions below. Caught in review of PR #36.
 *
 * SORTING WOULD NOT HAVE FIXED IT EITHER, only hidden it: `.sort().pop()` would silently re-target
 * the moment a third migration touched the view, which is exactly what happened to
 * `contract-state.test.ts`. So the match is on the category SEED — the `INSERT INTO … FileCategory`
 * that creates the row — which item 16 owns and item 13's view rewrite does not carry. Exactly one
 * file can match, and the count is asserted rather than assumed.
 */
const MIGRATION_MARKER = 'INSERT INTO [${mjSchema}].[FileCategory]';
const migrationFiles = (): string[] => {
    const dir = root('migrations');
    return readdirSync(dir)
        .filter((x) => x.endsWith('.sql'))
        .filter((f) => readFileSync(dir + '/' + f, 'utf8').includes(MIGRATION_MARKER));
};
const migration = (): string => {
    const dir = root('migrations');
    const found = migrationFiles();
    return found.length === 1 ? readFileSync(dir + '/' + found[0], 'utf8') : '';
};

describe('item 16 — only the executed agreement clears the flag', () => {
    it('exactly one migration seeds the category, so the target is unambiguous', () => {
        // If this fails the helper above picked nothing or picked between two, and every assertion
        // in this block is then reading a file nobody chose. Fail here, loudly, rather than there.
        expect(migrationFiles()).toHaveLength(1);
        expect(migrationFiles()[0]).toContain('IsAwaitingDocument_executed_agreement');
    });

    it('the view requires the file to carry the category', () => {
        const m = migration();
        expect(m).not.toBe('');
        expect(m).toContain('[FileCategory]');
        expect(m).toContain("fc.Name = 'Executed Agreement'");
        // The link and file must still be joined — the category alone proves nothing about THIS record.
        expect(m).toContain('[FileEntityRecordLink]');
        expect(m).toContain('f.ID = fl.FileID');
    });

    it('seeds the category idempotently, by name', () => {
        const m = migration();
        expect(m).toContain("WHERE [Name] = N'Executed Agreement'");
        expect(m).toMatch(/IF NOT EXISTS[\s\S]{0,200}INSERT INTO \[\$\{mjSchema\}\]\.\[FileCategory\]/);
    });

    it('resolves both lookups by name, never a hardcoded id', () => {
        const m = migration();
        expect(m).toContain("e.Name = 'MJ_BizApps_Contracts: Contracts'");
        // NEWID() for the seeded row is fine; a literal UUID anywhere else is not.
        expect(m.replace(/NEWID\(\)/g, '')).not.toMatch(/'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-/);
    });

    it('leaves the type gate alone — a Payment Link never awaits paper', () => {
        expect(migration()).toContain('ct.RequiresExecutedDocument = 1');
    });

    it('carries item 13\u2019s Terminated boundary forward rather than reverting it', () => {
        /*
         * THE DIRECTION OF THIS CHECK IS THE POINT, and it is the opposite of what it once was.
         *
         * Item 13 made Terminated inclusive (`<=`) in V202608300100. This migration sorts LATER and
         * re-creates the whole view, because CREATE OR ALTER offers no way to edit one branch — so
         * "leave that predicate to its owner" is not available here. Leaving it as written would
         * quietly revert item 13 on every database that applied both, in a file whose subject is
         * something else entirely. The later migration is the one that decides, so it has to decide
         * correctly.
         *
         * Expired stays `<`, which is not an inconsistency: an End Date is the last day the agreement
         * covers, a Terminated Date is the day it stops.
         *
         * Checked against the SQL rather than the file text, because the header discusses both
         * boundaries in prose in order to explain exactly this.
         */
        expect(sqlCode(migration())).toContain('g.TerminatedDate <= CAST(GETUTCDATE() AS date)');
        expect(sqlCode(migration())).not.toContain('g.TerminatedDate < CAST(GETUTCDATE() AS date)');
        expect(sqlCode(migration())).toContain('g.EndDate < CAST(GETUTCDATE() AS date)');
    });
});

describe('item 18 — these fields are never typed into', () => {
    it('the field spec can declare a field never-editable', () => {
        expect(FORM_FIELDS_RAW).toContain('readOnly?: boolean;');
        expect(FORM_FIELDS_RAW).toContain('[EditMode]="f.readOnly ? false : EditMode"');
    });

    /*
     * `ContractNumber` and `HasModifications` ARE server-owned — minted under a lock, and settled by
     * `ValidateAsync()`. `SupersededByContractID` is written only by `Contracts.Supersede`, on the
     * successor. The provenance pair is a different case since golive #219: finance may set it, but
     * never by typing into these two inputs, because the halves are under a both-or-neither constraint
     * and hand entry is what produced `CTR-000026`'s corrupt pair. The lookup above them writes both
     * at once; these stay read-only, which is what `source-deal-lookup.test.ts` pins.
     */
    it.each([
        ['ContractNumber', "{ name: 'ContractNumber', type: 'textbox', readOnly: true }"],
        ['HasModifications', "{ name: 'HasModifications', type: 'checkbox', readOnly: true }"],
        ['SupersededByContractID', "{ name: 'SupersededByContractID', type: 'textbox', link: 'Record', readOnly: true }"],
        ['CreatingEntityID', "{ name: 'CreatingEntityID', type: 'textbox', link: 'Record', readOnly: true }"],
        ['CreatingRecordID', "{ name: 'CreatingRecordID', type: 'textbox', readOnly: true }"],
    ])('%s is read-only', (_n, decl) => {
        expect(FORM_FIELDS_RAW).toContain(decl);
    });

    it('the Provenance SECTION is kept, contrary to item 18 — deliberately', () => {
        /*
         * Item 18 says hide it, because item 1's Source Deal link replaces it. The premise was false
         * when it was written — item 1 renders only when both provenance columns are set, and one
         * contract of eleven had them, from a hand-typed pair naming `MJ: Explorer Navigation Items`
         * with a record id that is not a valid UUID.
         *
         * GOLIVE #219 MAKES IT HALF TRUE and settles the section's fate the other way. Finance can now
         * link a deal from this very section, so contracts that show a Source Deal stat stop being a
         * theoretical population. But the pair is polymorphic and the stat renders only what it can
         * RESOLVE, so the ids below the lookup remain the one place a reader sees the provenance
         * verbatim — #219 item 3 asks for exactly that. The section stays for good.
         */
        expect(FORM_FIELDS_RAW).toContain("replacesSectionKey: 'provenance'");
        expect(FORM_FIELDS_RAW).toContain('MJCContractProvenanceFieldsPanel');
    });

    it('ParentContractID stays editable — item 11 is explicit about it', () => {
        // It is how a change order is attached to its parent.
        expect(FORM_FIELDS_RAW).toContain("{ name: 'ParentContractID', type: 'textbox', link: 'Record' },");
    });
});

describe('item 20 — the countdown is stated once', () => {
    it('the header keeps it and the Dates tab does not', () => {
        expect(PANELS).toContain('mjc-hero__next-val');
        // ONE binding and ONE getter to feed it. Two occurrences is the correct total: counting
        // "exactly one" would fail on the healthy state, which is how a test starts getting edited
        // to match whatever the code happens to say.
        expect(PANELS.match(/\{\{ EndsInText \}\}/g) ?? []).toHaveLength(1);
        expect(PANELS.match(/get EndsInText\(/g) ?? []).toHaveLength(1);
        expect(PANELS).not.toContain('<div class="mjc-hint">{{ EndsInText }}</div>');
    });
});
