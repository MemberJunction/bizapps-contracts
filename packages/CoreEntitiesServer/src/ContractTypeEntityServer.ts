/**
 * @fileoverview Server-side `ContractType` — the defaults every new term inherits.
 *
 * WHY A TYPE NEEDS ITS OWN VALIDATION. `ContractType` is configuration-as-data: the columns ARE the
 * rules, and `ContractTermEntityServer.applyContractTypeDefaults` copies them onto every new term.
 * That makes this table a MULTIPLIER — a bad value here does not produce one bad row, it produces
 * one per term created from that type, each of which then looks locally valid.
 *
 * THE RULE THAT CANNOT BE A CHECK. `DefaultEscalationPercent` must not exceed
 * `DefaultMaxEscalationPercent`. This is the same two-column shape as the term's escalation cap, and
 * it is barred from being a CHECK for the same documented reason: CodeGen derives a generated
 * validation method name from the constraint expression, and a constraint naming two columns makes
 * it emit a call to a method it never defines — a build break in generated code that orders already
 * hit. So the rule lives here, on the one path every write takes.
 *
 * Without it, a type could prescribe a 6% default escalation under a 5% default ceiling. Every term
 * born from it would inherit BOTH, and `ContractTermEntityServer.checkEscalationCap` would then
 * refuse the term — reporting the contradiction against the term, which is not where it came from
 * and not where it can be fixed.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import { BaseEntity, ValidationErrorInfo, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractTypeEntity } from '@mj-biz-apps/contracts-entities';

const TYPE_ENTITY = 'MJ_BizApps_Contracts: Contract Types';

@RegisterClass(BaseEntity, TYPE_ENTITY)
export class ContractTypeEntityServer extends mjBizAppsContractsContractTypeEntity {
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkDefaultEscalationUnderItsCap(result);
        return result;
    }

    /**
     * Both are fractions (0.05 = 5%). A null cap means "uncapped", which is deliberately permitted —
     * plenty of real agreements have no ceiling, and pretending otherwise would make them
     * unrecordable. Only a stated ceiling can be exceeded.
     */
    private checkDefaultEscalationUnderItsCap(result: ValidationResult): void {
        const pct = this.DefaultEscalationPercent;
        const cap = this.DefaultMaxEscalationPercent;
        if (pct === null || pct === undefined || cap === null || cap === undefined) return;
        if (pct <= cap) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'DefaultEscalationPercent',
                `This type prescribes a default escalation of ${(pct * 100).toFixed(2)}% under a default ` +
                    `ceiling of ${(cap * 100).toFixed(2)}%. Every term created from it would inherit both and ` +
                    'then be refused for exceeding its own cap — reporting the contradiction against the term, ' +
                    'which is not where it can be fixed. Resolve it here instead.',
                pct,
            ),
        );
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadContractTypeEntityServer(): void {
    /* intentionally empty */
}
