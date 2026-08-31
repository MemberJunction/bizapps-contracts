/**
 * What the re-papering picker OFFERS, and what the server ALLOWS — issue #28 items 2, 3 and 4.
 *
 * Source-level guards, for the same reason as `supersede-operation.test.ts`: the rules need a
 * provider and a rendered component, and neither tier exists in this package. What is checkable
 * without them is precisely what these three items changed — a query predicate, a label expression,
 * a set of CSS class names, and whether the server has a matching refusal at all.
 *
 * THE ONE WORTH STATING. Item 4's same-customer rule exists twice on purpose: once in the panel, which
 * decides what to OFFER, and once in `ContractEntityServer`, which decides what is ALLOWED. That is
 * not redundancy — the FK is writable by anything holding a `ContractEntity` (the generated form, an
 * import, another app), and a filter on a dropdown governs none of them. A future edit that "removes
 * the duplication" by deleting the server guard reopens the hole, so this pins both sides.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const SERVER = readFileSync(join(__dirname, '..', 'ContractEntityServer.ts'), 'utf-8');
const NG = join(__dirname, '..', '..', '..', 'Angular', 'src');
const PANEL = readFileSync(join(NG, 'lib', 'form-panels', 'supersede.panel.ts'), 'utf-8');
const KIT = readFileSync(join(NG, 'lib', 'styles', 'contracts-kit.css'), 'utf-8');

/**
 * The component's inline template only. Scoped deliberately: prose that was REMOVED from the UI is
 * still quoted in the doc comments explaining why it went, and a whole-file search cannot tell a
 * rendered paragraph from a note about one.
 */
const TEMPLATE = (() => {
    const start = PANEL.indexOf('template: `');
    const end = PANEL.indexOf('`,\n})', start);
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    return PANEL.slice(start, end);
})();

describe('item 2 — the empty picker explains itself, without a paragraph', () => {
    it('the two hint paragraphs are gone from the rendered panel', () => {
        expect(TEMPLATE).not.toContain('Link writes the OTHER contract');
        expect(TEMPLATE).not.toContain('Nothing eligible');
        expect(TEMPLATE).not.toContain('mjc-hint');
    });

    it('the combobox carries the explanation as its placeholder', () => {
        expect(TEMPLATE).toContain('[Placeholder]="PickerPlaceholder"');
        expect(PANEL).toContain("'No eligible contracts'");
    });

    it('an empty list is distinguished from a still-loading one', () => {
        const getter = PANEL.slice(PANEL.indexOf('public get PickerPlaceholder()'));
        expect(getter.slice(0, getter.indexOf('\n    }'))).toContain('CandidatesLoading');
    });
});

describe('item 3 — the label uses the kit, like every other panel on this form', () => {
    it('the panel is built from kit field markup', () => {
        expect(TEMPLATE).toContain('class="mjc-fields"');
        expect(TEMPLATE).toContain('class="mjc-field"');
        expect(TEMPLATE).toContain('<label>Supersedes</label>');
    });

    it("MJ's mj-forms-field markup is gone, so no second label style is in play", () => {
        expect(TEMPLATE).not.toContain('mj-forms-field-label');
        expect(TEMPLATE).not.toContain('class="mj-forms-field"');
        expect(TEMPLATE).not.toContain('mj-forms-field-control');
        expect(TEMPLATE).not.toContain('mj-forms-field-value');
    });

    it('the kit defines the button row the stacked field layout needs', () => {
        expect(KIT).toContain('.mjc-field__actions');
        expect(TEMPLATE).toContain('class="mjc-field__actions"');
    });
});

describe('item 4 — same customer, offered and enforced', () => {
    it('the picker filters on the customer', () => {
        const fn = PANEL.slice(PANEL.indexOf('private async loadCandidates()'));
        const body = fn.slice(0, fn.indexOf('\n    }\n}'));
        expect(body).toContain("CustomerOrganizationID = '${customerID}'");
        // The other three rules must survive the edit.
        expect(body).toContain('SupersededByContractID IS NULL');
        expect(body).toContain("ID <> '${me}'");
        expect(body).toMatch(/ParentContractID IS NULL/);
    });

    it('a record with no customer offers nothing rather than everything', () => {
        const fn = PANEL.slice(PANEL.indexOf('private async loadCandidates()'));
        expect(fn.slice(0, fn.indexOf('const parentID'))).toContain('if (!customerID)');
    });

    it('options read `<number> — <description>`, falling back to the type', () => {
        expect(PANEL).toContain('Fields: [\'ID\', \'ContractNumber\', \'ContractType\', \'Description\']');
        expect(PANEL).toContain('${c.ContractNumber} — ${c.Description?.trim() || c.ContractType');
    });

    it('the server refuses a cross-customer supersession too', () => {
        expect(SERVER).toContain('private async refuseCrossCustomerSupersession(');
        expect(SERVER).toContain('await this.refuseCrossCustomerSupersession(result)');
    });

    it('the server guard is gated and compares by value, like its same-level sibling', () => {
        const g = SERVER.slice(SERVER.indexOf('private async refuseCrossCustomerSupersession('));
        const body = g.slice(0, g.indexOf('\n    }'));
        // Only on a NEW selection, so re-saving a legacy row is not retro-refused.
        expect(body).toContain("isNewlySelected('SupersededByContractID')");
        // By value, never `===`: MJ#3984 means ids can differ only in casing.
        expect(body).toContain('UUIDsEqual(row.CustomerOrganizationID, this.CustomerOrganizationID)');
        expect(body).not.toMatch(/CustomerOrganizationID\s*===/);
        expect(body).toContain('ValidationErrorType.Failure');
    });

    it('the server guard runs after the same-level one, which owns the not-found message', () => {
        const level = SERVER.indexOf('await this.refuseCrossLevelSupersession(result)');
        const customer = SERVER.indexOf('await this.refuseCrossCustomerSupersession(result)');
        expect(level).toBeGreaterThan(-1);
        expect(customer).toBeGreaterThan(level);
    });
});
