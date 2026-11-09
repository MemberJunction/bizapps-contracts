/**
 * @fileoverview `ContractTypeEntity` and `ContractTemplateTypeEntity` — the two lookup tables, which
 * exist as subclasses for exactly one reason: their value-list columns are validated NOWHERE.
 *
 * Both carry an `nvarchar` column constrained by `CHECK (… IN (…))` — `ContractType.Status` and
 * `ContractTemplateType.Status`. (A third, `ContractType.ParentStatusRequirement`, was the original
 * motivating case; R-4 replaced it with two booleans, which need no value list at all — a `bit` has
 * only two possible values. The guard stays generic, so losing a field does not change it.) CodeGen
 * renders that kind of
 * constraint as value-list METADATA rather than as a generated `Validate()` method, and `BaseEntity`
 * never reads value-list metadata, so the constraint has no TypeScript representation at all. Full
 * reasoning, and the deletion plan, in `value-list-validation.ts`; filed as MJ#3969.
 *
 * These are the app's only entities with value-list fields today. `ValidateValueLists` is generic
 * rather than field-specific, so a future one is covered by adding the call, not by writing a check.
 *
 * WHY THESE TWO AND NOT ALL FIVE UNSUBCLASSED ENTITIES. `ContractTemplate` and
 * `ContractTemplateProvision` also lack subclasses, and both will need one — for provision
 * immutability (R-1) and the `ProvisionNumber` sort key (R-11). Neither rule is decided yet, and a
 * subclass created ahead of a rule is a file that says nothing while looking like it says something.
 * They arrive with their rules. `ContractSequence` is a separate question (R-7): whether it should be
 * an API-writable entity at all.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import { BaseEntity, type EntityDeleteOptions, EntitySaveOptions, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import {
    mjBizAppsContractsContractTemplateTypeEntity,
    mjBizAppsContractsContractTypeEntity,
} from './generated/entity_subclasses';
import { InvalidateContractTypeCache } from './contract-type-cache';
import { ValidateValueLists } from './value-list-validation';

/**
 * `Status` (`Active` / `Inactive`) — the only value-list column left on this table.
 *
 * It is load-bearing rather than cosmetic: R-5 refuses a contract that NEWLY selects a type whose
 * `Status` is `Inactive`, and R-8 refuses deleting a type in use while telling the user to retire it
 * instead. So "Active" / "Inactive" is the vocabulary two rules read, and the database's `CHECK` is
 * what keeps a third string out of the column — but it refuses at the very end, as a constraint
 * violation naming no field. This makes the refusal arrive on the field, in the browser, before the
 * round trip.
 *
 * The type's three RULE columns (`MustBeRoot`, `MustBeChild`, `TemplateRequired`) are `bit`s and need
 * nothing here — a boolean cannot hold an out-of-list value, which is half the argument R-4 made for
 * replacing the three-state string.
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Types')
export class ContractTypeEntity extends mjBizAppsContractsContractTypeEntity {
    public override Validate(): ValidationResult {
        const result = super.Validate();
        ValidateValueLists(this, result);
        return result;
    }

    /**
     * Forces the write when `DefaultAutoRenew` moves between "No" (`false`) and "no default" (`null`)
     * (#149). MJ's `EntityField.Dirty` compares `bit` fields through `convertToBoolean`, which turns
     * `null` into `false`, so those two transitions look clean: `BaseEntity` skips the provider and
     * `Save()` still returns `true`. The override lives on the shared class because MJAPI's
     * `UpdateRecord` goes through the same dirty gate. Remove it once `EntityField.Dirty` treats `null`
     * and `false` as different on a nullable `bit`.
     */
    public override async Save(options?: EntitySaveOptions): Promise<boolean> {
        const saveOptions = this.defaultAutoRenewNullnessChanged()
            ? { ...(options ?? new EntitySaveOptions()), IgnoreDirtyState: true }
            : options;
        const saved = await super.Save(saveOptions);
        if (saved) {
            InvalidateContractTypeCache(this.RunViewProviderToUse, this.ID);
        }
        return saved;
    }

    public override async Delete(options?: EntityDeleteOptions): Promise<boolean> {
        // `BaseEntity.Delete()` ends in `NewRecord()`, which assigns a fresh ID, so read it first.
        const deletedID = this.ID;
        const deleted = await super.Delete(options);
        if (deleted) {
            InvalidateContractTypeCache(this.RunViewProviderToUse, deletedID);
        }
        return deleted;
    }

    /** True on a saved record whose `DefaultAutoRenew` went from null to a value or back. */
    private defaultAutoRenewNullnessChanged(): boolean {
        if (!this.IsSaved) return false;
        const field = this.GetFieldByName('DefaultAutoRenew');
        if (!field) return false;
        const isNull = (v: unknown) => v === null || v === undefined;
        return isNull(field.OldValue) !== isNull(field.Value);
    }
}

/** `Status` (`Active` / `Inactive`) — see the note above. */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Types')
export class ContractTemplateTypeEntity extends mjBizAppsContractsContractTemplateTypeEntity {
    public override Validate(): ValidationResult {
        const result = super.Validate();
        ValidateValueLists(this, result);
        return result;
    }
}

/**
 * Anti-tree-shake anchor. Importing this module is what fires `@RegisterClass`; a production build can
 * drop an import whose class is never referenced, and a dropped registration means the rules above
 * silently stop existing — the same reason `LoadContractEntity` exists.
 */
export function LoadContractTypeEntities(): void {
    void ContractTypeEntity;
    void ContractTemplateTypeEntity;
}
