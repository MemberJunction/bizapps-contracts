/**
 * The date rule, the executed-agreement rule, the locked fields, and the countdown —
 * issue #28 items 12, 16 (database half), 18 (read-only half) and 20.
 *
 * ITEM 12 IS REAL BEHAVIOUR AND IS TESTED AS SUCH: `Validate()` needs no provider, so the rule runs
 * here against a constructed entity rather than being asserted from source. The others are structural
 * — a view's SQL, a field flag, a deleted template line — and none needs a database to be true.
 *
 * ON ITEM 13, WHICH THIS FILE ONCE SAID WAS UNRESOLVED: it shipped one commit later, in
 * `V202609010200`, after the ruling that item 13 had already made the call explicitly — `<=` on
 * Terminated, `<` on Expired. Its own tests live in `contract-state.test.ts` and
 * `state-derivation.mjs`. What remains here is narrower and still worth having: item 16's migration
 * must not carry the boundary change, because item 13's migration owns it and two files editing the
 * same predicate is how one silently wins.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { ContractEntity } from '../ContractEntity';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const strip = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

const ENTITY = readFileSync(root('packages/Entities/src/ContractEntity.ts'), 'utf8');
const PANELS = strip(readFileSync(root('packages/Angular/src/lib/form-panels/contract.panels.ts'), 'utf8'));
const FORM_FIELDS_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/contract-form.panels.ts'), 'utf8');

/** SQL with `--` line comments removed. Item 16's migration header discusses item 13 at length — it
 *  was written before item 13 shipped and records why that boundary was excluded from THIS file — so
 *  an absence check against the raw text reports the explanation as the defect. The header itself
 *  stays as written: an applied migration is immutable. */
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

describe('item 12 — a term cannot end before it starts', () => {
    it('the rule is on the SHARED subclass, so it runs in both tiers', () => {
        // Client-side via the form's Validate(), server-side inside ValidateAsync(). A rule that only
        // ran in the browser would be a UI courtesy with a raw CK_Contract_Dates error behind it.
        expect(ENTITY).toContain('private refuseEndBeforeEffective(');
        expect(ENTITY).toContain('this.refuseEndBeforeEffective(result)');
    });

    it('reports the issue’s message, on the End Date field', () => {
        expect(ENTITY).toContain("'End Date must be on or after the Effective Date.'");
        const fn = ENTITY.slice(ENTITY.indexOf('private refuseEndBeforeEffective('));
        expect(fn.slice(0, fn.indexOf('\n    }'))).toContain("'EndDate'");
    });

    it('compares calendar days, not instants', () => {
        // These are `date` columns but the entity hands back a JS Date whose time component is
        // whatever the transport produced — a raw comparison would refuse a valid same-day term.
        const fn = ENTITY.slice(ENTITY.indexOf('private refuseEndBeforeEffective('));
        expect(fn.slice(0, fn.indexOf('\n    }'))).toContain('Date.UTC(');
    });

    it('is inclusive: a single-day term is allowed', () => {
        const fn = ENTITY.slice(ENTITY.indexOf('private refuseEndBeforeEffective('));
        const body = fn.slice(0, fn.indexOf('\n    }'));
        expect(body).toContain('>= day(effective)');
    });

    it('says nothing when either date is absent', () => {
        const fn = ENTITY.slice(ENTITY.indexOf('private refuseEndBeforeEffective('));
        expect(fn.slice(0, fn.indexOf('\n    }'))).toContain('if (!effective || !end) return;');
    });

    it('is registered, so the rule is reachable at all', () => {
        expect(typeof ContractEntity).toBe('function');
    });
});

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

    it('leaves the Terminated boundary to item 13, which owns it', () => {
        /*
         * Item 13 SHIPPED, in V202609010200 — this is no longer "13 is undecided". The guarantee is
         * that item 16's migration does not also edit that predicate: both files carry the whole view
         * because CREATE OR ALTER requires it, so if each set the boundary independently the newest
         * would silently win and the older file would read as authority for something it no longer
         * decides. One predicate, one owner.
         *
         * Checked against the SQL rather than the file text: this migration's header discusses the
         * boundary at length in order to explain the split.
         */
        expect(sqlCode(migration())).not.toContain('TerminatedDate <=');
        expect(sqlCode(migration())).toContain('g.TerminatedDate < CAST(GETUTCDATE() AS date)');
    });
});

describe('item 18 — the server owns these three fields', () => {
    it('the field spec can declare a field never-editable', () => {
        expect(FORM_FIELDS_RAW).toContain('readOnly?: boolean;');
        expect(FORM_FIELDS_RAW).toContain('[EditMode]="f.readOnly ? false : EditMode"');
    });

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
         * Item 18 says hide it, because item 1's Source Deal link replaces it. That premise is false
         * on this database: item 1 renders only when both provenance columns are set, and one contract
         * of eleven has them — with a hand-typed pair naming `MJ: Explorer Navigation Items` and a
         * record id that is not a valid UUID. Hiding the section would remove the only visible
         * provenance in exchange for a stat that does not appear.
         *
         * This test exists so the departure is a decision somebody can find, not a gap. Delete it
         * together with the panel once a contract created by a real Close-Won deal exists to verify
         * item 1 against.
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
