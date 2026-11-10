/**
 * @fileoverview `Contracts.RecordNonRenewalOutcomes` — records the renewal-risk label on contracts whose
 * end date has passed (issue #159).
 *
 * `Contract.NonRenewalOutcome` is a stored column. The database writes it on every save (a trigger) and
 * holds the rule in one function, so a termination or a supersession is recorded by the save that makes
 * it. An expiry has no save behind it: the end date passes. This action runs the procedure that applies
 * the same rule to every row whose stored value differs from it today, and a scheduled job runs it hourly.
 *
 * The rule stays in SQL, in `fnContractNonRenewalOutcome`. This file only calls it.
 *
 * @module @mj-biz-apps/contracts-actions
 */
import { BaseAction } from '@memberjunction/actions';
import type { ActionParam, ActionResultSimple, RunActionParams } from '@memberjunction/actions-base';
import { type DatabaseProviderBase, Metadata, type PlatformSQL } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';

/**
 * The call, one form per database. SQL Server: a procedure that ends with `SELECT @Changed AS Changed`.
 * PostgreSQL: a function of the same name returning the count. The schema is unquoted and the function
 * name quoted, the converter's convention (see `ASSIGN_CONTRACT_NUMBER_SQL` in CoreEntitiesServer).
 */
export const RECORD_NON_RENEWAL_OUTCOMES_SQL: PlatformSQL = {
    default: `EXEC __mj_BizAppsContracts.spRecordContractNonRenewalOutcomes;`,
    postgresql: `SELECT __mj_BizAppsContracts."spRecordContractNonRenewalOutcomes"() AS "Changed";`,
};

function setOutput(params: RunActionParams, name: string, value: unknown): void {
    const existing = params.Params?.find((p) => p.Name?.toLowerCase() === name.toLowerCase());
    if (existing) {
        existing.Value = value;
        return;
    }
    params.Params = params.Params ?? [];
    params.Params.push({ Name: name, Value: value, Type: 'Output' } as ActionParam);
}

@RegisterClass(BaseAction, 'Contracts.RecordNonRenewalOutcomes')
export class RecordNonRenewalOutcomesAction extends BaseAction {
    protected async InternalRunAction(params: RunActionParams): Promise<ActionResultSimple> {
        try {
            // A server-side action always runs on a database provider; the metadata-provider type does not
            // declare ExecuteSQL, so this narrows to the base class that does.
            const db = Metadata.Provider as unknown as DatabaseProviderBase;
            const rows = await db.ExecuteSQL<{ Changed: number | string }>(
                db.ResolveSQL(RECORD_NON_RENEWAL_OUTCOMES_SQL),
                undefined,
                { isMutation: true, description: 'spRecordContractNonRenewalOutcomes' },
                params.ContextUser,
            );
            const changed = Number(rows?.[0]?.Changed ?? 0);
            setOutput(params, 'Changed', changed);
            return {
                Success: true,
                ResultCode: 'SUCCESS',
                Message: `Recorded the renewal outcome on ${changed} contract(s).`,
            };
        } catch (error) {
            return {
                Success: false,
                ResultCode: 'ERROR',
                Message: `Recording renewal outcomes failed: ${error instanceof Error ? error.message : String(error)}`,
            };
        }
    }
}

/** Anti-tree-shaking anchor — `@RegisterClass` is a side effect of import. */
export function LoadRecordNonRenewalOutcomesAction(): void {
    void RecordNonRenewalOutcomesAction;
}
