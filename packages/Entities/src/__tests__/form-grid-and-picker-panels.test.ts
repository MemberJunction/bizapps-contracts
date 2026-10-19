/**
 * Two panel fixes asserted against the source, since rendering a panel needs Angular and a form host.
 *
 *   · #136 — the Organization form's Agreements grid carries the FK-click workaround (W-1) and
 *     navigates through its host form.
 *   · #148 — the Source deal picker re-syncs from the record on each entry into edit mode, so a
 *     cancelled pick and a released lock do not survive Cancel.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const read = (p: string) => readFileSync(fileURLToPath(new URL('../../../Angular/src/lib/' + p, import.meta.url)), 'utf8');

describe('#136 — Organization Agreements grid FK links', () => {
    const ORG = read('form-panels/organization.panels.ts');
    const DIRECTIVE = read('directives/fk-navigate.directive.ts');

    it('imports the directive and applies it to the grid', () => {
        expect(ORG).toContain("import { MJCFkNavigateDirective } from '../directives/fk-navigate.directive';");
        expect(ORG).toMatch(/imports: \[[^\]]*MJCFkNavigateDirective/);
        expect(ORG).toContain('<mj-explorer-entity-data-grid mjcFkNavigate');
    });
    it('routes the FK navigation through the host form, as panels do', () => {
        expect(ORG).toContain('(FkNavigate)="FormComponent.OnFormNavigate($event)"');
        expect(DIRECTIVE).toContain('if (this.FkNavigate.observed)');
        expect(DIRECTIVE).toContain("Kind: 'record'");
    });
});

describe('#148 — Source deal picker after Cancel', () => {
    const SRC = read('form-panels/contract-form.panels.ts');
    const panel = SRC.slice(SRC.indexOf('export class MJCContractProvenanceFieldsPanel'));

    it('the template is gated on LookupShown, which is read outside edit mode too', () => {
        expect(SRC).toContain('@if (LookupShown) {');
        expect(SRC).not.toContain('@if (EditMode && ShowLookup)');
    });
    it('leaving edit mode clears the sync flag, and the next lookup re-syncs from the record', () => {
        expect(panel).toMatch(/get LookupShown\(\): boolean \{\s*if \(!this\.EditMode\) \{\s*this\.syncedThisEdit = false;/);
        expect(panel).toContain('if (this.loadedFor !== key || !this.syncedThisEdit) {');
        expect(panel).toMatch(/this\.syncedThisEdit = true;\s*this\.syncFromRecord\(\);/);
    });
});
