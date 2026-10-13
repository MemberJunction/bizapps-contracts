/**
 * @fileoverview `ContractOrderEntityServer` — linking an order to a contract copies the contract's
 * renewal terms to the order's subscriptions (issue #77).
 *
 * The copy runs on the link's save as well as the contract's, because the usual order of events is
 * contract first, link second: a deal closes, the contract exists, and the order is linked after it.
 * Without this the subscriptions would wait for someone to edit the contract.
 *
 * Removing a link leaves the subscriptions' values as they are. They were the contract's terms when
 * they were copied, and nothing else knows what the subscription said before.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import { BaseEntity } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractOrderEntity } from '@mj-biz-apps/contracts-entities';
import {
    ApplyContractRenewalTerms,
    type ContractRenewalTerms,
    type RenewalTermsOutcome,
    ReportRenewalTermsOutcome,
} from './renewal-terms.js';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Orders')
export class ContractOrderEntityServer extends mjBizAppsContractsContractOrderEntity {
    /** What the last save's copy did, for a caller that wants to report it. Null when no copy ran. */
    public LastRenewalTermsOutcome: RenewalTermsOutcome | null = null;

    public override async Save(): Promise<boolean> {
        const linkChanged = !this.IsSaved || !!this.GetFieldByName('OrderID')?.Dirty || !!this.GetFieldByName('ContractID')?.Dirty;
        if (!(await super.Save())) return false;

        this.LastRenewalTermsOutcome = null;
        if (linkChanged) {
            const terms = await this.contractTerms();
            if (terms) {
                this.LastRenewalTermsOutcome = await ApplyContractRenewalTerms(this.RunViewProviderToUse, terms, this.ContextCurrentUser);
                ReportRenewalTermsOutcome(terms, this.LastRenewalTermsOutcome);
            }
        }
        return true;
    }

    private async contractTerms(): Promise<ContractRenewalTerms | null> {
        const result = await this.RunViewProviderToUse.RunView<{
            ID: string;
            ContractNumber: string | null;
            AnnualIncreasePercent: number | null;
            CarryDiscountOnRenewal: boolean;
        }>(
            {
                EntityName: E_CONTRACT,
                ExtraFilter: `ID='${this.ContractID}'`,
                Fields: ['ID', 'ContractNumber', 'AnnualIncreasePercent', 'CarryDiscountOnRenewal'],
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!result.Success) {
            throw new Error(`Could not read contract ${this.ContractID} to copy its renewal terms: ${result.ErrorMessage}`);
        }
        const row = result.Results[0];
        if (!row) return null;
        return {
            ContractID: row.ID,
            ContractNumber: row.ContractNumber,
            AnnualIncreasePercent: row.AnnualIncreasePercent == null ? null : Number(row.AnnualIncreasePercent),
            CarryDiscountOnRenewal: !!row.CarryDiscountOnRenewal,
        };
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractOrderEntityServer(): void {
    void ContractOrderEntityServer;
}
