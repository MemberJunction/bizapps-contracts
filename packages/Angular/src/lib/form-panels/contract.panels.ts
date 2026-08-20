/**
 * @fileoverview The Contract form's panels — built to `mockups-v2/contract-form.html`.
 *
 * v1 replaced the generated Contract form outright. v2 does not: every panel here is a `BaseFormPanel`
 * contribution, so CodeGen can regenerate the form freely and these keep working.
 *
 * THREE THINGS AN EARLIER VERSION OF THIS FILE GOT WRONG, all visible on screen and none in the source:
 *
 *  1. **The panels were not `<mj-collapsible-panel>`s.** They were hand-rolled `<div class="card">`s, so
 *     they had none of MJ's panel chrome — hence text with no card behind it, cards touching each other,
 *     and content overflowing. The one panel that looked right (Documents) was the one panel built on
 *     the real component.
 *  2a. **`contributionKey` MUST EQUAL the panel's own `SectionKey`, and must DIFFER from
 *      `replacesSectionKey`.** This is the rule that took longest to find, because breaking it fails
 *      two different ways. The container resolves contribution chrome by `contributionKey`
 *      (`contributionRailKey`) but builds the rail's groups from the rendered panels' `SectionKey`
 *      (`BuildDefaultChromeSpec` over `visiblePanels`) — so if they differ, the `Primary` inclusion is
 *      computed and then never attaches to any rendered panel, and the panel folds into Details.
 *      And if the panel's own `SectionKey` equals its `replacesSectionKey`, the replacement adds that
 *      key to `HiddenSectionKeys`, which filters out the panel ITSELF — the section disappeared from
 *      the form entirely, taking the dates and renewal fields with it. Both were live here at once.
 *
 *  2. **No `inclusion: 'Primary'`.** Under `Layout: 'left-nav'` the forms guide is explicit: *"Field
 *     panels collapse into one **Details** item"*, and named rail entries come from Primary
 *     contributions. Without it, every panel folded into `Details` and the form had exactly one section
 *     — the "everything in one page" problem.
 *  3. **The hero was one line.** The mockup's hero is identity + chips + a meta row + a five-stat strip,
 *     and the stats are the part a reader actually scans.
 *
 * The hero lives in `before-fields` with NO `replacesSectionKey`: the mockup keeps the generated fields
 * as their own Overview section, and content in `before-fields` stays put across rail sections, which is
 * what makes the hero persistent chrome rather than a section.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import { ContractEntity, type ContractState } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';
import { MJCModificationEditorComponent } from '../custom/modification-editor.component';

/** Chip variant per lifecycle state — colour carries meaning, so each state gets a considered one. */
function chipClassFor(state: ContractState): string {
    switch (state) {
        case 'Active':      return 'mjc-chip--ok';
        case 'Executed':    return 'mjc-chip--info';   // signed, waiting — good news, not yet in force
        case 'Terminated':  return 'mjc-chip--error';
        case 'Expired':     return 'mjc-chip--muted';
        case 'Superseded':  return 'mjc-chip--muted';
        default:            return 'mjc-chip--muted';  // Draft
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 1 · Hero — persistent identity, above the rail
 * ──────────────────────────────────────────────────────────────────────────── */

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:hero',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'before-fields',
        sortKey: 100,
        contributionKey: 'header',
    },
})
@Component({
    selector: 'mjc-contract-hero-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <div class="mjc-hero">
            <div class="mjc-hero__identity">
                <div class="mjc-hero__avatar"><i class="fa-solid fa-file-signature" aria-hidden="true"></i></div>
                <div class="mjc-hero__copy">
                    <div class="mjc-hero__title-row">
                        <h1 class="mjc-hero__title">{{ Title }}</h1>
                        <span class="mjc-chip" [class]="'mjc-chip ' + StateChipClass">{{ State }}</span>
                        @if (TypeName) { <span class="mjc-chip mjc-chip--info">{{ TypeName }}</span> }
                        @if (Record.HasModifications) {
                            <span class="mjc-chip mjc-chip--warn"
                                  title="This contract deviates from the standard agreement — read the paper">
                                <i class="fa-solid fa-triangle-exclamation" aria-hidden="true"></i> Agreement modified
                            </span>
                        }
                        @if (IsAwaitingDocument) {
                            <span class="mjc-chip mjc-chip--warn"
                                  title="This contract type expects an executed document and none is attached">
                                <i class="fa-solid fa-file-circle-question" aria-hidden="true"></i> Awaiting document
                            </span>
                        }
                    </div>
                    <div class="mjc-hero__meta">
                        <span class="mjc-mono">{{ Record.ContractNumber || 'Unnumbered' }}</span>
                        <span>Customer: <strong>{{ CustomerName || '—' }}</strong></span>
                        <span>Selling: <strong>{{ CompanyName || '—' }}</strong></span>
                        @if (ContactName) { <span>Contact: <strong>{{ ContactName }}</strong></span> }
                    </div>
                </div>
            </div>

            <div class="mjc-hero__stats">
                <div class="mjc-stat">
                    <span class="mjc-stat__label">Executed</span>
                    <span class="mjc-stat__value">{{ (Record.ExecutedDate | date: 'd MMM y') || '—' }}</span>
                    @if (!Record.ExecutedDate) { <span class="mjc-stat__sub">not signed yet</span> }
                </div>
                <div class="mjc-stat">
                    <span class="mjc-stat__label">Effective</span>
                    <span class="mjc-stat__value">{{ (Record.EffectiveDate | date: 'd MMM y') || '—' }}</span>
                </div>
                <div class="mjc-stat">
                    <span class="mjc-stat__label">Term ends</span>
                    <span class="mjc-stat__value">{{ (Record.EndDate | date: 'd MMM y') || '—' }}</span>
                    @if (DaysToEnd !== null) { <span class="mjc-stat__sub">{{ EndsInText }}</span> }
                </div>
                <div class="mjc-stat">
                    <span class="mjc-stat__label">Agreement</span>
                    <span class="mjc-stat__value">{{ TemplateName || '—' }}</span>
                    @if (!TemplateName) { <span class="mjc-stat__sub">no standard terms referenced</span> }
                </div>
                <div class="mjc-stat">
                    <span class="mjc-stat__label">Created by</span>
                    <span class="mjc-stat__value">{{ CreatingEntityName || '—' }}</span>
                    @if (!CreatingEntityName) { <span class="mjc-stat__sub">entered directly</span> }
                </div>
            </div>

            @if (!Record.ContractNumber) {
                <div class="mjc-flag">
                    The contract number is minted on first save, from a counter taken under a lock — so it
                    cannot collide with another contract created at the same moment.
                </div>
            }
        </div>
    `,
})
export class MJCContractHeroPanel extends BaseFormPanel<ContractEntity> {
    /**
     * The human name for this agreement: its description, falling back to the number.
     *
     * The mockup's hero title is a descriptive line ("Sidecar — Learning Hub, 2-year"), not the contract
     * number — the number is already in the meta row directly beneath, and repeating it as the headline
     * wastes the one place a reader looks first.
     */
    public get Title(): string {
        return this.Record?.Description?.trim() || this.Record?.ContractNumber || 'New contract';
    }

    /**
     * READ from the view's derived column. Application code does not re-derive state (Marcelo,
     * 2026-08-19) — the view is the single authority, and `DeriveContractState()` is now for tests
     * and the equivalence harness only.
     *
     * This panel used to re-derive it in the browser so the chip tracked UNSAVED date edits. That
     * bought a live-updating chip and cost the thing worth more: a second implementation that could
     * disagree with the view, which is exactly what happened — the two diverged on the termination
     * boundary and no test could see it. The chip now shows what is PERSISTED, which is also the
     * more honest claim: a state chip that reacts to an unsaved date is asserting something no
     * query would agree with until the record is saved.
     *
     * A never-saved record has no column value, and `Draft` is not a guess there — it is what the
     * view's own `ELSE` branch returns for a row with no dates, which is every new contract.
     */
    public get State(): ContractState {
        return (this.Record?.State as ContractState) || 'Draft';
    }

    public get StateChipClass(): string { return chipClassFor(this.State); }

    /* Joined name columns off the base view, through typed members (D-23 / D-26). */
    public get TypeName(): string { return this.Record?.ContractType ?? ''; }
    public get CustomerName(): string { return this.Record?.CustomerOrganization ?? ''; }
    public get CompanyName(): string { return this.Record?.Company ?? ''; }
    public get ContactName(): string { return this.Record?.PrimaryContactPerson ?? ''; }
    public get TemplateName(): string { return this.Record?.ContractTemplate ?? ''; }
    public get CreatingEntityName(): string { return this.Record?.CreatingEntity ?? ''; }
    public get IsAwaitingDocument(): boolean { return this.Record?.IsAwaitingDocument === true; }
    public get DaysToEnd(): number | null { return this.Record?.DaysToEnd ?? null; }

    /** "in 16 months" reads better than "in 487 days" past a couple of months — the mockup's phrasing. */
    public get EndsInText(): string {
        const d = this.DaysToEnd;
        if (d === null) return '';
        if (d < 0) return `ended ${Math.abs(d)} days ago`;
        if (d === 0) return 'ends today';
        if (d < 60) return `in ${d} days`;
        const months = Math.round(d / 30);
        return `in ${months} month${months === 1 ? '' : 's'}`;
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 2 · Renewal terms — a real rail section
 * ──────────────────────────────────────────────────────────────────────────── */

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:renewal-terms',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'after-fields',
        sortKey: 85,
        contributionKey: 'renewal',
        // REPLACES the generated `renewalTerms` section rather than sitting beside it. Two reasons, and
        // the second is the one that makes the rail work:
        //
        //  1. Without it the four fields render TWICE — once in the generated field list and once here.
        //  2. Under `left-nav`, MJ folds every *leftover* field panel into a single `Details` rail item.
        //     A section that a Primary contribution REPLACES is no longer leftover, so it earns its own
        //     rail entry. That is the mechanism behind the mockup's rail, and without the replacement
        //     this panel folded into Details and the form read as one long page.
        replacesSectionKey: 'renewalTerms',
        // NO `inclusion: 'Primary'` — and that omission is what puts Details FIRST.
        //
        // The rail is assembled as fixed BANDS, not from a sortable flat list:
        // `spec.Groups = [...leads, ...details, ...related, ...more]`
        // (`resolve-form-chrome.ts:761`). A panel joins the LEAD band purely by declaring
        // `inclusion: 'Primary'` (`isLeadContribution`, `:313`), and every lead therefore renders
        // BEFORE Details. With all of these marked Primary, Details sat fourth.
        //
        // Reordering `spec.Groups` from a `BaseFormPolicy.DecorateChrome` cannot fix that:
        // `StabilizeFirstClassGroupOrder` re-imposes the bands, and its own comment says it moves
        // groups "into the lead band before Details" — so the reorder is silently undone. Only a
        // user's drag order (`OrderChromeGroups`) outranks the bands, and that is a per-user
        // preference an app cannot ship.
        //
        // Dropping Primary moves these into the `related` band, which sorts DESCENDING by sortKey
        // (`:753`), so the numbers below are the running order after Details.
    },
})
@Component({
    selector: 'mjc-contract-renewal-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    template: `
        <mj-collapsible-panel
            SectionKey="renewal"
            SectionName="Renewal terms"
            Icon="fa-solid fa-calendar-days"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            <div class="mjc-body">
                <span class="mjc-chip mjc-chip--muted">as stated in the agreement</span>

                <div class="mjc-fields">
                    <div class="mjc-field">
                        <label>Auto-renews</label>
                        @if (EditMode) {
                            <select [ngModel]="Record.AutoRenew" (ngModelChange)="Set('AutoRenew', $event)"
                                    aria-label="Does this agreement auto-renew?">
                                <option [ngValue]="true">Yes</option>
                                <option [ngValue]="false">No</option>
                            </select>
                        } @else {
                            <div class="mjc-val">{{ Record.AutoRenew ? 'Yes' : 'No' }}</div>
                        }
                        @if (!Record.AutoRenew) {
                            <div class="mjc-hint">someone must act for this to continue</div>
                        }
                    </div>
                    <div class="mjc-field">
                        <label>Renewal notice we owe</label>
                        @if (EditMode) {
                            <input type="number" min="0" style="width:100%" [ngModel]="Record.RenewalNoticeDays"
                                   (ngModelChange)="Set('RenewalNoticeDays', $event)" aria-label="Renewal notice days" />
                        } @else {
                            <div class="mjc-val">{{ Record.RenewalNoticeDays ? Record.RenewalNoticeDays + ' days' : '—' }}</div>
                        }
                        @if (NoticeDeadline) {
                            <div class="mjc-hint">deadline: {{ NoticeDeadline | date: 'd MMM y' }}</div>
                        }
                    </div>
                    <div class="mjc-field">
                        <label>Notice to cancel</label>
                        @if (EditMode) {
                            <input type="number" min="0" style="width:100%" [ngModel]="Record.CancellationWindowDays"
                                   (ngModelChange)="Set('CancellationWindowDays', $event)" aria-label="Cancellation window days" />
                        } @else {
                            <div class="mjc-val">{{ Record.CancellationWindowDays ? Record.CancellationWindowDays + ' days' : '—' }}</div>
                        }
                        @if (InCancellationWindow) { <div class="mjc-hint">the window is open now</div> }
                    </div>
                    <div class="mjc-field">
                        <label>Annual increase</label>
                        @if (EditMode) {
                            <input type="number" min="0" step="0.01" style="width:100%" [ngModel]="Record.AnnualIncreasePercent"
                                   (ngModelChange)="Set('AnnualIncreasePercent', $event)" aria-label="Annual increase percent" />
                        } @else {
                            <div class="mjc-val">{{ Record.AnnualIncreasePercent !== null ? Record.AnnualIncreasePercent + '%' : '—' }}</div>
                        }
                    </div>
                </div>

                <p class="mjc-note">
                    These record what the signed paper says. The subscription in orders holds the operational
                    setting and may legitimately differ — a mismatch is a finding, not a bug.
                </p>

                @if (!Record.RenewalNoticeDays && !Record.CancellationWindowDays && Record.AnnualIncreasePercent === null) {
                    <div class="mjc-empty">
                        No renewal terms recorded. If the agreement states any, recording them is what puts this
                        contract on the renewals watchlist.
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractRenewalPanel extends BaseFormPanel<ContractEntity> {
    /**
     * Write a field through the typed entity. Named `Set` rather than bound with two-way `[(ngModel)]`
     * so the write goes through one place — a two-way binding on `Record.X` works but gives no hook for
     * the dirty notification the form toolbar needs.
     */
    public Set(field: 'AutoRenew' | 'RenewalNoticeDays' | 'CancellationWindowDays' | 'AnnualIncreasePercent', value: unknown): void {
        (this.Record as unknown as Record<string, unknown>)[field] = value;
    }

    /** The authoritative view column — unlike State, nobody wants this tracking a half-typed edit. */
    public get NoticeDeadline(): Date | null { return this.Record?.RenewalNoticeDeadline ?? null; }
    public get InCancellationWindow(): boolean { return this.Record?.IsInCancellationWindow === true; }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 2b · Dates — its own rail section, replacing the generated `datesAndTerms`
 * ──────────────────────────────────────────────────────────────────────────── */

/**
 * The four dates, with the one piece of interpretation a reader needs.
 *
 * Exists as a panel for the same two reasons as Renewal terms: it earns a rail entry by REPLACING a
 * named field section (a replaced section is not "leftover", so left-nav does not fold it into
 * Details), and it can say things the generated field list cannot — that an executed date before the
 * effective date is normal, and that a terminated date is a fact rather than a projection.
 *
 * The generated form renders these as datetime inputs with a time component (`7/19/2025, 7:00:00 PM`)
 * because the underlying columns are `date` but the default control is a datetime picker. They are
 * calendar dates — a contract does not start at 7pm — so this panel renders them as dates.
 */
@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:dates',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'after-fields',
        sortKey: 90,
        contributionKey: 'dates',
        replacesSectionKey: 'datesAndTerms',
        // NO `inclusion: 'Primary'` — and that omission is what puts Details FIRST.
        //
        // The rail is assembled as fixed BANDS, not from a sortable flat list:
        // `spec.Groups = [...leads, ...details, ...related, ...more]`
        // (`resolve-form-chrome.ts:761`). A panel joins the LEAD band purely by declaring
        // `inclusion: 'Primary'` (`isLeadContribution`, `:313`), and every lead therefore renders
        // BEFORE Details. With all of these marked Primary, Details sat fourth.
        //
        // Reordering `spec.Groups` from a `BaseFormPolicy.DecorateChrome` cannot fix that:
        // `StabilizeFirstClassGroupOrder` re-imposes the bands, and its own comment says it moves
        // groups "into the lead band before Details" — so the reorder is silently undone. Only a
        // user's drag order (`OrderChromeGroups`) outranks the bands, and that is a per-user
        // preference an app cannot ship.
        //
        // Dropping Primary moves these into the `related` band, which sorts DESCENDING by sortKey
        // (`:753`), so the numbers below are the running order after Details.
    },
})
@Component({
    selector: 'mjc-contract-dates-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    template: `
        <mj-collapsible-panel
            SectionKey="dates"
            SectionName="Dates"
            Icon="fa-solid fa-calendar"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            <div class="mjc-body">
                <div class="mjc-fields">
                    <div class="mjc-field">
                        <label>Executed date</label>
                        @if (EditMode) {
                            <input type="date" style="width:100%" [ngModel]="AsInput(Record.ExecutedDate)"
                                   (ngModelChange)="SetDate('ExecutedDate', $event)" aria-label="Executed date" />
                        } @else {
                            <div class="mjc-val">{{ (Record.ExecutedDate | date: 'd MMM y') || '—' }}</div>
                        }
                        <div class="mjc-hint">may precede the effective date — that is normal, not an anomaly</div>
                    </div>
                    <div class="mjc-field">
                        <label>Effective date</label>
                        @if (EditMode) {
                            <input type="date" style="width:100%" [ngModel]="AsInput(Record.EffectiveDate)"
                                   (ngModelChange)="SetDate('EffectiveDate', $event)" aria-label="Effective date" />
                        } @else {
                            <div class="mjc-val">{{ (Record.EffectiveDate | date: 'd MMM y') || '—' }}</div>
                        }
                    </div>
                    <div class="mjc-field">
                        <label>End date</label>
                        @if (EditMode) {
                            <input type="date" style="width:100%" [ngModel]="AsInput(Record.EndDate)"
                                   (ngModelChange)="SetDate('EndDate', $event)" aria-label="End date" />
                        } @else {
                            <div class="mjc-val">{{ (Record.EndDate | date: 'd MMM y') || '—' }}</div>
                        }
                        @if (Record.DaysToEnd !== null) { <div class="mjc-hint">{{ EndsInText }}</div> }
                    </div>
                    <div class="mjc-field">
                        <label>Terminated date</label>
                        @if (EditMode) {
                            <input type="date" style="width:100%" [ngModel]="AsInput(Record.TerminatedDate)"
                                   (ngModelChange)="SetDate('TerminatedDate', $event)" aria-label="Terminated date" />
                        } @else {
                            <div class="mjc-val" [class.mjc-val--ro]="!Record.TerminatedDate">{{ (Record.TerminatedDate | date: 'd MMM y') || '—' }}</div>
                        }
                        <div class="mjc-hint">
                            a fact about what happened — set it and the contract reads Terminated regardless of its term
                        </div>
                    </div>
                </div>

                <p class="mjc-note">
                    The lifecycle is <strong>derived</strong> from these four dates and the two lineage links, not
                    stored — so a state can never disagree with the dates it came from.
                </p>
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractDatesPanel extends BaseFormPanel<ContractEntity> {
    /** `<input type="date">` needs `yyyy-MM-dd`; the entity hands back a Date or an ISO string. */
    public AsInput(v: Date | string | null | undefined): string {
        if (!v) return '';
        const d = v instanceof Date ? v : new Date(String(v));
        return Number.isNaN(d.getTime()) ? '' : d.toISOString().slice(0, 10);
    }

    public SetDate(field: 'ExecutedDate' | 'EffectiveDate' | 'EndDate' | 'TerminatedDate', value: string): void {
        (this.Record as unknown as Record<string, unknown>)[field] = value ? new Date(value + 'T00:00:00Z') : null;
    }

    public get EndsInText(): string {
        const d = this.Record?.DaysToEnd ?? null;
        if (d === null) return '';
        if (d < 0) return `ended ${Math.abs(d)} days ago`;
        if (d === 0) return 'ends today';
        return d < 60 ? `in ${d} days` : `in ${Math.round(d / 30)} months`;
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 3 · Modifications — the D-15 centrepiece, hosting the shared editor
 * ──────────────────────────────────────────────────────────────────────────── */

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:modifications',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'after-related',
        sortKey: 75,
        contributionKey: 'modifications',
        relatedEntity: MJC_ENTITIES.ContractTemplateModification,
        // NO `inclusion: 'Primary'` — and that omission is what puts Details FIRST.
        //
        // The rail is assembled as fixed BANDS, not from a sortable flat list:
        // `spec.Groups = [...leads, ...details, ...related, ...more]`
        // (`resolve-form-chrome.ts:761`). A panel joins the LEAD band purely by declaring
        // `inclusion: 'Primary'` (`isLeadContribution`, `:313`), and every lead therefore renders
        // BEFORE Details. With all of these marked Primary, Details sat fourth.
        //
        // Reordering `spec.Groups` from a `BaseFormPolicy.DecorateChrome` cannot fix that:
        // `StabilizeFirstClassGroupOrder` re-imposes the bands, and its own comment says it moves
        // groups "into the lead band before Details" — so the reorder is silently undone. Only a
        // user's drag order (`OrderChromeGroups`) outranks the bands, and that is a per-user
        // preference an app cannot ship.
        //
        // Dropping Primary moves these into the `related` band, which sorts DESCENDING by sortKey
        // (`:753`), so the numbers below are the running order after Details.
    },
})
@Component({
    selector: 'mjc-contract-modifications-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule, MJCModificationEditorComponent],
    template: `
        <mj-collapsible-panel
            SectionKey="contractModifications"
            SectionName="Modifications"
            Icon="fa-solid fa-pen-ruler"
            Variant="related-entity"
            [BadgeCount]="Count"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            <mjc-modification-editor
                [Record]="Record"
                [EditMode]="EditMode"
                [Provider]="FormComponent.ProviderToUse"
                (Changed)="onChanged()" />
        </mj-collapsible-panel>
    `,
})
export class MJCContractModificationsPanel extends BaseFormPanel<ContractEntity> {
    private readonly cdr = inject(ChangeDetectorRef);

    /** Drives the rail badge. Undefined rather than 0 so an empty section shows no badge. */
    public get Count(): number | undefined {
        const n = this.Record?.Modifications?.Count ?? 0;
        return n > 0 ? n : undefined;
    }

    protected onChanged(): void {
        this.cdr.detectChanges();
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 4 · Lineage — change orders and supersession, read-only
 * ──────────────────────────────────────────────────────────────────────────── */

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:lineage',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        slot: 'after-related',
        sortKey: 65,
        contributionKey: 'lineage',
        relatedEntity: MJC_ENTITIES.Contract,
        relatedJoinField: 'ParentContractID',
        // NO `inclusion: 'Primary'` — and that omission is what puts Details FIRST.
        //
        // The rail is assembled as fixed BANDS, not from a sortable flat list:
        // `spec.Groups = [...leads, ...details, ...related, ...more]`
        // (`resolve-form-chrome.ts:761`). A panel joins the LEAD band purely by declaring
        // `inclusion: 'Primary'` (`isLeadContribution`, `:313`), and every lead therefore renders
        // BEFORE Details. With all of these marked Primary, Details sat fourth.
        //
        // Reordering `spec.Groups` from a `BaseFormPolicy.DecorateChrome` cannot fix that:
        // `StabilizeFirstClassGroupOrder` re-imposes the bands, and its own comment says it moves
        // groups "into the lead band before Details" — so the reorder is silently undone. Only a
        // user's drag order (`OrderChromeGroups`) outranks the bands, and that is a per-user
        // preference an app cannot ship.
        //
        // Dropping Primary moves these into the `related` band, which sorts DESCENDING by sortKey
        // (`:753`), so the numbers below are the running order after Details.
    },
})
@Component({
    selector: 'mjc-contract-lineage-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <mj-collapsible-panel
            SectionKey="contractLineage"
            SectionName="Lineage"
            Icon="fa-solid fa-sitemap"
            Variant="related-entity"
            [BadgeCount]="Count"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            <div class="mjc-body" [class.mjc-body--flush]="Children.length > 0">
                @if (ParentName || SupersededBy) {
                    <div class="mjc-body">
                        @if (ParentName) {
                            <p class="mjc-note">
                                This is a change order to <strong>{{ ParentName }}</strong>.
                            </p>
                        }
                        @if (SupersededBy) {
                            <p class="mjc-note">
                                <span class="mjc-chip mjc-chip--muted">Superseded</span>
                                Replaced by newer paper — this agreement's terms no longer govern.
                            </p>
                        }
                    </div>
                }

                @if (Children.length) {
                    <table class="mjc-grid">
                        <thead>
                            <tr>
                                <th style="width:9rem">Contract</th>
                                <th style="width:10rem">Relationship</th>
                                <th>Summary</th>
                                <th style="width:8rem">Executed</th>
                            </tr>
                        </thead>
                        <tbody>
                            @for (c of Children; track c.ID) {
                                <tr>
                                    <td class="mjc-mono">{{ c.ContractNumber }}</td>
                                    <td><span class="mjc-chip mjc-chip--info">{{ c.ContractType || 'Change order' }}</span></td>
                                    <td>{{ c.Description || '—' }}</td>
                                    <td class="mjc-muted">{{ (c.ExecutedDate | date: 'd MMM y') || '—' }}</td>
                                </tr>
                            }
                        </tbody>
                    </table>
                } @else if (!ParentName && !SupersededBy) {
                    <div class="mjc-empty">
                        A standalone agreement — nothing above it, no change orders, and nothing has replaced it.
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractLineagePanel extends BaseFormPanel<ContractEntity> {
    private readonly cdr = inject(ChangeDetectorRef);

    /** Change orders naming THIS contract as parent. */
    public Children: Array<Record<string, string | null>> = [];
    private loadStarted = false;

    public get ParentName(): string { return this.Record?.ParentContract ?? ''; }
    public get SupersededBy(): string { return this.Record?.SupersededByContractID ?? ''; }

    public get Count(): number | undefined {
        this.ensureLoaded();
        return this.Children.length > 0 ? this.Children.length : undefined;
    }

    /**
     * Read the children ONCE, lazily on first template read.
     *
     * `BaseFormPanel` has no lifecycle hook of its own and the slot host sets `Record` before view init,
     * so the first template read is the earliest reliable moment. Read as a table rather than an
     * embedded grid: a grid inside a panel inside a rail section is three nested scroll contexts, and
     * the mockup renders four columns of read-only facts, which is a table.
     */
    private ensureLoaded(): void {
        if (this.loadStarted || !this.Record?.ID) return;
        this.loadStarted = true;
        void this.load();
    }

    private async load(): Promise<void> {
        try {
            const { ScopedRunView } = await import('../data/provider');
            const r = await ScopedRunView(this.FormComponent?.ProviderToUse).RunView<Record<string, string | null>>({
                EntityName: MJC_ENTITIES.Contract,
                Fields: ['ID', 'ContractNumber', 'ContractType', 'Description', 'ExecutedDate'],
                ExtraFilter: `ParentContractID = '${this.Record!.ID}'`,
                OrderBy: 'ExecutedDate ASC',
                ResultType: 'simple',
            });
            this.Children = r?.Success ? r.Results : [];
        } catch {
            this.Children = [];
        }
        this.cdr.detectChanges();
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 5 · Policy — moves Details to the top of the left-nav rail
 * ──────────────────────────────────────────────────────────────────────────── */
