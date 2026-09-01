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
import { CompositeKey, Metadata } from '@memberjunction/core';
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
                        <span>Company: <strong>{{ CompanyName || '—' }}</strong></span>
                        <span>Customer: <strong>{{ CustomerName || '—' }}</strong></span>
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
                @if (HasSource) {
                    <div class="mjc-stat">
                        <span class="mjc-stat__label">{{ SourceLabel }}</span>
                        <span class="mjc-stat__value">
                            <button type="button" class="mjc-link" (click)="OpenSource()"
                                    [attr.aria-label]="'Open ' + (SourceName || 'the source record')">
                                {{ SourceName || 'Open' }}
                            </button>
                        </span>
                    </div>
                }
            </div>

            @if (!Record.ContractNumber) {
                <div class="mjc-flag">Contract number is assigned on save.</div>
            }
        </div>
    `,
})
export class MJCContractHeroPanel extends BaseFormPanel<ContractEntity> {
    private readonly cdr = inject(ChangeDetectorRef);

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
    /* ── Source record — the thing that created this contract (issue #28 item 1) ──────────────
     *
     * WHAT THIS STAT USED TO CLAIM. It was labelled "Created by" and rendered `CreatingEntity` — the
     * name of an ENTITY, not a person — so a contract raised from a Close-Won deal read "Deals", and
     * one typed in by hand read "—" over the words "entered directly". The label promised a person,
     * the value delivered a table name, and neither told the reader which deal.
     *
     * `CreatingEntityID` / `CreatingRecordID` is a polymorphic pair, so nothing here may assume Deals.
     * Today `bizapps-sales` is the only writer (`LiveContractsSeam.ts`, on Close-Won) and always sets
     * Deals, but the column does not say so — the entity is resolved from the id, the label takes that
     * entity's own singular name, and an Order would render "Source Order" with no edit here.
     *
     * WHEN THERE IS NO SOURCE THE STAT IS ABSENT, not empty. A hero stat reading "—" over "entered
     * directly" spends the most-read row on the absence of a fact, and "entered directly" is not even
     * a fact about the contract — it is the panel narrating its own null.
     */
    private readonly navigation = inject(NavigationService);

    /** Resolved once per record, lazily, on the first template read. */
    private sourceFor: string | null = null;
    public SourceLabel = 'Source record';
    public SourceName = '';

    /**
     * Whether this contract records what created it.
     *
     * Doubles as the load trigger — `BaseFormPanel` has no lifecycle hook and the slot host sets
     * `Record` before view init, so the first template read is the earliest reliable moment. Keyed on
     * the record id rather than a bare boolean so navigating the form to a different contract reloads
     * instead of showing the previous one's deal.
     */
    public get HasSource(): boolean {
        const id = this.Record?.CreatingEntityID;
        if (!id || !this.Record?.CreatingRecordID) return false;
        const key = `${this.Record.ID}:${id}:${this.Record.CreatingRecordID}`;
        if (this.sourceFor !== key) { this.sourceFor = key; void this.loadSource(key); }
        return true;
    }

    /** The entity named by `CreatingEntityID`, or null when the id names nothing this user can see. */
    private sourceEntity() {
        const provider = this.FormComponent?.ProviderToUse ?? Metadata.Provider;
        const id = this.Record?.CreatingEntityID;
        return (id ? provider?.Entities?.find((e) => e.ID === id) : undefined) ?? null;
    }

    /**
     * Label from the entity, name from the record.
     *
     * `BaseTableDisplayName` rather than `DisplayName`: the entity is plural ("Deals") and the stat
     * labels one record, so the singular base table is the honest word — and it is what produces
     * "Source Deal" and "Source Order" without a de-pluralising guess.
     */
    private async loadSource(key: string): Promise<void> {
        const entity = this.sourceEntity();
        if (!entity) return;
        this.SourceLabel = `Source ${entity.BaseTableDisplayName}`;

        const nameField = entity.NameField?.Name;
        const pkField = entity.PrimaryKeys?.[0]?.Name ?? 'ID';
        const recordID = String(this.Record?.CreatingRecordID ?? '');
        if (!nameField || !recordID) { this.cdr.detectChanges(); return; }

        try {
            const { ScopedRunView } = await import('../data/provider');
            const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
            const r = await rv.RunView<Record<string, unknown>>({
                EntityName: entity.Name,
                Fields: [nameField],
                ExtraFilter: `${pkField} = '${recordID.replace(/'/g, "''")}'`,
                ResultType: 'simple',
            });
            // Guard against a slower read for a PREVIOUS record landing after the form moved on.
            if (this.sourceFor !== key) return;
            const row = r?.Success ? r.Results?.[0] : undefined;
            this.SourceName = row ? String(row[nameField] ?? '') : '';
        } catch {
            // The link still works without a name — the stat falls back to "Open" rather than
            // vanishing, because the source record exists whether or not we could read its title.
            this.SourceName = '';
        } finally {
            this.cdr.detectChanges();
        }
    }

    /** Open the record that created this contract. */
    public OpenSource(): void {
        const entity = this.sourceEntity();
        const recordID = this.Record?.CreatingRecordID;
        if (!entity || !recordID) return;
        const pkField = entity.PrimaryKeys?.[0]?.Name ?? 'ID';
        this.navigation.OpenEntityRecord(entity.Name, CompositeKey.FromKeyValuePair(pkField, String(recordID)));
    }
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
                    </div>
                    <div class="mjc-field">
                        <label>Renewal notice (days)</label>
                        @if (EditMode) {
                            <input type="number" min="0" [ngModel]="Record.RenewalNoticeDays"
                                   (ngModelChange)="Set('RenewalNoticeDays', $event)" aria-label="Renewal notice days" />
                        } @else {
                            <div class="mjc-val">{{ Days(Record.RenewalNoticeDays) }}</div>
                        }
                        <!-- WHICH WAY THE NOTICE RUNS is the whole content of this field, and the label
                             cannot carry it. "Renewal notice we owe (days)" tried, and produced a label
                             no other field in the app resembles while still leaving a reader to guess
                             what the notice is ABOUT. The direction goes in the hint instead. -->
                        <div class="mjc-hint">Written notice we must give the customer before a renewal price change.</div>
                        @if (NoticeDeadline) {
                            <div class="mjc-hint">deadline: {{ NoticeDeadline | date: 'd MMM y' }}</div>
                        }
                    </div>
                    <div class="mjc-field">
                        <label>Notice to cancel (days)</label>
                        @if (EditMode) {
                            <input type="number" min="0" [ngModel]="Record.CancellationWindowDays"
                                   (ngModelChange)="Set('CancellationWindowDays', $event)" aria-label="Cancellation window days" />
                        } @else {
                            <div class="mjc-val">{{ Days(Record.CancellationWindowDays) }}</div>
                        }
                        <!-- The MIRROR of the field above, and the pair is the point: one is notice we
                             owe, one is notice we are owed. The column description says they are not
                             the same field; two adjacent day-counts with no stated direction is exactly
                             how they get confused. -->
                        <div class="mjc-hint">Notice the customer must give us to cancel.</div>
                        @if (InCancellationWindow) { <div class="mjc-hint">the window is open now</div> }
                    </div>
                    <div class="mjc-field">
                        <label>Annual increase (%)</label>
                        @if (EditMode) {
                            <input type="number" min="0" step="0.01" [ngModel]="Record.AnnualIncreasePercent"
                                   (ngModelChange)="Set('AnnualIncreasePercent', $event)" aria-label="Annual increase percent" />
                        } @else {
                            <div class="mjc-val">{{ Percent(Record.AnnualIncreasePercent) }}</div>
                        }
                    </div>
                </div>


                @if (NoTermsRecorded) {
                    <div class="mjc-empty">No renewal terms recorded.</div>
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

    /**
     * A day count, where ZERO IS A VALUE (issue #28 item 21).
     *
     * The template used `Record.X ? … : '—'`, so a recorded `0` rendered as the same em dash as a
     * blank — the panel reported "we hold no figure" about a figure that says "no notice is required".
     * Those are different facts and the second is the one somebody negotiated. `== null` is the whole
     * fix, and it is deliberately `==` rather than `===` so it catches `undefined` too.
     */
    public Days(v: number | null | undefined): string {
        return v == null ? '—' : `${v} days`;
    }

    /** Same rule for the percentage: `0%` is a negotiated cap, not a missing value. */
    public Percent(v: number | null | undefined): string {
        return v == null ? '—' : `${v}%`;
    }

    /**
     * Whether this agreement genuinely states no renewal terms.
     *
     * AUTO-RENEWS IS ONE OF THE TERMS, and leaving it out is why the empty state used to contradict
     * the screen: `AutoRenew = Yes` with blank day counts showed "No renewal terms recorded" directly
     * beneath a field reading Yes. Auto-renewal is the most consequential renewal term there is, so
     * the panel is only empty when it is No AND all three numbers are absent.
     */
    public get NoTermsRecorded(): boolean {
        return !this.Record?.AutoRenew &&
            this.Record?.RenewalNoticeDays == null &&
            this.Record?.CancellationWindowDays == null &&
            this.Record?.AnnualIncreasePercent == null;
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
                            <input type="date" [ngModel]="AsInput(Record.ExecutedDate)"
                                   (ngModelChange)="SetDate('ExecutedDate', $event)" aria-label="Executed date" />
                        } @else {
                            <div class="mjc-val">{{ (Record.ExecutedDate | date: 'd MMM y') || '—' }}</div>
                        }
                    </div>
                    <div class="mjc-field">
                        <label>Effective date</label>
                        @if (EditMode) {
                            <input type="date" [ngModel]="AsInput(Record.EffectiveDate)"
                                   (ngModelChange)="SetDate('EffectiveDate', $event)" aria-label="Effective date" />
                        } @else {
                            <div class="mjc-val">{{ (Record.EffectiveDate | date: 'd MMM y') || '—' }}</div>
                        }
                    </div>
                    <div class="mjc-field">
                        <label>End date</label>
                        @if (EditMode) {
                            <input type="date" [ngModel]="AsInput(Record.EndDate)"
                                   (ngModelChange)="SetDate('EndDate', $event)" aria-label="End date" />
                        } @else {
                            <div class="mjc-val">{{ (Record.EndDate | date: 'd MMM y') || '—' }}</div>
                        }
                        @if (Record.DaysToEnd !== null) { <div class="mjc-hint">{{ EndsInText }}</div> }
                    </div>
                    <div class="mjc-field">
                        <label>Terminated date</label>
                        @if (EditMode) {
                            <input type="date" [ngModel]="AsInput(Record.TerminatedDate)"
                                   (ngModelChange)="SetDate('TerminatedDate', $event)" aria-label="Terminated date" />
                        } @else {
                            <div class="mjc-val" [class.mjc-val--ro]="!Record.TerminatedDate">{{ (Record.TerminatedDate | date: 'd MMM y') || '—' }}</div>
                        }
                        <div class="mjc-hint">Setting this marks the contract Terminated from this date.</div>
                    </div>
                </div>

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
    // The tree needs a usable height of its own: it is an SVG canvas, not flow content, so with no
    // intrinsic height it draws into a zero box (and logs translate(NaN,NaN) — MJ#3997).
    // WHY THESE RULES EXIST — measured, not guessed, after reading FORMS_ARCHITECTURE_GUIDE §7d.
    //
    // `Variant="related-entity"` is what puts this section on the left-nav RAIL; removing it drops the
    // rail item and the panel collapses into Details (confirmed both ways in the browser). But that
    // variant's CSS was written for AG Grid: it sizes the content box with `height:auto; min-height:0;
    // overflow:hidden` and restores a usable height for exactly ONE child selector —
    //
    //     .mj-forms-panel--related .mj-forms-panel-content > mj-explorer-entity-data-grid { height:100% }
    //
    // Any other child gets no height, and with `overflow:hidden` above it the panel renders BLANK while
    // every node sits in the DOM. So this mirrors MJ's own rule for our content instead of inventing a
    // different sizing scheme (an earlier attempt using `flex: 1 1 auto` was wrong — the content box is
    // not the flex parent that assumes).
    //
    // The host and the slot are both `display: contents` BY DESIGN (§7d), so they contribute no box and
    // `.mjc-body` is the real layout child of the content box. That is also why measuring the host's
    // height proves nothing.
    styles: [`
        /* A PINNED FLOOR, not a percentage. height:100% cannot work here: it resolves against
           .mj-forms-panel-content, which the variant sets to height:auto, and 100% of auto collapses
           straight back to auto - measured blank. AG Grid escapes this because the grid supplies its
           own intrinsic height; a plain div does not. A px min-height resolves regardless of what the
           parent computes to, and stays under the variant's own 800px cap. */
        /* DIRECT child only. As a descendant selector this also matched the nested .mjc-body wrapper
           inside the panel, so the floor applied twice and left a tall empty block above the tree. */
        mjc-contract-lineage-panel > .mjc-body {
            min-height: 440px;
            overflow-y: auto;
        }
        mjc-contract-lineage-panel mj-hierarchy-tree { display: block; min-height: 380px; }
    `],
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
                @if (ParentName) {
                    <div class="mjc-body">
                        @if (ParentName) {
                            <p class="mjc-note">
                                This is a change order to <strong>{{ ParentName }}</strong>.
                            </p>
                        }
                    </div>
                }

                <!-- The parent/child tree is MJ's, not ours: ParentContractID is an ordinary
                     self-referential hierarchy, which is exactly what mj-hierarchy-tree consumes. It
                     loads its own data from the Config, highlights the contract being viewed, and its
                     nodes NAVIGATE — the thing the hand-rolled table could never do. -->
                <mj-hierarchy-tree
                    [Config]="TreeConfig"
                    [ActiveRecordID]="Record?.ID ?? undefined"
                    (NodeDoubleClick)="OpenNode($event)" />

                @if (!ParentName && !HasChildren) {
                    <div class="mjc-empty">
                        No parent contract, change orders, or superseding contracts.
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

        this.cdr.detectChanges();
    }

    private async scopedRunView() {
        const { ScopedRunView } = await import('../data/provider');
        return ScopedRunView(this.FormComponent?.ProviderToUse);
    }
}

