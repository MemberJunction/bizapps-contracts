/**
 * @fileoverview `ContractEntity` — the SHARED subclass. Browser and server both load it, so every
 * rule here runs in both places: the user sees a refusal before the round trip, and the server
 * enforces the same rule regardless of what the client did.
 *
 * IT DOES NOT OVERRIDE `Save()`. A shared class that persisted would have to work on a provider
 * that cannot open a transaction. Persistence stays with `ContractEntityServer`; the browser ships
 * the whole graph in one `MJ.SaveEntityGraph` call and the server runs the same executor
 * (plan §6.3). Same split as orders' `OrderHeaderEntity`.
 *
 * WHAT IS DELIBERATELY NOT HERE:
 *   · No `NewRecord()` status default. An earlier draft seeded `Status = 'Draft'`; D-19 removed the
 *     column. A new contract reads as `Draft` because the layered base view derives it from the
 *     absence of dates (ERD §4.5) — there is nothing to set, and nothing that can drift.
 *   · No `DeclareRelatedRecords`. CodeGen emits `Modifications` onto the generated base class from
 *     the `RelatedRecordCollection` metadata — edit that row, not this file.
 *   · No provision/template consistency check. It needs a cross-entity read, so it is server-side
 *     only (`ContractTemplateModificationEntityServer`); the picker prevents it in the UI.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import { BaseEntity, ValidationErrorInfo, ValidationErrorType, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractEntity } from './generated/entity_subclasses';

/**
 * Do two contracts sit at the SAME LEVEL of the tree — i.e. may one supersede the other?
 *
 * The pure half of the same-level supersession rule (ruled by Marcelo, 2026-08-20). A free function
 * taking plain values for the same reason `FindDuplicateProvisionIDs` is one: the decision has three
 * cases and two of them are easy to get backwards, and none of them needs a database to check.
 *
 *   · **both NULL → same level.** Two top-level agreements. This is the common case and the one a
 *     naive `a === b` on nullable values gets right by accident and a SQL `=` gets WRONG — hence the
 *     caller's `IS NULL` branch when it builds a filter.
 *   · **one NULL, one set → DIFFERENT levels.** A change order claiming to replace a whole order form.
 *     This is the case the rule exists to refuse.
 *   · **both set → compare case-insensitively.** MJ returns UUIDs in either casing depending on how
 *     the row was loaded, so a case-sensitive compare would call two siblings different levels and
 *     refuse a legitimate re-papering.
 *
 * Note this is deliberately NOT "root only": two siblings under one parent are the same level, which
 * is what lets a change order supersede another change order under the same agreement.
 */
export function IsSameContractLevel(myParentID: string | null | undefined, theirParentID: string | null | undefined): boolean {
    const a = myParentID ?? null;
    const b = theirParentID ?? null;
    if (a === null && b === null) return true;
    if (a === null || b === null) return false;
    return a.toLowerCase() === b.toLowerCase();
}

/**
 * Which provision IDs appear more than once — the pure half of R-10's staged-rows rule.
 *
 * A free function taking plain values so the counting is testable without a provider or a
 * `RelatedRecordCollection`, the same reason `ValidateValueLists` and `IsNewlySelected` are free
 * functions. Every subtlety worth getting right is in here rather than in the caller:
 *
 *   · **case-insensitive** — MJ returns UUIDs in either casing depending on how the row was loaded, so
 *     a case-sensitive compare would miss a duplicate while appearing to check for one;
 *   · **blanks are skipped**, not grouped — several rows with no provision chosen yet are an
 *     incomplete edit, not "the same provision twice", and reporting them as duplicates would refuse a
 *     save the user is still composing;
 *   · **each duplicated ID is reported once**, however many times it appears, so three copies of one
 *     provision is one problem rather than two.
 */
export function FindDuplicateProvisionIDs(provisionIDs: readonly unknown[]): string[] {
    const counts = new Map<string, number>();
    const duplicates: string[] = [];
    for (const raw of provisionIDs) {
        const id = String(raw ?? '').trim().toLowerCase();
        if (!id) continue;
        const next = (counts.get(id) ?? 0) + 1;
        counts.set(id, next);
        if (next === 2) duplicates.push(id);
    }
    return duplicates;
}

/**
 * R-12 — `CK_Contract_Dates` as a predicate: is this pair of dates definitely out of order?
 *
 * MIRRORS THE CONSTRAINT EXACTLY, which is `EndDate IS NULL OR EffectiveDate IS NULL OR EndDate >=
 * EffectiveDate`. So this returns true ONLY when both dates are readable and the end really does fall
 * before the start. Three consequences worth stating, because each is a way the obvious version would
 * be wrong:
 *
 *   * EQUAL DATES PASS. A contract that starts and ends on the same day is a real one-day agreement.
 *     Refusing it would reject rows the database accepts — worse than the error being replaced.
 *   * EITHER MISSING PASSES. Half-filled dates are the normal state of a form mid-edit, and the
 *     constraint itself allows them.
 *   * UNREADABLE PASSES. Typed `Date | null`, but a form binding can put a string here, and comparing
 *     a string to a Date compares nonsense rather than throwing. Anything that will not parse is
 *     treated as "not yet known" rather than as an error on a field still being typed.
 *
 * Exported and pure so it can be asserted directly, the way `IsSameContractLevel` above is — not
 * restated in a test, which is a copy that can drift from the rule it claims to check.
 */
export function IsEndBeforeEffective(effectiveDate: unknown, endDate: unknown): boolean {
    const at = (v: unknown): number | null => {
        if (v === null || v === undefined || v === '') return null;
        const t = v instanceof Date ? v.getTime() : new Date(v as string).getTime();
        return Number.isFinite(t) ? t : null;
    };
    const effective = at(effectiveDate);
    const end = at(endDate);
    if (effective === null || end === null) return false;
    return end < effective;
}

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contracts')
export class ContractEntity extends mjBizAppsContractsContractEntity {
    /**
     * `HasModifications` is MONOTONIC: it must be true when modification rows exist, and it is never
     * cleared automatically.
     *
     * WHY THE FLAG EXISTS AT ALL, given that the rows are right there to count. Because its job is to
     * say "go read the PDF" *before* anyone has recorded the modifications. A derived flag would read
     * false for every contract nobody has processed yet — which is exactly the population finance
     * needs to be warned about. So a person asserts it, and this rule enforces the one direction that
     * cannot be wrong: rows imply the flag.
     *
     * The other direction is deliberately unenforced. Clearing the flag after deleting every
     * modification would be defensible, but it would also let a bulk delete quietly erase the warning
     * on a contract whose paper really was negotiated. A human sets it false, or it stays true.
     */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.refuseReservedContractNumber(result);

        if (this.HasModifications === false && this.modificationsKnownToExist()) {
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    'HasModifications',
                    `Contract ${this.ContractNumber ?? ''} records ${this.Modifications.Count} modification(s) to the ` +
                        `standard agreement, so it cannot be marked as unmodified. Remove the modifications first if ` +
                        `the agreement really is standard.`,
                    this.HasModifications,
                    ValidationErrorType.Failure,
                ),
            );
        }

        this.refuseDuplicateStagedModifications(result);
        this.refuseEndBeforeEffective(result);

        return result;
    }

    /**
     * R-12 — `CK_Contract_Dates` in words, before the database says it in SQL.
     *
     * The constraint has always existed, so the data was never at risk; what the user got was the raw
     * violation text naming a constraint and no field. This runs in the browser AND on the server
     * (`Validate()` is shared), so the message arrives on the End Date field before a save is attempted.
     *
     * THE PREDICATE MIRRORS THE CONSTRAINT EXACTLY — `EndDate IS NULL OR EffectiveDate IS NULL OR
     * EndDate >= EffectiveDate`. Both-null and either-null pass, and equal dates pass: a contract that
     * starts and ends on the same day is a real one-day agreement, and refusing it here would reject
     * rows the database accepts, which is worse than the error it replaces.
     *
     * The constraint STAYS. This is the friendly path, not the enforcement: a write that reaches the
     * table by some other route still meets the check.
     */
    private refuseEndBeforeEffective(result: ValidationResult): void {
        if (!IsEndBeforeEffective(this.EffectiveDate, this.EndDate)) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'EndDate',
                'End Date must be on or after the Effective Date.',
                this.EndDate,
                ValidationErrorType.Failure,
            ),
        );
    }

    /**
     * R-10 — two modifications of the SAME provision, caught among the rows in hand.
     *
     * `UQ_ContractTemplateModification_Contract_Provision` is the floor, and it refuses this as a raw
     * unique-index violation naming no field. This catches the case the browser can see for free: the
     * collection is staged right here during a graph save, so a duplicate among those rows needs **no
     * query at all**. The saved-rows half (a staged row colliding with one already in the table) needs
     * a read and lives on the server subclass.
     *
     * WHY THIS IS ON `ContractEntity` AND NOT ON THE MODIFICATION. The item says "rule on the shared
     * subclass" without saying which; only the CONTRACT holds the sibling rows. A modification cannot
     * see its siblings, so the same rule written there could only ever be the one-query server version.
     *
     * Case-insensitive on the FK because MJ returns UUIDs in either casing, and a case-sensitive
     * comparison would miss a duplicate while appearing to check for one.
     */
    private refuseDuplicateStagedModifications(result: ValidationResult): void {
        const provisionIDs = this.Modifications.Items.map((mod) => mod.Get('ContractTemplateProvisionID') as unknown);
        const duplicates = FindDuplicateProvisionIDs(provisionIDs);
        if (duplicates.length === 0) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'Modifications',
                `${duplicates.length === 1 ? 'A provision is' : `${duplicates.length} provisions are`} modified more ` +
                    `than once on this contract. A contract records ONE negotiated wording per standard clause — ` +
                    `combine the duplicates into a single modification.`,
                duplicates.length,
                ValidationErrorType.Failure,
            ),
        );
    }

    /**
     * Drop generated NOT-NULL errors for fields the SAVE ITSELF fills in.
     *
     * `ContractNumber` is NOT NULL in metadata and is minted by `ContractEntityServer.Save()` from the
     * sequence counter, under a lock. So on a record that has not been saved yet it is legitimately
     * empty — and the generated check reported "Contract Number cannot be null", which the form
     * surfaced as a refusal.
     *
     * That made the create path IMPOSSIBLE: every attempt to save a new contract through the UI was
     * rejected for a field the user cannot fill and the server was about to. Measured in a browser, not
     * reasoned about — the form refused with four errors and only three of them were real.
     *
     * After the first save the value exists, so an empty `ContractNumber` on a SAVED record is a
     * genuine failure and is kept. That asymmetry is the whole rule, and it is why this cannot simply
     * be "ignore ContractNumber".
     *
     * Same shape as orders' `IsSavePopulatedFieldError`, narrowed: contracts has exactly one
     * save-populated field, because nothing here prepares child rows the way orders stamps line
     * numbers and prices.
     */
    /**
     * A hand-typed contract number may not look like a system-assigned one.
     *
     * WHY THIS REPLACED AN ERROR FILTER. This method sits where
     * `dropSavePopulatedFieldErrors` used to: that one searched the validation result for
     * `Source === 'ContractNumber'` and deleted it, so a new contract could be saved despite MJ
     * correctly reporting a NOT NULL field as null. Deleting a real error because we believe
     * something later will fix it is the same defect as blessing a self-reference because a
     * generated validator "has it" — it converts an invalid state into a silent success the moment
     * the belief stops holding. The cause is now removed instead: `V202608211000` gives the column a
     * DEFAULT, which is how MJ models "NOT NULL but supplied on insert", so the error is never raised.
     *
     * WHAT THIS RULE IS. `Save()` honours a number the user typed, which is the right behaviour —
     * migrated paper has its own references. But `CTR-<digits>` is the shape the sequence mints, so a
     * hand-typed one can collide with a value the sequence has not reached yet. The collision would
     * surface months later, on somebody else's save, as a unique-index violation with no explanation.
     * So the namespaces are kept apart: type your own reference, or leave it blank.
     *
     * Note `\d+`, not `\d{6}`: `FORMAT(n,'D6')` pads to a MINIMUM of six digits and keeps growing
     * past a million, so a seven-digit hand-typed number is just as collidable.
     *
     * ONLY ON AN UNSAVED RECORD, and only when the system did not assign it. An existing contract's
     * stored number obviously matches the pattern and must not be retro-refused; and
     * `ContractEntityServer.Save()` mints INTO this field before calling `super.Save()`, which
     * validates — so without `NumberWasSystemAssigned` this rule would refuse the very numbers it is
     * meant to protect.
     */
    private refuseReservedContractNumber(result: ValidationResult): void {
        if (this.IsSaved || this.NumberWasSystemAssigned) return;
        const typed = (this.ContractNumber ?? '').trim();
        if (!typed || !/^CTR-\d+$/i.test(typed)) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'ContractNumber',
                `The CTR-#### pattern is reserved for contract numbers the system assigns, so "${typed}" cannot be ` +
                    `entered by hand — a number the sequence has not reached yet would collide with it later, on ` +
                    `somebody else's save. Leave this blank to have one assigned, or enter your own reference in a ` +
                    `different format.`,
                this.ContractNumber,
                ValidationErrorType.Failure,
            ),
        );
    }

    /**
     * Set by the server subclass when IT minted the number, so `refuseReservedContractNumber` can tell
     * a system-assigned `CTR-…` from a hand-typed one. Protected rather than public: nothing outside
     * the entity has any business claiming a number was system-assigned.
     */
    protected NumberWasSystemAssigned = false;

    /**
     * Whether modification rows are KNOWN to exist — as opposed to merely not known to be absent.
     *
     * The distinction is the whole subtlety of validating a collection in the browser. `Count > 0` is
     * unambiguous: rows are staged or loaded, so they exist. `Count === 0` is ambiguous on a SAVED
     * record whose collection was never loaded — empty there means *unknown*, and treating it as zero
     * would let the flag be cleared on a contract whose modifications are sitting in the table.
     *
     * This method therefore only ever returns true on certainty. The unknown case is settled
     * server-side, where a read is cheap and authoritative. Note `IsLoaded` alone is not the test:
     * `Create()` does not mark a collection loaded, so a contract composed in the browser has
     * modifications with `IsLoaded === false`. Orders' guard, same reasoning.
     */
    private modificationsKnownToExist(): boolean {
        return this.Modifications.Count > 0;
    }

    /**
     * Re-paper this contract: point it at the agreement that REPLACES it.
     *
     * ONE WRITE, NOT TWO. An earlier design also set `Status = 'Superseded'`; D-19 / R-18 removed the
     * column precisely because the successor FK *is* the superseded state — the base view derives it
     * (ERD §4.5), so there is no second fact that can disagree. The tautological
     * `CK_Contract_SupersededHasSuccessor` constraint went with it.
     *
     * The successor is NOT saved here and neither is this record. The caller saves — normally as one
     * graph — which keeps re-papering atomic: either both contracts reflect the supersession or
     * neither does. Mirrors orders' `Confirm()`, which is likewise an intent-setter, not a persister.
     */
    public Supersede(successor: ContractEntity): void {
        if (!successor?.ID) {
            throw new Error(
                `Cannot supersede contract ${this.ContractNumber ?? this.ID}: the replacement contract must be ` +
                    `saved first, so that its ID exists to point at.`,
            );
        }
        if (successor.ID === this.ID) {
            throw new Error(
                `Contract ${this.ContractNumber ?? this.ID} cannot supersede itself. ` +
                    `(CK_Contract_SupersededNotSelf would refuse the save regardless.)`,
            );
        }
        this.SupersededByContractID = successor.ID;
    }

}

/**
 * Anti-tree-shake anchor. Importing this module is what fires `@RegisterClass`; a production build
 * can drop an import whose class is never referenced, and a dropped registration means every rule
 * above silently stops existing.
 */
export function LoadContractEntity(): void {
    void ContractEntity;
}
