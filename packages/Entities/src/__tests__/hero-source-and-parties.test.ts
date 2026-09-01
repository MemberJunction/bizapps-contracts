/**
 * The hero's two claims about a contract's provenance and its parties — issue #28 items 1 and 8.
 *
 * Source-level guards, cheap by construction: reads files, no database, no MJ imports. Both items
 * are checkable that way because both defects were about what the markup SAYS, and item 1's is
 * additionally about an assumption the code must not make.
 *
 * WHAT ITEM 1 IS REALLY GUARDING. `CreatingEntityID`/`CreatingRecordID` is a POLYMORPHIC pair. Today
 * `bizapps-sales` is its only writer and always stores Deals, so a "Source Deal" label and a Deals
 * lookup would both work right now and would both be wrong — the first time anything else writes the
 * pair, a hardcoded label mislabels the record and a hardcoded entity opens nothing. The tests below
 * pin the resolve-from-the-id shape, not the string "Deal".
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const PANEL = readFileSync(root('packages/Angular/src/lib/form-panels/contract.panels.ts'), 'utf8');
const KIT = readFileSync(root('packages/Angular/src/lib/styles/contracts-kit.css'), 'utf8');
const META = readFileSync(root('metadata/entity-fields/.entity-fields.json'), 'utf8');

/** The hero component's inline template. */
const HERO = (() => {
    const start = PANEL.indexOf('<div class="mjc-hero">');
    const end = PANEL.indexOf('export class MJCContractHeroPanel');
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    return PANEL.slice(start, end);
})();

describe('item 1 — the source record, as a link', () => {
    it('the "Created by" stat and its placeholders are gone', () => {
        expect(HERO).not.toContain('Created by');
        expect(HERO).not.toContain('entered directly');
        expect(PANEL).not.toContain('get CreatingEntityName()');
    });

    it('the stat is absent entirely when nothing created this contract', () => {
        expect(HERO).toContain('@if (HasSource)');
        const guard = PANEL.slice(PANEL.indexOf('public get HasSource()'));
        const body = guard.slice(0, guard.indexOf('\n    }'));
        expect(body).toContain('CreatingEntityID');
        expect(body).toContain('CreatingRecordID');
    });

    it('the label comes from the resolved entity, never a hardcoded "Deal"', () => {
        expect(HERO).toContain('{{ SourceLabel }}');
        // Every assignment to the label, so a hardcoded one cannot be added alongside the derived
        // one. Matching on assignments rather than searching the file for the word "Deal": the doc
        // comments legitimately name it while explaining why the code must not.
        const assigned = [...PANEL.matchAll(/this\.SourceLabel = ([^;]+);/g)].map((m) => m[1]);
        expect(assigned).toEqual(['`Source ${entity.BaseTableDisplayName}`']);
    });

    it('the entity is looked up by CreatingEntityID rather than assumed', () => {
        const fn = PANEL.slice(PANEL.indexOf('private sourceEntity()'));
        expect(fn.slice(0, fn.indexOf('\n    }'))).toContain('e.ID === id');
    });

    it('navigation uses the entity\'s own primary key, not an assumed "ID" column', () => {
        const fn = PANEL.slice(PANEL.indexOf('public OpenSource()'));
        const body = fn.slice(0, fn.indexOf('\n    }'));
        expect(body).toContain('entity.PrimaryKeys?.[0]?.Name');
        expect(body).toContain('CompositeKey.FromKeyValuePair');
        expect(body).toContain('OpenEntityRecord(entity.Name');
    });

    it('a slow read for a previous record cannot overwrite the current one', () => {
        const fn = PANEL.slice(PANEL.indexOf('private async loadSource('));
        expect(fn.slice(0, fn.indexOf('\n    }\n'))).toContain('if (this.sourceFor !== key) return;');
    });

    it('the kit styles the link, so the panel carries no inline colour', () => {
        expect(KIT).toContain('.mjc-link');
        expect(HERO).toContain('class="mjc-link"');
        // A <button>, so it is keyboard-reachable without a fake href.
        expect(HERO).toContain('<button type="button" class="mjc-link"');
    });
});

describe('item 8 — the two parties, in order and correctly labelled', () => {
    it('the meta row reads Company before Customer', () => {
        const company = HERO.indexOf('Company: <strong>');
        const customer = HERO.indexOf('Customer: <strong>');
        expect(company).toBeGreaterThan(-1);
        expect(customer).toBeGreaterThan(company);
    });

    it('"Selling" is gone — it named no field a user could find', () => {
        expect(HERO).not.toContain('Selling:');
    });

    it('needs NO metadata entry — CodeGen already derives the DisplayName', () => {
        /*
         * The issue asked for `EntityField.DisplayName` on `CompanyID` to be set to "Company", on the
         * apparent assumption that CodeGen would otherwise produce "Company ID". It does not: it
         * strips the trailing `ID` from a foreign-key field, which is why `CustomerOrganizationID`
         * reads "Customer Organization" with nobody having configured it. Measured on BizAppsDev —
         * the column already held "Company" and `mj sync push` reported "no changes".
         *
         * So an entry here would restate what the platform already does. It is not free: it is a line
         * in the INSTALL SEED asserting a value nothing sets differently, and it makes a branch look
         * like it carries a database change when it does not — which decides the changeset level.
         *
         * This test exists because the mistake is an easy one to make twice, straight from the issue
         * text. If CodeGen's derivation ever changes, delete the test with the fix.
         */
        const entries: Array<{ fields?: Record<string, unknown>; primaryKey?: { ID?: string } }> = JSON.parse(META);
        expect(entries.filter((e) => e.primaryKey?.ID?.endsWith('Name=CompanyID'))).toEqual([]);
    });

    it('and carries no hand-written per-PR sync migration either', () => {
        // metadata/CLAUDE.md §1b: a PR contributes declarative JSON only. The build engineer's
        // `mj sync push` turns every accumulated metadata edit into ONE consolidated metadata-sync
        // migration at release. Hand-authoring one per PR duplicates that step, replaces one
        // migration per build with many small ones, and drifts from what the real push emits.
        const migrations = readdirSync(root('migrations')).filter((f) => f.endsWith('.sql'));
        expect(migrations.filter((f) => /DisplayName|CompanyID/i.test(f))).toEqual([]);
    });
});
