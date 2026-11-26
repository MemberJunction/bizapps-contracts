/**
 * Verifies that `ContractEntityServer` deduplicates repeated reads of the same referenced row
 * during one validation pass:
 *   - `refuseCrossLevelSupersession` + `refuseCrossCustomerSupersession` share ONE `RunView`
 *     for `SupersededByContractID` (instead of two sequential reads of the same contract).
 *   - `refuseUnusableTemplate` + `retiredTemplateType` share ONE `RunView` for
 *     `ContractTemplateID` (instead of two sequential reads of the same template).
 */
import { describe, expect, it, vi } from 'vitest';
import { ValidationResult } from '@memberjunction/core';
import { ContractEntityServer } from '../ContractEntityServer.js';

const SELF_ID = '11111111-0000-4000-8000-000000000001';
const TARGET_ID = '11111111-0000-4000-8000-000000000002';
const CUST_A = '22222222-0000-4000-8000-000000000001';
const CUST_B = '22222222-0000-4000-8000-000000000002';
const PARENT_X = '33333333-0000-4000-8000-000000000001';
const TMPL_ID = '44444444-0000-4000-8000-000000000001';
const TMPL_TYPE_ID = '55555555-0000-4000-8000-000000000001';

function createStub(overrides: Record<string, unknown>, runView: ReturnType<typeof vi.fn>) {
    const self = Object.create(ContractEntityServer.prototype) as Record<string, unknown>;
    const members: Record<string, unknown> = {
        ID: SELF_ID,
        ContractNumber: 'CTR-000001',
        IsSaved: false,
        ParentContractID: null,
        CustomerOrganizationID: CUST_A,
        SupersededByContractID: null,
        ContractTemplateID: null,
        ContextCurrentUser: undefined,
        cachedSupersededTarget: undefined,
        cachedSelectedTemplate: undefined,
        RunViewProviderToUse: { RunView: runView },
        ProviderToUse: { RunView: runView },
        ...overrides,
    };
    for (const [k, v] of Object.entries(members)) {
        Object.defineProperty(self, k, { value: v, writable: true, enumerable: true, configurable: true });
    }
    return self as unknown as {
        refuseCrossLevelSupersession(r: ValidationResult): Promise<void>;
        refuseCrossCustomerSupersession(r: ValidationResult): Promise<void>;
        refuseUnusableTemplate(r: ValidationResult): Promise<void>;
        retiredTemplateType(): Promise<string | null>;
    };
}

describe('ContractEntityServer validation query deduplication', () => {
    it('reads SupersededByContractID once across cross-level and cross-customer checks', async () => {
        const runView = vi.fn(async () => ({
            Success: true,
            Results: [
                {
                    ContractNumber: 'CTR-000002',
                    ParentContractID: PARENT_X,
                    CustomerOrganizationID: CUST_B,
                },
            ],
        }));
        const entity = createStub({ SupersededByContractID: TARGET_ID }, runView);
        const result = new ValidationResult();

        await entity.refuseCrossLevelSupersession(result);
        await entity.refuseCrossCustomerSupersession(result);

        expect(runView).toHaveBeenCalledTimes(1);
        expect(result.Success).toBe(false);
        expect(result.Errors).toHaveLength(2);
    });

    it('reads ContractTemplateID once across refuseUnusableTemplate and retiredTemplateType', async () => {
        const runView = vi.fn(async (params: { EntityName: string }) => {
            if (params.EntityName === 'MJ_BizApps_Contracts: Contract Templates') {
                return {
                    Success: true,
                    Results: [
                        {
                            Name: 'Legacy MSA',
                            IsUsable: false,
                            Status: 'Draft',
                            ContractTemplateTypeID: TMPL_TYPE_ID,
                        },
                    ],
                };
            }
            return {
                Success: true,
                Results: [{ Name: 'Old Template Type', Status: 'Inactive' }],
            };
        });
        const entity = createStub({ ContractTemplateID: TMPL_ID }, runView);
        const result = new ValidationResult();

        await entity.refuseUnusableTemplate(result);
        const retiredName = await entity.retiredTemplateType();

        const templateCalls = runView.mock.calls.filter(
            (c) => (c[0] as { EntityName: string }).EntityName === 'MJ_BizApps_Contracts: Contract Templates',
        );
        expect(templateCalls).toHaveLength(1);
        expect(retiredName).toBe('Old Template Type');
        expect(result.Success).toBe(false);
        expect(result.Errors).toHaveLength(2);
    });
});
