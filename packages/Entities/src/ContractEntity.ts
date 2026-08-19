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

/** The contract form's left-nav sections, in the order the rail shows them (D-17). */
export type ContractFormSection = 'overview' | 'dates' | 'renewal' | 'modifications' | 'documents' | 'lineage';

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
        this.dropSavePopulatedFieldErrors(result);

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

        return result;
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
    private dropSavePopulatedFieldErrors(result: ValidationResult): void {
        if (this.IsSaved) return;
        const kept = result.Errors.filter((error) => (error.Source ?? '') !== 'ContractNumber');
        if (kept.length === result.Errors.length) return;
        result.Errors = kept;
        result.Success = kept.every((error) => error.Type !== ValidationErrorType.Failure);
    }

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

    /**
     * Which left-nav SECTION a validation failure belongs to, so the form can put a red dot on the
     * rail item that owns the field rather than showing a rejection the user has to go hunting for.
     *
     * Metadata-only — it reads the `Source` a `ValidationErrorInfo` already carries. No database, no
     * provider, so the browser gets it free and the server never needs it.
     *
     * The `Modifications[` case is why this is worth having: whole-graph validation attributes child
     * failures positionally (`Modifications[2].ContractTemplateProvisionID`), and without the mapping
     * every one of them would land on the header section, which is the one place the user cannot fix
     * it.
     */
    public static SectionForField(source: string | null | undefined): ContractFormSection {
        const field = (source ?? '').trim();
        if (!field) return 'overview';
        if (/^Modifications\[/i.test(field)) return 'modifications';
        switch (field) {
            case 'EffectiveDate':
            case 'ExecutedDate':
            case 'EndDate':
            case 'TerminatedDate':
                return 'dates';
            case 'AutoRenew':
            case 'RenewalNoticeDays':
            case 'CancellationWindowDays':
            case 'AnnualIncreasePercent':
                return 'renewal';
            case 'HasModifications':
                return 'modifications';
            case 'SigningProviderURL':
                return 'documents';
            case 'ParentContractID':
            case 'SupersededByContractID':
                return 'lineage';
            default:
                return 'overview';
        }
    }

    /** The rail sections currently holding at least one error, for the form's section chrome. */
    public SectionsWithErrors(): ContractFormSection[] {
        const result = this.Validate();
        if (result.Success) return [];
        const sections = new Set<ContractFormSection>();
        for (const e of result.Errors) sections.add(ContractEntity.SectionForField(e.Source));
        return [...sections];
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
