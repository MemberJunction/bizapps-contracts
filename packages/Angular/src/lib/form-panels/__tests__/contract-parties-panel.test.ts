/**
 * The Parties panel's two party lookups use common's fast picker (golive #372): the stock
 * `mj-form-field` lists rows on focus and scans a view with `LIKE '%q%'`, which takes seconds on a
 * party file of a million people. Which fields get the picker is decided by `kind` on the field spec.
 *
 * Checked as source, like `contract-dates-panel.test.ts`: the panel is an `@Component` and cannot be
 * constructed outside an Angular host. `ngc` proves the template binds; this proves the wiring.
 */
import { describe, expect, it } from 'vitest';

describe('MJCContractPartiesPanel', () => {
    it('marks exactly the customer (Organization) and primary contact (Person) as party pickers', async () => {
        const panel = await readPartiesPanel();
        expect(panel).toContain("{ name: 'CustomerOrganizationID', type: 'textbox', link: 'Record', kind: 'Organization' }");
        expect(panel).toContain("{ name: 'PrimaryContactPersonID', type: 'textbox', link: 'Record', kind: 'Person' }");
        expect(panel).toContain("{ name: 'CompanyID', type: 'textbox', link: 'Record' }");
        expect(panel.match(/kind: '/g) ?? []).toHaveLength(2);
    });

    it('renders bizapps-party-field for a kind and keeps navigation wired', async () => {
        const panel = await readPartiesPanel();
        expect(panel).toContain('@if (f.kind)');
        expect(panel).toContain('<bizapps-party-field');
        expect(panel).toContain('[Kind]="f.kind"');
        expect(panel.match(/\(Navigate\)="FormComponent\.OnFormNavigate\(\$event\)"/g) ?? []).toHaveLength(2);
    });
});

/** From the panel's selector to its class's closing brace (column-one `}`). */
async function readPartiesPanel(): Promise<string> {
    const { readFile } = await import('node:fs/promises');
    const source = await readFile(new URL('../contract-form.panels.ts', import.meta.url), 'utf8');
    const start = source.indexOf("selector: 'mjc-contract-parties-panel'");
    expect(start).toBeGreaterThan(-1);
    const close = source.indexOf('\n}\n', source.indexOf('export class MJCContractPartiesPanel', start));
    expect(close).toBeGreaterThan(start);
    return source.slice(start, close + 2);
}
