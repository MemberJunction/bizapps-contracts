/**
 * @fileoverview The Contract form's panels — the app's UX, layered onto the GENERATED form.
 *
 * v1 replaced the generated Contract form with a custom one at priority 2. v2 does not: every panel here
 * is a `BaseFormPanel` contribution, so CodeGen can regenerate the form freely and these keep working.
 * That is orders' current direction and the reason the rebuild could delete a whole custom-forms folder.
 *
 * The rail (D-17, `Layout: 'left-nav'`) decides which section the body shows; these panels ARE those
 * sections' content. Slot and `sortKey` place them; `replacesSectionKey` lets the hero stand in for the
 * generic Details block; `relatedEntity` CLAIMS a related list so the baked grid does not double it.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import type { RunViewParams } from '@memberjunction/core';
import { ContractEntity, DeriveContractState, type ContractState } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';
import { MJCModificationEditorComponent } from '../custom/modification-editor.component';

/** CSS class suffix for a state, so the chip's colour is derived rather than switch-cased in a template. */
function stateClass(state: ContractState): string {
    return `mjc-state--${state.toLowerCase()}`;
}

/* ────────────────────────────────────────────────────────────────────────────
 * 1 · Hero — identity, at the top, replacing the generic Details section
 * ──────────────────────────────────────────────────────────────────────────── */

/**
 * The contract, in one line: number, state, type, customer, dates.
 *
 * `replacesSectionKey: 'details'` because a generic field grid of 23 columns answers no question a
 * reader arrives with. The five facts here are the ones they came for.
 *
 * STATE IS DERIVED IN THE BROWSER TOO, from the same module the base view renders its `CASE` from
 * (`DeriveContractState`). The view's `State` column is authoritative and available on a loaded record,
 * but a record being EDITED has unsaved dates — so reading the stored column would show a state that
 * contradicts the form the user is looking at. Deriving from the live field values means the chip tracks
 * the edit, and because both renderings come from one module they cannot disagree about the rule.
 */
@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:hero',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'before-fields',
        sortKey: 100,
        contributionKey: 'header',
        replacesSectionKey: 'details',
    },
})
@Component({
    selector: 'mjc-contract-hero-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <div class="mjc-card">
            <div style="display:flex; align-items:center; gap:var(--mj-space-3); flex-wrap:wrap">
                <strong style="font-size:var(--mj-font-size-lg)">{{ Record.ContractNumber || 'Unnumbered' }}</strong>
                <span class="mjc-state" [class]="'mjc-state ' + StateClass">{{ State }}</span>
                @if (Record.HasModifications) {
                    <span class="mjc-flag" title="This contract deviates from the standard agreement — read the paper">
                        <i class="fa-solid fa-pen-ruler" aria-hidden="true"></i> Modified
                    </span>
                }
                @if (Record.ContractTypeID) {
                    <span class="mjc-pill__count">{{ TypeName }}</span>
                }
            </div>

            <p class="mjc-page__intro" style="margin-top:var(--mj-space-2)">
                {{ CustomerName || 'No customer organisation set' }}
                @if (Record.EffectiveDate) { · in force from {{ Record.EffectiveDate | date: 'mediumDate' }} }
                @if (Record.EndDate) { · through {{ Record.EndDate | date: 'mediumDate' }} }
            </p>

            @if (!Record.ContractNumber) {
                <p class="mjc-page__intro">
                    The number is minted on first save, under a lock, so it cannot collide with another
                    contract created at the same moment.
                </p>
            }
        </div>
    `,
})
export class MJCContractHeroPanel extends BaseFormPanel<ContractEntity> {
    /** Derived live from the record's current field values — see the class comment. */
    public get State(): ContractState {
        return DeriveContractState({
            TerminatedDate: this.Record?.TerminatedDate ?? null,
            SupersededByContractID: this.Record?.SupersededByContractID ?? null,
            EndDate: this.Record?.EndDate ?? null,
            EffectiveDate: this.Record?.EffectiveDate ?? null,
            ExecutedDate: this.Record?.ExecutedDate ?? null,
        });
    }

    public get StateClass(): string {
        return stateClass(this.State);
    }

    /**
     * Names, not ids — the base view's joined columns (D-23), reached through the entity's TYPED members.
     *
     * CodeGen emits a getter for every view column including the virtual derived ones, so `.Get('…')`
     * would be substituting a string lookup for a typed property that exists — which the conventions
     * table forbids (D-26's typed-entities row). The read costs nothing either way; the difference is
     * that a renamed column breaks the build here instead of returning undefined at runtime.
     */
    public get TypeName(): string {
        return this.Record?.ContractType ?? '';
    }

    public get CustomerName(): string {
        return this.Record?.CustomerOrganization ?? '';
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 2 · Renewal terms — as the paper states them
 * ──────────────────────────────────────────────────────────────────────────── */

/**
 * Auto-renewal, notice periods and the annual increase.
 *
 * LABELLED "as stated in the agreement", and that wording is a decision (ERD §4.3). These columns record
 * what the DOCUMENT says; they are not the operational setting that makes anything renew. Orders'
 * subscription is what actually renews. Without the label, a reader reasonably assumes ticking
 * `AutoRenew` here changes behaviour somewhere — it does not, and discovering that after a renewal was
 * missed is the worst way to learn it.
 *
 * The derived deadline is shown beside the raw day-count because the day-count is not the question
 * anyone has: "60 days" means nothing until it is a date on a calendar.
 */
@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:renewal-terms',
    skipNullKeyWarning: true,
    metadata: { entity: MJC_ENTITIES.Contract, slot: 'after-fields', sortKey: 80, contributionKey: 'renewal' },
})
@Component({
    selector: 'mjc-contract-renewal-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <div class="mjc-card">
            <h3 class="mjc-card__title">Renewal terms — as stated in the agreement</h3>
            <p class="mjc-page__intro">
                What the document says about renewing. These fields are a <strong>record</strong>, not a
                setting: nothing here causes a renewal. The subscription in orders is what renews.
            </p>

            <ul>
                <li>
                    <strong>{{ Record.AutoRenew ? 'Auto-renews' : 'Does not auto-renew' }}</strong>
                    @if (!Record.AutoRenew) { — someone must act for this to continue }
                </li>
                @if (Record.RenewalNoticeDays) {
                    <li>
                        Notice we owe: <strong>{{ Record.RenewalNoticeDays }} days</strong>
                        @if (NoticeDeadline) { — by {{ NoticeDeadline | date: 'mediumDate' }} }
                    </li>
                }
                @if (Record.CancellationWindowDays) {
                    <li>
                        Customer cancellation window: <strong>{{ Record.CancellationWindowDays }} days</strong>
                        @if (InCancellationWindow) { — <span class="mjc-flag">open now</span> }
                    </li>
                }
                @if (Record.AnnualIncreasePercent) {
                    <li>Annual increase: <strong>{{ Record.AnnualIncreasePercent }}%</strong></li>
                }
            </ul>

            @if (!Record.RenewalNoticeDays && !Record.CancellationWindowDays && !Record.AnnualIncreasePercent) {
                <p class="mjc-empty">
                    No renewal terms recorded. If the agreement states any, recording them is what puts
                    this contract on the renewals watchlist.
                </p>
            }
        </div>
    `,
})
export class MJCContractRenewalPanel extends BaseFormPanel<ContractEntity> {
    /**
     * The derived columns are read from the record where present rather than recomputed.
     *
     * Unlike `State`, these do not need to track an unsaved edit: a notice deadline the user is
     * mid-way through changing is not information anyone wants. So the authoritative view column is the
     * right source, and `null` when the record was not loaded through the view.
     */
    public get NoticeDeadline(): Date | null {
        return this.Record?.RenewalNoticeDeadline ?? null;
    }

    public get InCancellationWindow(): boolean {
        return this.Record?.IsInCancellationWindow === true;
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 3 · Modifications — the D-15 centrepiece
 * ──────────────────────────────────────────────────────────────────────────── */

/**
 * Hosts the shared editor inline, claiming the related list so the stock grid does not double it.
 *
 * `relatedEntity` is what does the claiming: the form's baked grid for Contract Template Modifications
 * disappears because this panel says it owns that relationship. Without the claim there would be two
 * places to edit the same rows, one of which saves independently — which is precisely the split D-15
 * removed.
 */
@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:modifications',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'after-related',
        sortKey: 90,
        contributionKey: 'modifications',
        relatedEntity: MJC_ENTITIES.ContractTemplateModification,
    },
})
@Component({
    selector: 'mjc-contract-modifications-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule, MJCModificationEditorComponent],
    template: `
        <div class="mjc-card">
            <h3 class="mjc-card__title">Modifications to the standard agreement</h3>
            <p class="mjc-page__intro">
                Each row is one provision this contract changed, with the standard clause beside the
                negotiated language. Changes here save <strong>with the contract</strong> — one
                transaction, so the header and its modifications can never disagree.
            </p>
            <mjc-modification-editor
                [Record]="Record"
                [EditMode]="EditMode"
                [Provider]="FormComponent.ProviderToUse"
                (Changed)="onChanged()" />
        </div>
    `,
})
export class MJCContractModificationsPanel extends BaseFormPanel<ContractEntity> {
    private readonly cdr = inject(ChangeDetectorRef);

    /**
     * Tell the host form something changed, so its Save button enables.
     *
     * The editor mutates entity fields directly, which MJ tracks as dirty on the record — but the
     * FORM's toolbar reads its own dirty state, and a collection mutation is not a field change on the
     * header. Nudging change detection is what makes the toolbar notice.
     */
    protected onChanged(): void {
        this.cdr.detectChanges();
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 4 · Lineage — change orders and supersession, read-only
 * ──────────────────────────────────────────────────────────────────────────── */

/**
 * What this contract amends, what amends it, and what replaced it.
 *
 * READ-ONLY on purpose. A change order is a first-class contract with its own number, dates and paper
 * (§6.1) — it is created as a contract, not as a child of this one, which is why `ParentContractID` was
 * deliberately NOT declared as a related-record collection: no `OnRemove` mode is right, since deleting
 * destroys signed paper and orphaning erases lineage.
 *
 * Claims the `ParentContractID` self-relationship so the baked grid does not appear beside this.
 */
@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:lineage',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'after-related',
        sortKey: 70,
        contributionKey: 'lineage',
        relatedEntity: MJC_ENTITIES.Contract,
        relatedJoinField: 'ParentContractID',
    },
})
@Component({
    selector: 'mjc-contract-lineage-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <div class="mjc-card">
            <h3 class="mjc-card__title">Lineage</h3>

            @if (ParentName) {
                <p class="mjc-page__intro">
                    This is a change order to <strong>{{ ParentName }}</strong>.
                </p>
            }
            @if (SupersededByID) {
                <p class="mjc-page__intro">
                    <span class="mjc-flag"><i class="fa-solid fa-arrow-right" aria-hidden="true"></i>
                    Replaced by newer paper</span> — this agreement is superseded, so its terms no longer
                    govern.
                </p>
            }
            @if (!ParentName && !SupersededByID) {
                <p class="mjc-page__intro">
                    A standalone agreement: nothing above it, and nothing has replaced it.
                </p>
            }

            <h3 class="mjc-card__title" style="margin-top:var(--mj-space-4)">Change orders to this contract</h3>
            <mj-explorer-entity-data-grid [Params]="ChildParams" [ShowToolbar]="false" [NavigateOnDoubleClick]="true" />
        </div>
    `,
})
export class MJCContractLineagePanel extends BaseFormPanel<ContractEntity> {
    public get ParentName(): string {
        return this.Record?.ParentContract ?? '';
    }

    public get SupersededByID(): string {
        return String(this.Record?.SupersededByContractID ?? '');
    }

    /** Contracts naming THIS one as their parent — the change orders. */
    public get ChildParams(): RunViewParams | null {
        const id = this.Record?.ID;
        if (!id) return null;
        return {
            EntityName: MJC_ENTITIES.Contract,
            ExtraFilter: `ParentContractID = '${id}'`,
            OrderBy: 'EffectiveDate ASC',
        };
    }
}
