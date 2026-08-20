/**
 * @fileoverview `ContractEntityServer` — the rules that CANNOT run in a browser.
 *
 * Registered later than the shared `ContractEntity`, so MJ's ClassFactory resolves this one on the
 * server while the browser keeps the shared class (plan §6.3). Everything a client should be able to
 * preflight lives on the shared class instead; what is here needs a lock or a cross-entity read.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import {
    BaseEntity,
    type DatabaseProviderBase,
    LogError,
    ValidationErrorInfo,
    ValidationErrorType,
    ValidationResult,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { ContractEntity } from '@mj-biz-apps/contracts-entities';

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contracts')
export class ContractEntityServer extends ContractEntity {
    /**
     * Mint `ContractNumber` on first save, then persist.
     *
     * WHY THE NUMBER IS MINTED HERE and not defaulted in SQL. It comes from a singleton counter that
     * has to be taken under a lock inside the save's own transaction, so a rollback releases the
     * number instead of burning it. A column default cannot do that, and a client cannot be trusted
     * with it.
     *
     * Contracts needs no `SkipRelatedCollections` dance, unlike orders: nothing here prepares child
     * rows before the graph executor runs, so the plain save carries `Modifications` with it.
     */
    public override async Save(): Promise<boolean> {
        try {
            if (!this.IsSaved && !this.ContractNumber) {
                this.ContractNumber = await this.assignContractNumber();
            }
            return await super.Save();
        } catch (err) {
            LogError(`ContractEntityServer.Save failed for contract ${this.ContractNumber ?? this.ID}: ${err}`);
            throw err;
        }
    }

    /**
     * Server-authoritative rules that need to read another entity.
     *
     * SETTLE THE `HasModifications` UNKNOWN CASE. The shared `ContractEntity.Validate()` only rejects
     * a false flag when it can PROVE rows exist — `Modifications.Count > 0`. On an ordinary form load
     * the collection is not loaded, so `Count === 0` means *unknown*, and the shared guard stays
     * silent by design rather than refusing a legitimate save.
     *
     * That design is only honest if something settles the unknown case, and until now nothing did:
     * load a saved contract without its modifications, set `HasModifications = false`, save, and it
     * succeeded — flag false with rows in the table, which ERD §4.4 explicitly rejects and which the
     * modification subclass's own comment calls the single most misleading state this app can produce.
     * The shared class's comment PROMISED this check existed. Caught on review of PR #9.
     *
     * One `EXISTS`, and only when it can matter (`IsSaved && HasModifications === false`), so the
     * ordinary save pays nothing. The message is the shared class's, deliberately — the user should
     * not be able to tell which tier refused them.
     *
     * THE TYPE DECIDES WHETHER A PARENT IS ALLOWED. `ContractType.ParentStatusRequirement` is
     * `'Required'`, `'Prohibited'` or NULL, and this reads it. The rule needs the type row, which is a
     * join the browser has no business doing, so the shared class cannot carry it (ERD §7.1).
     *
     * ⚠ THIS USED TO COMPARE THE TYPE'S NAME TO THE STRING 'Change Order' — and that was the defect,
     * not a shortcut. A display name is not a rule: renaming that lookup row, an ordinary thing to do,
     * silently stopped the check from ever firing, with nothing failing and no error to notice. The
     * column now carries the constraint, so the rule reads a rule (Marcelo, 2026-08-19).
     *
     * Both directions are enforced, because a column with three states that only ever checks one of
     * them is two-thirds decoration: `'Required'` refuses a missing parent (a change order that amends
     * nothing would never appear in the original agreement's lineage), and `'Prohibited'` refuses a
     * present one (a root agreement sitting under another contract is a lineage cycle waiting to
     * happen). NULL enforces nothing, which is the honest default for a type that can legitimately do
     * either.
     */
    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();

        if (this.IsSaved && this.HasModifications === false && (await this.modificationRowsExist())) {
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    'HasModifications',
                    `Contract ${this.ContractNumber ?? ''} has modifications recorded against the standard ` +
                        `agreement, so it cannot be marked as unmodified. Remove the modifications first if the ` +
                        `agreement really is standard.`,
                    this.HasModifications,
                    ValidationErrorType.Failure,
                ),
            );
        }

        if (this.ContractTypeID) {
            const requirement = await this.parentStatusRequirement();
            if (requirement === 'Required' && !this.ParentContractID) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ParentContractID',
                        `Contract ${this.ContractNumber ?? ''} is a ${await this.typeName()}, which must name the ` +
                            `contract it changes. One that names nothing amends nothing, and would not appear in the ` +
                            `original agreement's lineage.`,
                        this.ParentContractID,
                        ValidationErrorType.Failure,
                    ),
                );
            } else if (requirement === 'Prohibited' && this.ParentContractID) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ParentContractID',
                        `Contract ${this.ContractNumber ?? ''} is a ${await this.typeName()}, which stands on its own ` +
                            `and cannot sit under another contract. Record the relationship the other way round, or ` +
                            `change the contract type.`,
                        this.ParentContractID,
                        ValidationErrorType.Failure,
                    ),
                );
            }
        }

        return result;
    }

    /**
     * A shrotcut to get the datbaseProvider.
     *
     * `ExecuteSQL<T>(query, parameters?, options?, contextUser?)` is a public member of
     * `DatabaseProviderBase`, which `@memberjunction/core` exports — so the four
     * `as unknown as { ExecuteSQL: … }` casts this replaces were never necessary. Each of them
     * re-declared a narrower signature than the real one: no generic (forcing a second cast on every
     * result), and no `contextUser` parameter, which made the API look as though it could not carry a
     * context user at all. Worse, `as unknown as` switches off checking, so a signature change
     * upstream would have compiled here and failed at runtime.
     *
     * `ProviderToUse` is typed as the metadata-provider interface, which does not declare
     * `ExecuteSQL`; this is a narrowing cast to the concrete base class, which is what a server-side
     * entity subclass always has. It is one cast in one place instead of four scattered ones, and it
     * keeps the real generic signature.
     */
    private get db(): DatabaseProviderBase {
        return this.ProviderToUse as unknown as DatabaseProviderBase;
    }

    /**
     * Whether any modification row exists for this contract, read from the DATABASE rather than the
     * collection — which is the whole point: the collection is exactly what the browser could not
     * know about. `TOP 1` because existence is the question, not the count.
     */
    private async modificationRowsExist(): Promise<boolean> {
        // `count_only` returns no rows and populates TotalRowCount, which is exactly the question.
        const result = await this.RunViewProviderToUse.RunView(
            {
                EntityName: 'MJ_BizApps_Contracts: Contract Template Modifications',
                ExtraFilter: `ContractID = '${this.ID}'`,
                ResultType: 'count_only',
            },
            this.ContextCurrentUser,
        );
        if (!result?.Success) {
            // A failed read must not read as "no modifications" — that would let the flag be cleared
            // on a contract whose rows simply could not be counted.
            throw new Error(`Could not count modifications for contract ${this.ID}: ${result?.ErrorMessage ?? 'unknown error'}`);
        }
        return (result.TotalRowCount ?? 0) > 0;
    }

    /**
     * What this contract's TYPE says about naming a parent: `'Required'`, `'Prohibited'` or null.
     *
     * One scalar read, no entity load, and memoised for the call — `ValidateAsync` asks for the
     * requirement and then for the type's name to build the message, and a validation pass should not
     * make two round trips to say one thing.
     */
    private async typeRule(): Promise<{ Name: string; ParentStatusRequirement: string | null } | null> {
        if (this.cachedTypeRule !== undefined) return this.cachedTypeRule;
        const result = await this.RunViewProviderToUse.RunView<{ Name: string; ParentStatusRequirement: string | null }>(
            {
                EntityName: 'MJ_BizApps_Contracts: Contract Types',
                ExtraFilter: `ID = '${this.ContractTypeID}'`,
                Fields: ['Name', 'ParentStatusRequirement'],
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        this.cachedTypeRule = result?.Results?.[0] ?? null;
        return this.cachedTypeRule;
    }

    /**
     * Cleared on nothing, and that is safe: a contract's type can change between saves, but this cache
     * lives only for the duration of one `ValidateAsync` call tree — the field is re-read from the
     * database on the next validation because a new entity instance is what a new save uses.
     */
    private cachedTypeRule: { Name: string; ParentStatusRequirement: string | null } | null | undefined = undefined;

    /** The type's parent restriction, or null when the type imposes none. */
    private async parentStatusRequirement(): Promise<string | null> {
        return (await this.typeRule())?.ParentStatusRequirement ?? null;
    }

    /** The type's display name, for the refusal message — naming the type the user chose. */
    private async typeName(): Promise<string> {
        return (await this.typeRule())?.Name ?? 'contract of this type';
    }

    /**
     * Mint the next contract number by calling the database's own numbering procedure.
     *
     * WHY A SPROC AND NOT `RunView` / `RunQuery` / `BaseEntity`. This is an atomic
     * read-modify-write, and none of those can express one: `RunView` is read-only, `RunQuery` is a
     * read surface (hiding DML inside a "query" would be worse than being honest about it), and the
     * entity path removes the lock — two concurrent creates would both read N, both mint the same
     * number, and the collision would surface later as a unique-index violation on the insert rather
     * than as a serialised wait.
     *
     * So the lock stays in the database, in a DATABASE OBJECT rather than a TypeScript string.
     * `spAssignNextContractNumber` (V202608192200) holds the `HOLDLOCK, UPDLOCK` and the format; this
     * method is one dialect-free `EXEC`. That is accounting's pattern, adopted rather than invented —
     * `SequenceService.ts` there keeps `spAssignNextJournalEntryNumber` at DB level for the same
     * stated reason. Orders still inlines the same UPDATE in four places, which is what this stops
     * doing.
     *
     * It also makes the PostgreSQL port a database exercise: write a PG function with this name and
     * signature and no application code changes.
     *
     * `isMutation: true` matters and was missing while this was inline: MJ's SQL-statement logging
     * uses it to know a statement CHANGED data, which is what lets a logging session capture the
     * mutation. `description` names the operation in that log.
     *
     * ⚠ NOT gap-free. On a standalone save the number is consumed before the row's own transaction
     * opens, so a later failure has already spent it; inside a graph save a rollback releases it. The
     * unique index is the real guard.
     */
    private async assignContractNumber(): Promise<string> {
        const rows = await this.db.ExecuteSQL<{ ContractNumber: string }>(
            `DECLARE @contractNumber NVARCHAR(50);
             EXEC __mj_BizAppsContracts.spAssignNextContractNumber @ContractNumber = @contractNumber OUTPUT;
             SELECT @contractNumber AS ContractNumber;`,
            // No parameters: the sproc takes only an OUTPUT, declared in the batch above. Accounting
            // passes an OBJECT here because its sprocs take inputs and `ExecuteSQL` binds objects BY
            // NAME while an array binds positionally as @p0 — worth knowing before adding a parameter
            // to this call, and worth noting that the object form needs the SQLServerDataProvider type
            // rather than the DatabaseProviderBase one this uses.
            undefined,
            { isMutation: true, description: 'spAssignNextContractNumber' },
            this.ContextCurrentUser,
        );

        const assigned = rows?.[0]?.ContractNumber; 
        if (!assigned) {
            throw new Error(
                `Could not obtain the next contract number — spAssignNextContractNumber returned nothing. ` +
                    `The ContractSequence singleton row (ID=1) is seeded by the baseline migration.`,
            );
        }
        return assigned;
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractEntityServer(): void {
    void ContractEntityServer;
}
