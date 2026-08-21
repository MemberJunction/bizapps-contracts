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
import { HierarchyTreeComponent, type HierarchyTreeConfig, type HierarchyNodeEvent } from '@memberjunction/ng-hierarchy-tree';
import { NavigationService } from '@memberjunction/ng-shared';
import { ContractEntity, type ContractState } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';

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
                        <label>Renewal notice we owe (days)</label>
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
                        <label>Notice to cancel (days)</label>
                        @if (EditMode) {
                            <input type="number" min="0" style="width:100%" [ngModel]="Record.CancellationWindowDays"
                                   (ngModelChange)="Set('CancellationWindowDays', $event)" aria-label="Cancellation window days" />
                        } @else {
                            <div class="mjc-val">{{ Record.CancellationWindowDays ? Record.CancellationWindowDays + ' days' : '—' }}</div>
                        }
                        @if (InCancellationWindow) { <div class="mjc-hint">the window is open now</div> }
                    </div>
                    <div class="mjc-field">
                        <label>Annual increase (%)</label>
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
    imports: [CommonModule, FormsModule, BaseFormsModule, HierarchyTreeComponent],
    template: `
        <mj-collapsible-panel
            SectionKey="contractLineage"
            SectionName="Lineage"
            Icon="fa-solid fa-sitemap"
            Variant="related-entity"
            [BadgeCount]="Count"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            <div class="mjc-body" [class.mjc-body--flush]="HasChildren">
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
                                Replaced by <strong>{{ SupersededBy }}</strong> — this agreement's terms no longer govern.
                            </p>
                        }
                    </div>
                }

                <!-- ── Re-papering: what THIS agreement replaces ─────────────────────────────
                     The FK lives on the PREDECESSOR, so this section writes another record. See
                     LinkSupersedes(). Rendered on a brand-new contract too — picking the predecessor
                     while composing the successor is the primary flow. -->
                <div class="mjc-body">
                    @if (Supersedes.length) {
                        <p class="mjc-note">
                            <span class="mjc-chip mjc-chip--info">Re-papers</span>
                            This agreement replaces
                            @for (p of Supersedes; track p.ID) {
                                <strong>{{ p.ContractNumber }}</strong>{{ $last ? '' : ', ' }}
                            }.
                            @if (EditMode) {
                                @for (p of Supersedes; track p.ID) {
                                    <button type="button" class="mjc-btn mjc-btn--flat mjc-btn--sm"
                                            [disabled]="Busy"
                                            (click)="UnlinkSupersedes(p.ID)"
                                            [attr.aria-label]="'Stop superseding ' + p.ContractNumber">
                                        Unlink {{ p.ContractNumber }}
                                    </button>
                                }
                            }
                        </p>
                    }

                    @if (EditMode) {
                        <div class="mjc-field">
                            <label for="mjc-supersedes-picker">This agreement supersedes</label>
                            <select id="mjc-supersedes-picker" [(ngModel)]="PickedPredecessorID" [disabled]="Busy"
                                    aria-label="Choose the contract this agreement replaces">
                                <option [ngValue]="''">— nothing (this is new paper) —</option>
                                @for (c of Candidates; track c.ID) {
                                    <option [ngValue]="c.ID">{{ c.ContractNumber }} — {{ c.ContractType }}</option>
                                }
                            </select>
                            <button type="button" class="mjc-btn mjc-btn--sm"
                                    [disabled]="Busy || !PickedPredecessorID"
                                    (click)="LinkSupersedes()">
                                {{ Busy ? 'Linking…' : 'Link' }}
                            </button>
                            <div class="mjc-hint">
                                Saves this contract first, then marks the chosen agreement superseded by it.
                            </div>
                            @if (!Candidates.length && !CandidatesLoading) {
                                <div class="mjc-hint">
                                    Nothing eligible. A predecessor must sit at the same level as this contract
                                    ({{ LevelDescription }}) and must not already be superseded.
                                </div>
                            }
                            @if (LinkError) { <div class="mjc-error">{{ LinkError }}</div> }
                        </div>
                    }
                </div>

                <!-- The parent/child tree is MJ's, not ours: ParentContractID is an ordinary
                     self-referential hierarchy, which is exactly what mj-hierarchy-tree consumes. It
                     loads its own data from the Config, highlights the contract being viewed, and its
                     nodes NAVIGATE — the thing the hand-rolled table could never do. -->
                <mj-hierarchy-tree
                    [Config]="TreeConfig"
                    [ActiveRecordID]="Record?.ID ?? undefined"
                    (NodeDoubleClick)="OpenNode($event)" />

                @if (!ParentName && !SupersededBy && !HasChildren) {
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

    private readonly navigation = inject(NavigationService);

    /**
     * The whole tree, declared rather than fetched.
     *
     * `ParentContractID` is an ordinary self-referential hierarchy, so MJ's tree does the recursive
     * read, the expand/collapse state, the search box and — the part that matters — turns each node
     * into something you can OPEN. The hand-rolled table this replaces could show a change order's
     * number but gave no way to get to it, which is most of what a person wants from a lineage panel.
     *
     * NO `ExtraFilter`, deliberately — the component does the scoping better than a filter could. Given
     * the whole entity plus `ActiveRecordID`, it focuses this contract's subtree on its own (the header
     * reads "Focusing subtree: CTR-…") and offers "View Full Hierarchy" to widen. A filter rooted at
     * the current record would hard-hide the parent a change order needs to show ABOVE it, with no way
     * back out. Ordering is by contract number so siblings read in the order they were issued.
     */
    public get TreeConfig(): HierarchyTreeConfig {
        return {
            EntityName: MJC_ENTITIES.Contract,
            ParentField: 'ParentContractID',
            NameField: 'ContractNumber',
            SubtitleField: 'Description',
            OrderBy: 'ContractNumber ASC',
            ShowSearch: true,
            InitialExpandDepth: 2,
        };
    }

    /** Whether anything hangs beneath this contract — drives the empty state, nothing else. */
    public HasChildren = false;
    private loadStarted = false;

    /**
     * Open the contract a node stands for.
     *
     * The node carries a real `CompositeKey`, so this does not have to guess that the primary key is
     * called `ID` — the same reasoning as `MJCFkNavigateDirective`, which would break on the first
     * natural-key entity it met, and would break as a WRONG-RECORD navigation rather than an error.
     */
    public OpenNode(e: HierarchyNodeEvent): void {
        const key = e?.Node?.PrimaryKey;
        if (!key) return;
        this.navigation.OpenEntityRecord(MJC_ENTITIES.Contract, key);
    }

    public get ParentName(): string { return this.Record?.ParentContract ?? ''; }

    /**
     * The successor's NUMBER, not its id.
     *
     * Was `SupersededByContractID` — which rendered a raw UUID to the user in the one place the panel
     * is trying to say something human ("replaced by newer paper"). `SupersededByContract` is the
     * generated virtual FK-name field, so this costs nothing extra to read.
     */
    public get SupersededBy(): string { return this.Record?.SupersededByContract ?? ''; }

    /** Predecessors THIS contract replaces — the reverse of `SupersededByContractID`. */
    public Supersedes: Array<{ ID: string; ContractNumber: string }> = [];
    /** Eligible predecessors, loaded only in EditMode. */
    public Candidates: Array<{ ID: string; ContractNumber: string; ContractType: string }> = [];
    public CandidatesLoading = false;
    public PickedPredecessorID = '';
    public Busy = false;
    public LinkError = '';

    /** Names this contract's level, so the empty-candidates hint can explain what "eligible" means. */
    public get LevelDescription(): string {
        return this.Record?.ParentContractID
            ? `under ${this.Record.ParentContract ?? 'its parent contract'}`
            : 'a top-level agreement';
    }

    /**
     * Re-paper: mark the chosen PREDECESSOR as superseded by this contract.
     *
     * TWO STEPS, IN THIS ORDER, and that is the whole operation. The predecessor cannot point at a
     * contract that does not exist yet, so this one is saved first; then the predecessor's own
     * `Supersede()` sets its field and saves. `ContractEntityServer` validates the level on that
     * second save — the same rule that applies to anyone setting `SupersededByContractID` by hand.
     *
     * WHY THIS WRITES ANOTHER RECORD. The relationship is stored on the predecessor, which is the
     * correct direction: it keeps "a contract is superseded at most once" structurally true, supports
     * several agreements consolidating into one, and lets the base view derive `Superseded` from a
     * column on the row it is already projecting rather than an EXISTS subquery on the app's hottest
     * read path. The cost of that choice is exactly this — the successor's form reaches over and writes
     * the predecessor. No `SupersedesID` column is needed to carry the intent: the picker yields an ID
     * and `Supersede()` takes the entity.
     *
     * DELIBERATELY NOT ONE TRANSACTION (simplified 2026-08-20 after Marcelo pushed back). A
     * `TransactionGroup` would make both writes atomic, but it DEFERS every write until `Submit()` —
     * so the predecessor would validate against a successor that has an ID and no row, and the level
     * check could not tell an unwritten sibling from a bad reference. That ambiguity was the only
     * reason the guard needed a special case.
     *
     * And atomicity buys very little here: the successor is not a byproduct of superseding, it is a
     * contract the user is deliberately creating. If the link fails, what remains is that contract,
     * unlinked — not garbage — and the picker below retries the link on its own. A benign, visible,
     * recoverable partial state is worth more than a rule the validator cannot check.
     */
    public async LinkSupersedes(): Promise<void> {
        const predecessorID = this.PickedPredecessorID;
        if (!predecessorID || !this.Record) return;

        this.Busy = true;
        this.LinkError = '';
        try {
            const { Metadata } = await import('@memberjunction/core');
            const provider = this.FormComponent?.ProviderToUse ?? Metadata.Provider;

            // 1 · The successor must exist before anything can point at it.
            if (this.Record.Dirty || !this.Record.IsSaved) {
                if (!(await this.Record.Save())) {
                    throw new Error(
                        this.Record.LatestResult?.Message ??
                            'This contract could not be saved, so nothing was superseded.',
                    );
                }
            }

            // 2 · Set the field on the predecessor. Its own validation checks the level.
            const predecessor = await provider.GetEntityObject<ContractEntity>(MJC_ENTITIES.Contract);
            if (!(await predecessor.Load(predecessorID))) {
                throw new Error('That contract could not be loaded — it may have been deleted.');
            }
            predecessor.Supersede(this.Record);
            if (!(await predecessor.Save())) {
                throw new Error(
                    predecessor.LatestResult?.Message ??
                        'The predecessor could not be marked superseded. This contract was saved and is not linked.',
                );
            }

            this.PickedPredecessorID = '';
            this.loadStarted = false;
            await this.load();
        } catch (e) {
            this.LinkError = e instanceof Error ? e.message : String(e);
        } finally {
            this.Busy = false;
            this.cdr.detectChanges();
        }
    }

    /**
     * Undo a re-papering — clear the predecessor's successor FK.
     *
     * Left available deliberately (Marcelo, 2026-08-20: "supersedes should be left unlocked for now").
     * One record changes, so no transaction group is needed. The predecessor returns to whatever state
     * its own dates imply, because `Superseded` was never stored.
     */
    public async UnlinkSupersedes(predecessorID: string): Promise<void> {
        this.Busy = true;
        this.LinkError = '';
        try {
            const { Metadata } = await import('@memberjunction/core');
            const provider = this.FormComponent?.ProviderToUse ?? Metadata.Provider;
            const predecessor = await provider.GetEntityObject<ContractEntity>(MJC_ENTITIES.Contract);
            if (!(await predecessor.Load(predecessorID))) {
                throw new Error('That contract could not be loaded — it may have been deleted.');
            }
            predecessor.SupersededByContractID = null;
            if (!(await predecessor.Save())) {
                throw new Error(predecessor.LatestResult?.Message ?? 'Could not unlink. Nothing was changed.');
            }
            this.loadStarted = false;
            await this.load();
        } catch (e) {
            this.LinkError = e instanceof Error ? e.message : String(e);
        } finally {
            this.Busy = false;
            this.cdr.detectChanges();
        }
    }

    public get Count(): number | undefined {
        this.ensureLoaded();
        return this.ChildCount > 0 ? this.ChildCount : undefined;
    }

    /** Direct children, for the badge. The TREE renders the hierarchy; this is just the count. */
    public ChildCount = 0;

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
        const me = this.Record!.ID;
        const rv = await this.scopedRunView();
        // Only the COUNT, for the badge and the empty state — mj-hierarchy-tree reads the hierarchy
        // itself from TreeConfig, so duplicating that read here would be a second source of truth.
        try {
            const r = await rv.RunView<{ ID: string }>({
                EntityName: MJC_ENTITIES.Contract,
                Fields: ['ID'],
                ExtraFilter: `ParentContractID = '${me}'`,
                ResultType: 'simple',
            });
            this.ChildCount = r?.Success ? r.Results.length : 0;
            this.HasChildren = this.ChildCount > 0;
        } catch {
            this.ChildCount = 0;
            this.HasChildren = false;
        }

        // What this contract replaces. The reverse of `SupersededByContractID`, so it is a query and
        // not a field read — a set, because several agreements may consolidate into one successor.
        try {
            const r = await rv.RunView<{ ID: string; ContractNumber: string }>({
                EntityName: MJC_ENTITIES.Contract,
                Fields: ['ID', 'ContractNumber'],
                ExtraFilter: `SupersededByContractID = '${me}'`,
                OrderBy: 'ContractNumber ASC',
                ResultType: 'simple',
            });
            this.Supersedes = r?.Success ? r.Results : [];
        } catch {
            this.Supersedes = [];
        }

        await this.loadCandidates();
        this.cdr.detectChanges();
    }

    /**
     * Eligible predecessors: same level, not already superseded, not this contract.
     *
     * The same-level predicate has to be written two ways because `ParentContractID = NULL` matches
     * nothing in SQL — a top-level contract's peers are found with `IS NULL`, a child's with an
     * equality. Getting that wrong would silently offer an empty list to every root contract, which is
     * most of them.
     *
     * This mirrors `refuseCrossLevelSupersession` but does NOT replace it: this query decides what to
     * OFFER, the server decides what is ALLOWED. If they ever disagree the server wins and the user
     * sees its message — which is the right way round.
     */
    private async loadCandidates(): Promise<void> {
        if (!this.EditMode) { this.Candidates = []; return; }
        this.CandidatesLoading = true;
        try {
            const parentID = this.Record?.ParentContractID ?? null;
            const sameLevel = parentID === null ? 'ParentContractID IS NULL' : `ParentContractID = '${parentID}'`;
            const rv = await this.scopedRunView();
            const r = await rv.RunView<{ ID: string; ContractNumber: string; ContractType: string }>({
                EntityName: MJC_ENTITIES.Contract,
                Fields: ['ID', 'ContractNumber', 'ContractType'],
                ExtraFilter: `${sameLevel} AND SupersededByContractID IS NULL AND ID <> '${this.Record!.ID}'`,
                OrderBy: 'ContractNumber ASC',
                ResultType: 'simple',
            });
            this.Candidates = r?.Success ? r.Results : [];
        } catch {
            this.Candidates = [];
        } finally {
            this.CandidatesLoading = false;
        }
    }

    private async scopedRunView() {
        const { ScopedRunView } = await import('../data/provider');
        return ScopedRunView(this.FormComponent?.ProviderToUse);
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 5 · Policy — moves Details to the top of the left-nav rail
 * ──────────────────────────────────────────────────────────────────────────── */
