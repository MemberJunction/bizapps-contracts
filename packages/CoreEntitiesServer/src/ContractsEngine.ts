/**
 * @fileoverview The lookup cache for BizApps Contracts — `ContractType` and its defaults.
 *
 * WHY THIS EXISTS. `ContractType` is the textbook high-read / low-write entity: six rows that
 * effectively never change, read on every roster load, every workspace open and every create form.
 * Before this, each of those paths ran its own `RunView` against the same six rows.
 *
 * WHAT IT IS ACTUALLY FOR, though, is not saving a query — six rows are cheap. It is that a
 * contract type is CONFIGURATION AS DATA: the columns ARE the rules. `DefaultTermMonths`,
 * `DefaultEscalationPercent`, `DefaultMaxEscalationPercent`, `DefaultRenewalNoticeDays`,
 * `DefaultCancellationWindowDays`, `RenewalMode` — the engine is supposed to READ those and act on
 * them, never to branch on a type's name. A cache with typed accessors is what makes that practical:
 * `ContractsEngine.Instance.TypeByID(id)?.DefaultMaxEscalationPercent` is a compile-checked read,
 * where a hand-rolled RunView with a `Fields` list would hand back `undefined` for a column that was
 * renamed and nobody would find out until a renewal escalated past a cap.
 *
 * `ResultType: 'entity_object'` for the same reason: callers get typed entities, so reading a column
 * that does not exist is a compile error rather than a run-time `undefined`.
 *
 * SHAPE COPIED FROM `OrdersEngine`, deliberately — same `BaseEngine` subclass, same `Instance`
 * accessor, same `Config()` signature, same `Load<Engine>(provider, user)` convenience function, same
 * case-insensitive ID matching. Somebody who has read one should not have to learn the other.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import { BaseEngine, type IMetadataProvider, type UserInfo } from '@memberjunction/core';
import type { mjBizAppsContractsContractTypeEntity } from '@mj-biz-apps/contracts-entities';

/**
 * The lookup cache for BizApps Contracts.
 *
 * Use `ContractsEngine.Instance` after `Config()`; every accessor is a synchronous property read.
 */
export class ContractsEngine extends BaseEngine<ContractsEngine> {
    public static get Instance(): ContractsEngine {
        return super.getInstance<ContractsEngine>();
    }

    private _contractTypes: mjBizAppsContractsContractTypeEntity[] = [];

    /**
     * Load (or refresh) the cache.
     *
     * Only `ContractType` is cached, and that is a deliberate limit rather than a starting point.
     * Contracts, terms and lines are the opposite shape — many rows, written constantly — so caching
     * them would trade a cheap query for a stale read of the exact data a contract argument turns on.
     * The rule is high-read/low-write, and `ContractType` is the only entity here that qualifies.
     */
    public async Config(forceRefresh?: boolean, contextUser?: UserInfo, provider?: IMetadataProvider): Promise<void> {
        await this.Load(
            [
                {
                    Type: 'entity',
                    PropertyName: '_contractTypes',
                    EntityName: 'MJ_BizApps_Contracts: Contract Types',
                    ResultType: 'entity_object',
                },
            ],
            provider as IMetadataProvider,
            forceRefresh,
            contextUser,
        );
    }

    public get ContractTypes(): mjBizAppsContractsContractTypeEntity[] {
        return this._contractTypes;
    }

    /** The active types, which is what a picker should offer — inactive ones stay readable by ID. */
    public get ActiveContractTypes(): mjBizAppsContractsContractTypeEntity[] {
        return this._contractTypes.filter((t) => t.IsActive);
    }

    /** One type by ID, or undefined. */
    public TypeByID(id: string | null | undefined): mjBizAppsContractsContractTypeEntity | undefined {
        return byID(this._contractTypes, id);
    }

    /**
     * One type by its stable code (`Standard`, `MSA`, `SOW`, …).
     *
     * Case-insensitive because `Code` is unique under SQL Server's case-insensitive collation, so
     * `'msa'` and `'MSA'` are the same row in the database and pretending otherwise here would make
     * this lookup disagree with the unique index.
     */
    public TypeByCode(code: string | null | undefined): mjBizAppsContractsContractTypeEntity | undefined {
        if (!code) return undefined;
        const wanted = code.trim().toLowerCase();
        return this._contractTypes.find((t) => t.Code?.trim().toLowerCase() === wanted);
    }

    /**
     * The escalation ceiling a new term should inherit from its contract's type, or null when the
     * type sets none.
     *
     * Exposed as a named method rather than leaving callers to reach through `TypeByID(...)?.` — this
     * is the value the whole escalation-cap invariant turns on, and a caller that silently gets
     * `undefined` because it mistyped the property would create terms with NO ceiling, which is the
     * uncapped "then-current list price" case the cap exists to prevent.
     */
    public DefaultMaxEscalationFor(contractTypeID: string | null | undefined): number | null {
        return this.TypeByID(contractTypeID)?.DefaultMaxEscalationPercent ?? null;
    }

    /** The renewal notice period a new term should inherit, or null when the type sets none. */
    public DefaultRenewalNoticeDaysFor(contractTypeID: string | null | undefined): number | null {
        return this.TypeByID(contractTypeID)?.DefaultRenewalNoticeDays ?? null;
    }
}

/** Case-insensitive ID match — SQL Server hands UUIDs back in either case. */
function byID<T extends { ID?: string }>(rows: T[], id: string | null | undefined): T | undefined {
    if (!id) return undefined;
    const wanted = id.toLowerCase();
    return rows.find((r) => r.ID?.toLowerCase() === wanted);
}

/**
 * Load the cache. Idempotent and cheap after the first call.
 *
 * A thin function rather than making callers reach for `ContractsEngine.Instance.Config(...)`, so
 * the argument order is decided once — matching `LoadOrdersEngine`.
 */
export async function LoadContractsEngine(provider: IMetadataProvider, user: UserInfo): Promise<void> {
    await ContractsEngine.Instance.Config(false, user, provider);
}
