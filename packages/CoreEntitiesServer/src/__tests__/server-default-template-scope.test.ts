/**
 * The server's default template is scoped by the contract type's `ContractTemplateTypeID` (#114).
 *
 * `ResolveServerDefaultTemplate` (see `server-default-template.test.ts`) decides WHETHER to default;
 * this file pins WHICH template the server looks for: `typeRule()` must read `ContractTemplateTypeID`
 * and `currentTemplateID()` must receive it, or an Order Form defaults to whatever template is newest
 * across every template type.
 *
 * Called through the real prototype on a minimal stub, like `seed-renewal-defaults-entity.test.ts`,
 * so the two private methods under test are the shipped ones and no database is needed.
 */
import { describe, expect, it } from 'vitest';
import { ContractEntityServer } from '../ContractEntityServer.js';

const CONTRACT_TYPE_ID = '33333333-0000-4000-8000-000000001001';
const MASTER_AGREEMENT_TYPE_ID = '33333333-0000-4000-8000-000000002001';
const TEMPLATE_ID = '44444444-0000-4000-8000-000000000001';

type Params = { EntityName: string; ExtraFilter: string; Fields?: string[] };

function stub(templateTypeID: string | null) {
    const calls: Params[] = [];
    const self = Object.create(ContractEntityServer.prototype) as Record<string, unknown>;
    const members: Record<string, unknown> = {
        ContractTypeID: CONTRACT_TYPE_ID,
        ContextCurrentUser: undefined,
        cachedTypeRule: undefined,
        RunViewProviderToUse: {
            RunView: async (params: Params) => {
                calls.push(params);
                if (params.EntityName === 'MJ_BizApps_Contracts: Contract Types') {
                    // Return only what was asked for, as SQL would.
                    const row: Record<string, unknown> = {
                        Name: 'Order Form',
                        TemplateRequired: true,
                        ContractTemplateTypeID: templateTypeID,
                        Status: 'Active',
                    };
                    const projected = Object.fromEntries((params.Fields ?? Object.keys(row)).map((f) => [f, row[f]]));
                    return { Success: true, Results: [projected] };
                }
                return { Success: true, Results: [{ ID: TEMPLATE_ID }] };
            },
        },
    };
    for (const [key, value] of Object.entries(members)) {
        Object.defineProperty(self, key, { value, writable: true, enumerable: true, configurable: true });
    }
    const typeDefault = () => (self as unknown as { typeDefaultTemplateID(): Promise<string | null> }).typeDefaultTemplateID();
    return { calls, typeDefault };
}

describe('server default template scope (#114)', () => {
    it('restricts the template read to the type\'s ContractTemplateTypeID', async () => {
        const { calls, typeDefault } = stub(MASTER_AGREEMENT_TYPE_ID);
        await expect(typeDefault()).resolves.toBe(TEMPLATE_ID);

        const templateRead = calls.find((c) => c.EntityName === 'MJ_BizApps_Contracts: Contract Templates');
        expect(templateRead?.ExtraFilter).toContain(`ContractTemplateTypeID = '${MASTER_AGREEMENT_TYPE_ID}'`);
    });

    it('falls back to any published, usable template when the type names no template type', async () => {
        const { calls, typeDefault } = stub(null);
        await typeDefault();

        const templateRead = calls.find((c) => c.EntityName === 'MJ_BizApps_Contracts: Contract Templates');
        expect(templateRead?.ExtraFilter).toBe(`Status = 'Published' AND IsUsable = 1`);
    });
});
