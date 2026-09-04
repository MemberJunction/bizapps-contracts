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
    type EntityDeleteOptions,
    LogError,
    ValidationErrorInfo,
    ValidationErrorType,
    ValidationResult,
} from '@memberjunction/core';
import { RegisterClass, UUIDsEqual } from '@memberjunction/global';
import { ContractEntity, IsSameContractLevel } from '@mj-biz-apps/contracts-entities';
import { GuardedDelete, plural } from './delete-guard.js';

/**
 * Whether a foreign key is being CHOSEN right now, as opposed to merely being present.
 *
 * A free function so it can be unit-tested against a duck-typed record without a provider — the same
 * reason `ValidateValueLists` and `ExplainMissingRequiredFields` are free functions. The semantics
 * are the whole point and they are easy to get subtly wrong, so they are pinned by tests rather than
 * by this comment:
 *
 *   · NEW record          -> any value is a new selection.  (accounting's identity lock skips this
 *                            case, correctly for its purpose and wrongly for ours)
 *   · SAVED, key changed  -> a new selection.
 *   · SAVED, key the same -> NOT a new selection, whatever the referenced row now says.
 *
 * The comparison is case-insensitive and string-wise because these are UUIDs, which MJ can hand back
 * in either casing depending on how the record was loaded (MJ's UUID_COMPARISON_GUIDE). A `!==` here
 * would report a change on a record nobody touched.
 */
export function IsNewlySelected(entity: BaseEntity, fieldName: string): boolean {
    if (!entity.IsSaved) return true;
    const field = entity.GetFieldByName(fieldName);
    if (!field) return false;
    return String(field.OldValue ?? '').toLowerCase() !== String(field.Value ?? '').toLowerCase();
}

/** The columns of `ContractType` this class reads, in one shot. */
type ContractTypeRule = {
    Name: string;
    /** R-4: may NOT name a ParentContractID. Mutually exclusive with MustBeChild. */
    MustBeRoot: boolean;
    /** R-4: MUST name one. */
    MustBeChild: boolean;
    /** R-4: must carry its own ContractTemplateID. */
    TemplateRequired: boolean;
    /** R-5: 'Active' | 'Inactive'. */
    Status: string | null;
};

/** A retired lookup row. The string is the value the `IN (...)` CHECK constrains `Status` to. */
const RETIRED = 'Inactive';

/** Guards an ID before it is interpolated into the R-3 lineage walk. */
const UUID_SHAPE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

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
            // MINT WHENEVER THE INCOMING VALUE IS ABSENT, and treat blank as absent.
            //
            // The column is NULLABLE as of V202608211200 — MJ cannot express "NOT NULL, assigned by the
            // server on insert" (MJ#4001), and both workarounds broke creation: a DB DEFAULT stops
            // spCreateContract from compiling (MJ#4000), and marking the field read-only drops it from
            // the insert payload entirely. So the database no longer holds this invariant and THIS LINE
            // does. That is the trade, and it is why blank is handled and not just null: a form that
            // posts an empty string, a seed script, or an import would otherwise persist '' as a
            // contract number and the filtered unique index would happily accept exactly one of them.
            if (!this.IsSaved && !(this.ContractNumber ?? '').trim()) {
                this.ContractNumber = await this.assignContractNumber();
                // Tell the shared guard this CTR-… came from the sequence, not from a person. Without
                // it, `refuseReservedContractNumber` would refuse the number we just minted — `Save()`
                // validates below, and on an unsaved record a system-assigned number is
                // indistinguishable from a hand-typed one by shape alone.
                this.NumberWasSystemAssigned = true;
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
     * THE TYPE DECIDES WHERE IN THE TREE A CONTRACT MAY SIT, and whether it needs its own paper.
     * `ContractType.MustBeRoot` / `MustBeChild` / `TemplateRequired` — three booleans, all read from the
     * one memoised type row. The rules need that row, which is a join the browser has no business
     * doing, so the shared class cannot carry them (ERD §7.1).
     *
     * ⚠ TWO GENERATIONS OF DEFECT ARE BURIED HERE, and both are worth remembering.
     *
     * FIRST, this compared the type's NAME to the string 'Change Order'. A display name is not a rule:
     * renaming that lookup row — an ordinary thing to do — silently stopped the check from ever firing,
     * with nothing failing and no error to notice (fixed 2026-08-19).
     *
     * SECOND, the column that replaced the name match was a THREE-STATE STRING,
     * `ParentStatusRequirement IN ('Required','Prohibited')` or NULL. Ruled out by Marcelo on
     * 2026-08-20 as confusing and overly complex, with the transposition argument as the proof: a
     * column whose values INVERT the rule when read in the wrong order is a column that will
     * eventually be read in the wrong order. Now two booleans, mutually exclusive by
     * `CK_ContractType_RootOrChild`, and "both false" means unrestricted — a real and in fact majority
     * state (V202608200300).
     *
     * Both placement directions are enforced, because a rule that only ever checks one of them is half
     * decoration: `MustBeChild` refuses a missing parent (a change order that amends nothing would
     * never appear in the original agreement's lineage), and `MustBeRoot` refuses a present one (a root
     * agreement sitting under another contract is a lineage ring waiting to happen — see R-3).
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
            const rule = await this.typeRule();

            // R-4 — WHERE IN THE TREE this type may sit. Two booleans replacing the three-state
            // `ParentStatusRequirement` string (V202608200300). Both false = unrestricted, which is what
            // two of the four seeded types want, and the CHECK guarantees they are never both true.
            if (rule?.MustBeChild && !this.ParentContractID) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ParentContractID',
                        `Contract ${this.ContractNumber ?? ''} is a ${rule.Name}, which must name the contract it ` +
                            `changes. One that names nothing amends nothing, and would not appear in the original ` +
                            `agreement's lineage.`,
                        this.ParentContractID,
                        ValidationErrorType.Failure,
                    ),
                );
            } else if (rule?.MustBeRoot && this.ParentContractID) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ParentContractID',
                        `Contract ${this.ContractNumber ?? ''} is a ${rule.Name}, which stands on its own and cannot ` +
                            `sit under another contract. Record the relationship the other way round, or change the ` +
                            `contract type.`,
                        this.ParentContractID,
                        ValidationErrorType.Failure,
                    ),
                );
            }

            // R-4 — DOES THIS TYPE NEED ITS OWN PAPER. A separate axis from placement: a type could
            // want any combination, which is why `TemplateRequired` is its own column rather than
            // inferred from the flags above.
            if (rule?.TemplateRequired && !this.ContractTemplateID) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ContractTemplateID',
                        `A ${rule.Name} must reference the agreement version it incorporates. Choose the template ` +
                            `whose standard terms this contract is written against.`,
                        this.ContractTemplateID,
                        ValidationErrorType.Failure,
                    ),
                );
            }
        }

        await this.refuseClearingAReferencedTemplate(result);
        await this.refuseUnusableTemplate(result);

        await this.refuseRetiredSelections(result);
        // Runs BEFORE both lineage guards: each of them skips the self-referential case, and this call
        // is what makes that skip a deduplication rather than an assumption.
        this.refuseSelfReferences(result);
        await this.refuseLineageCycles(result);
        await this.refuseCrossLevelSupersession(result);
        await this.refuseCrossCustomerSupersession(result);

        return result;
    }

    /**
     * R-8 — a contract that other records point at cannot be deleted, and the refusal says who.
     *
     * THREE DEPENDENCIES, and the two lineage ones are the reason this is not obvious. A contract is
     * referenced not only by its modifications but by any contract naming it as `ParentContractID`
     * (its change orders) or as `SupersededByContractID` (the agreement it replaced). Both of those are
     * self-references on `Contract`, so the rows blocking the delete are *other contracts* — and the
     * user is looking at the record they wanted gone, not at the ones pointing to it. Naming them is
     * the whole value.
     *
     * Deleting a superseded contract is the case worth spelling out: it is the *predecessor* in a
     * re-papering chain, so removing it destroys the history the successor exists to continue.
     */
    public override async Delete(options?: EntityDeleteOptions): Promise<boolean> {
        const label = this.ContractNumber ?? this.ID;
        return GuardedDelete(
            this,
            options,
            `Contract ${label} cannot be deleted.`,
            [
                {
                    EntityName: 'MJ_BizApps_Contracts: Contract Template Modifications',
                    Filter: `ContractID = '${this.ID}'`,
                    Describe: (n) =>
                        `It records ${plural(n, 'modification')} to the standard agreement — the record of what was ` +
                        `negotiated. Remove ${n === 1 ? 'it' : 'them'} first if this contract really should go.`,
                },
                {
                    EntityName: 'MJ_BizApps_Contracts: Contracts',
                    Filter: `ParentContractID = '${this.ID}'`,
                    Describe: (n) =>
                        `${plural(n, 'contract')} ${n === 1 ? 'names' : 'name'} it as a parent, so deleting it would ` +
                        `leave ${n === 1 ? 'a change order' : 'change orders'} amending nothing.`,
                },
                {
                    EntityName: 'MJ_BizApps_Contracts: Contracts',
                    Filter: `SupersededByContractID = '${this.ID}'`,
                    Describe: (n) =>
                        `${plural(n, 'contract')} ${n === 1 ? 'was' : 'were'} superseded BY it, so deleting it would ` +
                        `break the re-papering history those contracts point at.`,
                },
            ],
            (o) => super.Delete(o),
        );
    }

    /**
     * R-5 — A RETIRED TYPE MUST NOT BE *NEWLY* SELECTED, and the word doing the work is "newly".
     *
     * A contract that already references a type keeps working. We assume the type was Active when it
     * was chosen, and retiring a type is not a statement about the contracts already signed under it —
     * refusing to save an existing contract because a lookup row was retired years later would make
     * the retirement itself a destructive act. So this is a rule about the EDIT, not about the row.
     *
     * "Newly selected" means one of exactly two things, and both must be covered:
     *   · the record is NEW and names the type at all, or
     *   · the record is SAVED and the foreign key CHANGED.
     *
     * That first clause is why this does not reuse `GLAccountEntityServer`'s shape verbatim.
     * Accounting's identity lock returns early when `OldValue` is null — correct there, because it is
     * asking "did an existing value change". Here the same early return would skip every CREATE, which
     * is the primary case the rule exists for: the Configuration page promises a retired type "stops
     * being offered for new contracts", and a create is the newest selection there is.
     *
     * TIER: code only, no trigger. `Status` lives on another table so a CHECK cannot see it, and the
     * plan ruled a trigger not worth it — the failure mode is a person picking a retired value in our
     * own UI, not silent corruption by an outside writer.
     *
     * COST: the `ContractTypeID` half is FREE — `typeRule()` already reads that row for the
     * parent-status rule, and `Status` now rides along on the same RunView. The `ContractTemplateID`
     * half costs two reads (template -> its type -> that type's `Status`) and only runs when the
     * template FK is newly selected, which is rare. There is no single view exposing the template's
     * type's status; `vwContractTemplates` carries the type's NAME, not its `Status`.
     */
    private async refuseRetiredSelections(result: ValidationResult): Promise<void> {
        if (this.ContractTypeID && this.isNewlySelected('ContractTypeID')) {
            const rule = await this.typeRule();
            if (rule?.Status === RETIRED) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ContractTypeID',
                        `"${rule.Name}" has been retired and cannot be chosen for a contract. Existing ` +
                            `contracts of this type are unaffected — pick a current type for this one.`,
                        this.ContractTypeID,
                        ValidationErrorType.Failure,
                    ),
                );
            }
        }

        if (this.ContractTemplateID && this.isNewlySelected('ContractTemplateID')) {
            const retired = await this.retiredTemplateType();
            if (retired) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ContractTemplateID',
                        `That agreement template is a "${retired}", which has been retired and cannot be ` +
                            `chosen for a contract. Existing contracts referencing it are unaffected — pick a ` +
                            `template of a current type.`,
                        this.ContractTemplateID,
                        ValidationErrorType.Failure,
                    ),
                );
            }
        }
    }

    /**
     * Whether this foreign key is being chosen right now, as opposed to merely being present.
     *
     * On a NEW record any value is a new selection. On a SAVED one, only a change counts — and the
     * comparison is case-insensitively string-wise because these are UUIDs, which MJ can hand back in
     * either casing depending on the path that loaded them (see MJ's UUID_COMPARISON_GUIDE). Comparing
     * them with `!==` would report a change on a record nobody touched, which would refuse saves of
     * contracts whose type is perfectly legal.
     */
    private isNewlySelected(fieldName: string): boolean {
        return IsNewlySelected(this, fieldName);
    }

    /**
     * The NAME of the template's type when that type is retired, or null.
     *
     * Two hops, because `Status` lives on `ContractTemplateType` and the contract points at a
     * `ContractTemplate`. Returns the type's name rather than a boolean so the refusal can say WHICH
     * kind of template was retired — "that template is an Order Form, which we no longer issue" is
     * actionable where "invalid template" sends the user back to the same picker.
     */
    private async retiredTemplateType(): Promise<string | null> {
        const template = await this.RunViewProviderToUse.RunView<{ ContractTemplateTypeID: string }>(
            {
                EntityName: 'MJ_BizApps_Contracts: Contract Templates',
                ExtraFilter: `ID = '${this.ContractTemplateID}'`,
                Fields: ['ContractTemplateTypeID'],
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        const typeID = template?.Results?.[0]?.ContractTemplateTypeID;
        // A template we cannot read is not a template we can call retired. Staying silent leaves the
        // FK constraint as the floor, which is the right failure for a missing row.
        if (!typeID) return null;

        const type = await this.RunViewProviderToUse.RunView<{ Name: string; Status: string | null }>(
            {
                EntityName: 'MJ_BizApps_Contracts: Contract Template Types',
                ExtraFilter: `ID = '${typeID}'`,
                Fields: ['Name', 'Status'],
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        const row = type?.Results?.[0];
        return row?.Status === RETIRED ? row.Name : null;
    }


    /**
     * R-3 — a contract may not end up in its own lineage, on either axis.
     *
     * THE HOLE. `CK_Contract_ParentNotSelf` and `CK_Contract_SupersededNotSelf` stop only `A -> A`.
     * Nothing stopped `A -> B -> A`, or a longer ring, because every individual save is legal in
     * isolation: setting B's parent to A is fine, and later setting A's parent to B is fine — the row
     * being written references a different row, which is all a CHECK can see.
     *
     * A cycle can only be created by THE EDGE BEING ADDED, which is what makes the check cheap: the
     * question is not "is the graph acyclic" but "starting from the parent I am proposing, can I reach
     * myself?" One upward walk along an indexed FK, one row per level, and change-order chains are 1–3
     * deep in practice. `Depth < 50` caps it and — more importantly — means an ALREADY-corrupt ring
     * terminates instead of spinning.
     *
     * ⚠ THE CONSEQUENCE OF A CYCLE IS WORSE THAN THE PLAN SAYS, and this is worth recording because it
     * changes the tier. R-3 argued a cycle "corrupts nothing silently — it makes the Lineage panel walk
     * forever, which is loud." That was true when written. It is not true now: `vwContracts` computes
     * `RootParentContractID` and `RootSupersededByContractID` through
     * `fnContract*_GetRootID`, whose CTE walks to `Depth < 100` and then selects the row
     * `WHERE ParentContractID IS NULL`. In a ring **no row satisfies that**, so the function returns no
     * row and the column comes back **NULL** — silently wrong, on the app's primary view, for every
     * contract in the ring, while also costing 100 levels of recursion per row on every read. So a
     * cycle is quiet after all, which is exactly the shape of defect this app keeps designing away.
     *
     * SKIPPED ON A CREATE. An unsaved contract has an ID but no row, so nothing can point at it and no
     * walk can reach it. Skipped when the proposed target IS this record, too — that is `A -> A`, which
     * the generated CHECK validator already reports, and two errors for one mistake is its own defect.
     */
    private async refuseLineageCycles(result: ValidationResult): Promise<void> {
        if (!this.IsSaved) return;

        const axes = [
            {
                Field: 'ParentContractID',
                Proposed: this.ParentContractID,
                Message: (chain: string) =>
                    `That would put contract ${this.ContractNumber ?? this.ID} inside its own parent chain ` +
                    `(${chain}). A contract cannot be, directly or indirectly, its own parent — the lineage has ` +
                    `to end somewhere for the app to know which agreement is the original.`,
            },
            {
                Field: 'SupersededByContractID',
                Proposed: this.SupersededByContractID,
                Message: (chain: string) =>
                    `That would make contract ${this.ContractNumber ?? this.ID} supersede itself through a chain ` +
                    `(${chain}). Re-papering has to move forward: the agreement that replaces this one cannot ` +
                    `already be replaced by it.`,
            },
        ] as const;

        for (const axis of axes) {
            const proposed = axis.Proposed;
            if (!proposed) continue;
            if (!this.isNewlySelected(axis.Field)) continue;
            // A -> A is reported by `refuseSelfReferences`, called just before this method, so skipping
            // it here deduplicates a failure THIS CLASS has already recorded. It previously said the
            // error "belongs to the generated CHECK validator" — an assumption about code this class does
            // not own, and that validator turns out to miss the case where the two UUIDs differ only in
            // casing. `ParentContractID -> self` had NO other check here at all, so that axis was relying
            // entirely on it.
            if (UUIDsEqual(proposed, this.ID)) continue;

            const chain = await this.lineageReachesSelf(axis.Field, proposed);
            if (chain) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(axis.Field, axis.Message(chain), proposed, ValidationErrorType.Failure),
                );
            }
        }
    }

    /**
     * A contract may not be its own parent, nor its own successor. Reported HERE, unconditionally.
     *
     * WHY THIS EXISTS when `CK_Contract_ParentNotSelf` / `CK_Contract_SupersededNotSelf` and their
     * generated validators all cover it: because the generated validators DO NOT actually cover it.
     * They are LLM-authored from the constraint text (`generateValidatorFunctionFromCheckConstraint`
     * → the `CodeGen: Check Constraint Parser` prompt), and both emitted `===` on a `uniqueidentifier`:
     *
     *     if (this.SupersededByContractID != null && this.SupersededByContractID === this.ID) { ... }
     *
     * MJ returns UUIDs in either casing depending on how a row was loaded, so a lowercase value against
     * an uppercase `ID` is the SAME contract and that check silently misses it. Filed in MJ-UPSTREAM.md.
     *
     * AND THE RULE IS CHECKED WHOLE, not only the part the generated code misses. Covering just the
     * casing-differs case and deferring the rest would bless a genuinely invalid state on an assumption
     * about code this class does not own — and the moment that code changes, an invalid state starts
     * reading as success. The cost of overlap is one duplicated message; the cost of the gap is a wrong
     * save. This is also why the two lineage guards below delegate here rather than each deciding: one
     * owner, checked fully, in this file, where the skip can be verified by reading it.
     */
    private refuseSelfReferences(result: ValidationResult): void {
        const axes: Array<{ Field: 'ParentContractID' | 'SupersededByContractID'; Value: string | null; Message: string }> = [
            { Field: 'ParentContractID', Value: this.ParentContractID, Message: 'A contract cannot be its own parent.' },
            { Field: 'SupersededByContractID', Value: this.SupersededByContractID, Message: 'A contract cannot be superseded by itself.' },
        ];
        for (const axis of axes) {
            if (!axis.Value || !UUIDsEqual(axis.Value, this.ID)) continue;
            result.Success = false;
            result.Errors.push(new ValidationErrorInfo(axis.Field, axis.Message, axis.Value, ValidationErrorType.Failure));
        }
    }

    /**
     * A contract may only supersede a contract at the SAME LEVEL of the tree — same `ParentContractID`.
     *
     * WHY THIS IS NOT "ROOT ONLY" (ruled by Marcelo, 2026-08-20). The obvious-looking rule is that only
     * a top-level agreement may be re-papered. It is wrong in both directions. A change order genuinely
     * does get renegotiated and replaced by a second change order under the same order form — forbidding
     * that would force somebody to DELETE the first one, destroying the history re-papering exists to
     * preserve. And "root only" would still permit the incoherent case: a change order claiming to
     * replace a whole order form, which asserts that a subordinate document replaced the agreement it
     * hangs off.
     *
     * So the axis that matters is not depth, it is SIBLINGHOOD. `ParentContractID` says what a document
     * sits under; `SupersededByContractID` says what replaced it. A supersession that crosses levels is
     * the only genuinely meaningless combination, and same-parent is exactly the predicate that excludes
     * it while allowing everything real: two roots (both NULL) or two siblings (same parent).
     *
     * TYPE IS DELIBERATELY NOT CONSTRAINED. An Order Form replaced by an Order Form is the common case,
     * but a Payment Link customer graduating to signed paper is a real cross-type supersession — and
     * `Payment Link -> Order Form` is precisely the upgrade path the two types exist to distinguish.
     * Constraining `ContractTypeID` here would forbid it for no benefit.
     *
     * WHY THIS IS NOT A CHECK CONSTRAINT. The rule compares THIS row's `ParentContractID` with ANOTHER
     * row's, and a CHECK sees only the row being written — the same reason `refuseLineageCycles` lives
     * here. One indexed read of the target contract is the whole cost.
     *
     * RUNS ON CREATE TOO, unlike `refuseLineageCycles`. A cycle is impossible before the row exists
     * (nothing can point at it yet), but a cross-level supersession is entirely possible on a brand-new
     * contract — a successor composed in the browser names its predecessor before either is saved, which
     * is the primary flow this rule exists to police. Gated on `isNewlySelected` instead, so an ordinary
     * re-save of an existing chain is not re-policed and legacy rows are not retro-refused.
     */
    private async refuseCrossLevelSupersession(result: ValidationResult): Promise<void> {
        if (!this.SupersededByContractID) return;
        if (!this.isNewlySelected('SupersededByContractID')) return;

        // Reported in full by `refuseSelfReferences`, which runs immediately before this method.
        // Comparing a contract's level against its own is meaningless, so there is nothing further to
        // say here — this skips a SECOND message for a failure this class has already recorded, which is
        // not the same thing as trusting another layer to catch it.
        if (UUIDsEqual(this.SupersededByContractID, this.ID)) return;

        const target = await this.RunViewProviderToUse.RunView<{ ContractNumber: string; ParentContractID: string | null }>(
            {
                EntityName: 'MJ_BizApps_Contracts: Contracts',
                ExtraFilter: `ID = '${this.SupersededByContractID}'`,
                Fields: ['ContractNumber', 'ParentContractID'],
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        const row = target?.Results?.[0];
        if (!row) {
            // A contract cannot be superseded by one that does not exist — the successor must be saved
            // before anything can point at it. `FK_Contract_SupersededBy` would refuse this too, but it
            // reports a constraint name and no field, so the refusal is worth stating properly.
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    'SupersededByContractID',
                    `The contract named as replacing ${this.ContractNumber ?? this.ID} could not be found. It may ` +
                        `have been deleted, or you may not have access to it. Pick an existing contract, or clear ` +
                        `the field if this agreement has not been re-papered.`,
                    this.SupersededByContractID,
                    ValidationErrorType.Failure,
                ),
            );
            return;
        }

        const myParentID = this.ParentContractID ?? null;
        const theirParentID = row.ParentContractID ?? null;
        if (IsSameContractLevel(myParentID, theirParentID)) return;

        // Say which side is which, because "levels differ" leaves the reader to work out whether to move
        // the parent or pick a different successor.
        const describe = (parent: string | null, label: string): string =>
            parent === null ? `${label} is a top-level agreement` : `${label} sits under another contract`;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'SupersededByContractID',
                `Contract ${this.ContractNumber ?? this.ID} cannot be superseded by ${row.ContractNumber ?? 'that contract'}: ` +
                    `${describe(myParentID, 'this contract')}, but ${describe(theirParentID, 'that one')}. A re-papering replaces an ` +
                    `agreement with one at the same level — two top-level agreements, or two documents under the same ` +
                    `parent. Pick a successor alongside this contract, or correct whichever parent is wrong.`,
                this.SupersededByContractID,
                ValidationErrorType.Failure,
            ),
        );
    }

    /**
     * A re-papering replaces one customer's agreement with another agreement for THAT SAME CUSTOMER.
     *
     * WHY THE SERVER OWNS THIS, given the picker already filters on it (issue #28 item 4). The picker
     * decides what to OFFER; this decides what is ALLOWED, and the two are not the same surface. The
     * FK is writable by anything holding a `ContractEntity` — the generated form, an import, another
     * app — and only the entity tier sees all of them. Exactly the split already documented on
     * `refuseCrossLevelSupersession`, which this mirrors deliberately: same trigger, same shape, same
     * `isNewlySelected` gate so a re-save of an existing chain is not retro-refused.
     *
     * Cross-customer supersession is not a rule about tidiness. `Superseded` is derived from this
     * column, so pointing one customer's contract at another's silently retires an agreement that is
     * still in force, for a party who was never involved in the re-papering.
     */
    private async refuseCrossCustomerSupersession(result: ValidationResult): Promise<void> {
        if (!this.SupersededByContractID) return;
        if (!this.isNewlySelected('SupersededByContractID')) return;

        // Reported in full by `refuseSelfReferences`; a contract always shares a customer with itself,
        // so there is nothing this rule could add beyond a second message for the same failure.
        if (UUIDsEqual(this.SupersededByContractID, this.ID)) return;

        const target = await this.RunViewProviderToUse.RunView<{
            ContractNumber: string;
            CustomerOrganizationID: string;
            CustomerOrganization: string | null;
        }>(
            {
                EntityName: 'MJ_BizApps_Contracts: Contracts',
                ExtraFilter: `ID = '${this.SupersededByContractID}'`,
                Fields: ['ContractNumber', 'CustomerOrganizationID', 'CustomerOrganization'],
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        const row = target?.Results?.[0];
        // A missing successor is reported by `refuseCrossLevelSupersession`, which runs immediately
        // before this and reads the same record. Saying it twice helps nobody.
        if (!row) return;

        if (UUIDsEqual(row.CustomerOrganizationID, this.CustomerOrganizationID)) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'SupersededByContractID',
                `Contract ${this.ContractNumber ?? this.ID} cannot be superseded by ` +
                    `${row.ContractNumber ?? 'that contract'}: they belong to different customers` +
                    `${row.CustomerOrganization ? ` (${row.CustomerOrganization})` : ''}. A re-papering ` +
                    `replaces an agreement with a later agreement for the SAME customer. Pick a contract ` +
                    `for this customer, or correct whichever customer is wrong.`,
                this.SupersededByContractID,
                ValidationErrorType.Failure,
            ),
        );
    }

    /**
     * Walk up `<column>` from `startID`; return the chain as text if it reaches this record, else null.
     *
     * Returns the CHAIN rather than a boolean so the refusal can show the ring — "A -> B -> A" is
     * something a person can act on, where "cycle detected" sends them to guess which edge to remove.
     *
     * The column name comes from a fixed internal list, never from input, and both IDs are checked
     * against a UUID shape before interpolation — `ExecuteSQL`'s object-parameter form needs the
     * concrete `SQLServerDataProvider` type rather than the `DatabaseProviderBase` this class holds
     * (see the note on `assignContractNumber`), so a guard plus interpolation is the honest option here
     * rather than a cast that switches off checking.
     */
    private async lineageReachesSelf(column: 'ParentContractID' | 'SupersededByContractID', startID: string): Promise<string | null> {
        if (!UUID_SHAPE.test(startID) || !UUID_SHAPE.test(this.ID)) {
            throw new Error(`Refusing to walk the ${column} lineage: '${startID}' or '${this.ID}' is not a UUID.`);
        }
        const rows = await this.db.ExecuteSQL<{ Chain: string; Depth: number }>(
            `WITH lineage AS (
                 SELECT [ID], [${column}], 1 AS Depth,
                        CAST([ContractNumber] AS NVARCHAR(MAX)) AS Chain
                   FROM __mj_BizAppsContracts.[Contract]
                  WHERE [ID] = '${startID}'
                 UNION ALL
                 SELECT c.[ID], c.[${column}], l.Depth + 1,
                        CAST(l.Chain + N' -> ' + c.[ContractNumber] AS NVARCHAR(MAX))
                   FROM __mj_BizAppsContracts.[Contract] c
                   JOIN lineage l ON c.[ID] = l.[${column}]
                  WHERE l.Depth < 50
             )
             SELECT TOP 1 Chain, Depth FROM lineage WHERE [ID] = '${this.ID}' ORDER BY Depth;`,
            undefined,
            { isMutation: false, description: `R-3 ${column} cycle probe` },
            this.ContextCurrentUser,
        );
        const hit = rows?.[0];
        return hit ? `${this.ContractNumber ?? this.ID} -> ${hit.Chain}` : null;
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
    private async typeRule(): Promise<ContractTypeRule | null> {
        if (this.cachedTypeRule !== undefined) return this.cachedTypeRule;
        // `Status` rides along on a read that already happens (R-5). Asking for it here rather than in
        // its own RunView is the difference between one round trip per validation and two, on the
        // path every single contract save takes.
        const result = await this.RunViewProviderToUse.RunView<ContractTypeRule>(
            {
                EntityName: 'MJ_BizApps_Contracts: Contract Types',
                ExtraFilter: `ID = '${this.ContractTypeID}'`,
                Fields: ['Name', 'MustBeRoot', 'MustBeChild', 'TemplateRequired', 'Status'],
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
    private cachedTypeRule: ContractTypeRule | null | undefined = undefined;


    /**
     * R-12 — a contract may not reference a template nobody can read.
     *
     * `IsUsable` is derived in `vwContractTemplates`: 1 when the template records a `SourceURL` **or**
     * has a file attached, 0 when it has neither. The flag and this refusal do different jobs and both
     * are needed (ruled 2026-08-20):
     *
     *   · **the flag is the affordance** — someone authoring a template sees the red "Unusable" chip and
     *     fixes it, rather than being blocked by a condition they cannot see;
     *   · **this refusal is the floor** — a contract citing standard terms nobody can read is the actual
     *     harm, and it is worth stopping at the moment it would happen.
     *
     * Shipping only the flag leaves the harm unprevented; shipping only the refusal is the confusing
     * version this item started as, where a person is refused for something invisible.
     *
     * ONLY ON A NEW REFERENCE. Whether an EXISTING contract should be affected when its template later
     * becomes unusable is a lifecycle question, and it is R-15's — not this one. So this fires on the
     * same `isNewlySelected` gate as R-5, which also means an ordinary re-save of an existing contract
     * costs nothing.
     */
    private async refuseUnusableTemplate(result: ValidationResult): Promise<void> {
        if (!this.ContractTemplateID) return;
        if (!this.isNewlySelected('ContractTemplateID')) return;

        const template = await this.RunViewProviderToUse.RunView<{ Name: string; IsUsable: boolean; Status: string }>(
            {
                EntityName: 'MJ_BizApps_Contracts: Contract Templates',
                ExtraFilter: `ID = '${this.ContractTemplateID}'`,
                Fields: ['Name', 'IsUsable', 'Status'],
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        const row = template?.Results?.[0];
        // A template we cannot read is not one we can call unusable — the FK stays the floor.
        if (!row) return;

        // R-12 — the terms must be readable.
        if (!row.IsUsable) {
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    'ContractTemplateID',
                    `"${row.Name}" has no source URL and no attached document, so nobody can read the standard ` +
                        `terms it names — a contract cannot incorporate terms that are not available. Add a URL or ` +
                        `attach the agreement document to that template first.`,
                    this.ContractTemplateID,
                    ValidationErrorType.Failure,
                ),
            );
        }

        // V202608200900 — and the version must be PUBLISHED. A draft is still being authored: its
        // provisions can be added to, edited and removed freely, so a contract pointing at one would
        // have its standard terms change underneath it. This is the other half of what makes the
        // publication freeze meaningful — the freeze protects referenced versions, and this ensures a
        // referenced version is a frozen one.
        //
        // Only NEW references are policed (the isNewlySelected gate above), which is what keeps the
        // contracts that already point at now-Draft templates valid. Same shape as R-5's retired types.
        if (row.Status !== 'Published') {
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    'ContractTemplateID',
                    `"${row.Name}" is still a draft, so its clauses can change at any time — a contract cannot ` +
                        `incorporate terms that are not settled. Publish that version first, or choose one that ` +
                        `is already published.`,
                    this.ContractTemplateID,
                    ValidationErrorType.Failure,
                ),
            );
        }
    }

    /**
     * R-4 (certain half) — do not clear `ContractTemplateID` while modifications on THIS contract point
     * at provisions of THAT template.
     *
     * Clearing it would leave every one of those modifications comparing negotiated language against
     * standard language the contract no longer claims to incorporate — the modification rows survive
     * and quietly stop meaning anything, which is the app's worst failure shape.
     *
     * ⚠ THIS IS THE NARROW HALF ON PURPOSE. The full rule is *"reject clearing when a modification
     * ANYWHERE IN THE TREE references that template and it is not reachable elsewhere in the tree"*,
     * which the plan DEFERS to ride with R-14 — not on cost (it is the same walk, and chains are 1–3
     * deep) but on sequencing, so the ancestor walk is written once against a settled tree model. This
     * half covers modifications on this contract only. A modification on a CHILD contract pointing at
     * the template this contract is clearing is **not yet caught here**; the modification-side rule
     * below refuses to SAVE such a row, so the gap is the pre-existing row, not a new one.
     */
    private async refuseClearingAReferencedTemplate(result: ValidationResult): Promise<void> {
        if (!this.IsSaved) return;
        if (this.ContractTemplateID) return;                       // not being cleared
        if (!this.isNewlySelected('ContractTemplateID')) return;    // was already empty

        const field = this.GetFieldByName('ContractTemplateID');
        const previousTemplateID = field?.OldValue ? String(field.OldValue) : null;
        if (!previousTemplateID) return;

        const affected = await this.modificationsAgainstTemplate(previousTemplateID);
        if (affected === 0) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'ContractTemplateID',
                `This contract records ${affected} modification(s) to provisions of the agreement version it ` +
                    `currently references, so the reference cannot be removed — those modifications would be left ` +
                    `describing deviations from terms the contract no longer claims to incorporate. Remove the ` +
                    `modifications first, or point the contract at a different version instead of clearing it.`,
                this.ContractTemplateID,
                ValidationErrorType.Failure,
            ),
        );
    }

    /** How many of THIS contract's modifications cite a provision of the given template. */
    private async modificationsAgainstTemplate(templateID: string): Promise<number> {
        if (!UUID_SHAPE.test(templateID) || !UUID_SHAPE.test(this.ID)) {
            throw new Error(`Refusing to count modifications: '${templateID}' or '${this.ID}' is not a UUID.`);
        }
        const rows = await this.db.ExecuteSQL<{ Hits: number }>(
            `SELECT COUNT(*) AS Hits
               FROM __mj_BizAppsContracts.[ContractTemplateModification] m
               JOIN __mj_BizAppsContracts.[ContractTemplateProvision] p ON p.[ID] = m.[ContractTemplateProvisionID]
              WHERE m.[ContractID] = '${this.ID}' AND p.[ContractTemplateID] = '${templateID}';`,
            undefined,
            { isMutation: false, description: 'R-4 modifications-against-template count' },
            this.ContextCurrentUser,
        );
        return Number(rows?.[0]?.Hits ?? 0);
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
                    `The number comes from the schema-owned SQL sequence seq_ContractNumber (V202608200200); ` +
                    `check that the sequence and the procedure both exist in __mj_BizAppsContracts.`,
            );
        }
        return assigned;
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractEntityServer(): void {
    void ContractEntityServer;
}
