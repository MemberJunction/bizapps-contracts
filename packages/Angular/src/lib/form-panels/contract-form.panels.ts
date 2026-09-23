/**
 * @fileoverview Contract form body — Overview plus organized rail sections.
 *
 * Replaces leftover generated field dumps (Contract Details, Stakeholders, Provenance,
 * Lifecycle, Notes) with:
 *   Overview (exec briefing) · Agreement · Parties · Dates · Renewal · Notes
 *   Modifications · Lineage · Re-papering · Provenance
 *
 * Dates / Renewal / Lineage / Re-papering already live in sibling files.
 * Files on a contract are MJ's stock attachments (form toolbar), not a custom Documents section.
 * `contributionKey` equals each panel's `SectionKey`. Overview is the only
 * `inclusion: 'Primary'` so it leads; the rest sort into the related band by sortKey.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, ViewEncapsulation, inject, type OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CompositeKey } from '@memberjunction/core';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import { MJAlertComponent, MJButtonDirective, MJComboboxComponent } from '@memberjunction/ng-ui-components';
import type { AfterDataLoadEventArgs } from '@memberjunction/ng-entity-viewer';
import {
    ContractEntity,
    CurrentTemplateFilter,
    CurrentTemplateOrderBy,
    DealIDClause,
    DealOptionLabel,
    DealSearchClause,
    MayWriteDefaultTemplate,
    ShouldDefaultTemplate,
    ShouldWithdrawDefaultTemplate,
    type ContractState,
    type DealOption,
} from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from '../data/entity-names';
import { DateAsText } from './contract-dates';

const E = MJC_ENTITIES.Contract;

/**
 * A deal option with its rendered label attached (golive #219).
 *
 * The label is computed ONCE per row, on load, rather than from a template call: `mj-combobox` reads
 * `TextField` on every change-detection pass and for every option, so a function there re-renders the
 * whole list on each keystroke.
 */
interface DealChoice extends DealOption {
    Label: string;
}

type ContractFieldType =
    | 'textbox' | 'textarea' | 'number' | 'datepicker' | 'checkbox'
    | 'select' | 'autocomplete' | 'code' | 'dropdownlist' | 'numerictextbox';

interface ContractFieldSpec {
    name: string;
    type: ContractFieldType;
    link?: 'Record' | 'URL';
    span?: boolean;
    /**
     * Never editable, even in Edit mode — the SERVER owns this value (issue #28 item 18).
     *
     * Distinct from a field the API happens to reject: these render as an input a person can type
     * into, and the typing is silently discarded or overwritten on save. `ContractNumber` is minted
     * under a lock in `assignContractNumber()`, `HasModifications` is settled by the server's
     * `ValidateAsync()`, and `SupersededByContractID` is written only by `Contracts.Supersede` on the
     * SUCCESSOR — editing it here would set the opposite direction from the Re-papering panel.
     */
    readOnly?: boolean;
}

const FIELD_STYLES = `
    .mjc-fields-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--mj-space-4) var(--mj-space-5);
        padding: var(--mj-space-4) var(--mj-space-5);
    }
    @media (max-width: 720px) { .mjc-fields-grid { grid-template-columns: 1fr; } }
    .mjc-fg { min-width: 0; }
    .mjc-fg--span { grid-column: 1 / -1; }
    .mjc-fg .mj-forms-field {
        display: flex; flex-direction: column; align-items: stretch; gap: 4px; padding: 0;
    }
    .mjc-fg .mj-forms-field-label {
        font-size: var(--mj-text-xs); font-weight: 700; letter-spacing: .06em;
        text-transform: uppercase; color: var(--mj-text-muted);
    }
    .mjc-fg .mj-forms-field--editing:hover { margin: 0; padding: 0; }
`;

/**
 * One rendering of a stored calendar day, shared with the hero and the Dates tab.
 *
 * This function had the zone right — `timeZone: 'UTC'` on a UTC-midnight `DATE` is exactly the
 * doctrine — and got the PARSE wrong in a narrower way: `new Date('2026-09-30T23:00:00-05:00')` is
 * 1 October in UTC, so an offset-bearing stored string re-based onto the following day. `DateAsText`
 * takes such a string as written. Kept as a name because the Overview template and three panels bind
 * `dateLabel` directly.
 */
const dateLabel = DateAsText;

function endsInText(days: number | null | undefined): string {
    if (days == null) return '';
    if (days < 0) return `ended ${Math.abs(days)} days ago`;
    if (days === 0) return 'ends today';
    if (days < 60) return `in ${days} days`;
    const months = Math.round(days / 30);
    return `in ${months} month${months === 1 ? '' : 's'}`;
}

/**
 * The whole clause, verb included, because the verb has to agree with the tense
 * `endsInText` picks. Writing `Term ends ${endsInText(d)}` reads "Term ends ends
 * today" on the day a term ends, and "Term ends ended 3 days ago" behind it.
 */
function termEndsText(days: number | null | undefined): string {
    if (days == null) return '';
    if (days < 0) return `Term ${endsInText(days)}`;
    if (days === 0) return 'Term ends today';
    return `Term ends ${endsInText(days)}`;
}

/* ── Overview ─────────────────────────────────────────────────────────────── */

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:overview',
    skipNullKeyWarning: true,
    metadata: {
        entity: E,
        slot: 'after-fields',
        sortKey: 200,
        contributionKey: 'overview',
        inclusion: 'Primary',
        replacesSectionKey: 'contractDetails',
    },
})
@Component({
    selector: 'mjc-contract-overview-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <mj-collapsible-panel
            SectionKey="overview"
            SectionName="Overview"
            Icon="fa-solid fa-chart-pie"
            [Form]="FormComponent"
            [FormContext]="FormContext"
            [DefaultExpanded]="true">
            <div class="mjc-ov">
                @if (Health.length) {
                    <div class="mjc-ov-health">
                        @for (h of Health; track h) {
                            <div class="mjc-ov-alert">
                                <i class="fa-solid fa-triangle-exclamation" aria-hidden="true"></i>
                                {{ h }}
                            </div>
                        }
                    </div>
                } @else if (Record.IsSaved) {
                    <div class="mjc-ov-ok">
                        <i class="fa-solid fa-circle-check" aria-hidden="true"></i>
                        No issues.
                    </div>
                }

                <div class="mjc-ov-strip">
                    <div class="mjc-ov-kpi" [attr.data-tone]="StateTone">
                        <div class="l">State</div>
                        <div class="v">{{ State }}</div>
                        <div class="s">{{ TypeName || 'No type' }}</div>
                    </div>
                    <div class="mjc-ov-kpi" [attr.data-tone]="EndTone">
                        <div class="l">Term ends</div>
                        <div class="v">{{ EndClock }}</div>
                        <div class="s">{{ dateLabel(Record.EndDate) }}</div>
                    </div>
                    <div class="mjc-ov-kpi" [attr.data-tone]="NoticeTone">
                        <div class="l">Notice</div>
                        <div class="v">{{ NoticeClock }}</div>
                        <div class="s">{{ dateLabel(Record.RenewalNoticeDeadline) }}</div>
                    </div>
                    <div class="mjc-ov-kpi">
                        <div class="l">Auto-renew</div>
                        <div class="v">{{ Record.AutoRenew ? 'Yes' : 'No' }}</div>
                    </div>
                </div>

                <div class="mjc-ov-grid">
                    <article class="mjc-ov-card">
                        <header><i class="fa-solid fa-building"></i> Parties</header>
                        <div class="mjc-ov-facts">
                            <div>
                                <div class="l">Customer</div>
                                <div class="v">
                                    @if (Record.CustomerOrganizationID && CustomerName) {
                                        <button type="button" class="mjc-ov-link" (click)="OpenCustomer($event)">{{ CustomerName }}</button>
                                    } @else { {{ CustomerName || '—' }} }
                                </div>
                            </div>
                            <div>
                                <div class="l">Contact</div>
                                <div class="v">
                                    @if (Record.PrimaryContactPersonID && ContactName) {
                                        <button type="button" class="mjc-ov-link" (click)="OpenContact($event)">{{ ContactName }}</button>
                                    } @else { {{ ContactName || '—' }} }
                                </div>
                            </div>
                            <div><div class="l">Company</div><div class="v">{{ CompanyName || '—' }}</div></div>
                            <div><div class="l">Agreement</div><div class="v">{{ TemplateName || 'None' }}</div></div>
                        </div>
                    </article>
                    <article class="mjc-ov-card">
                        <header><i class="fa-solid fa-scale-balanced"></i> Obligation</header>
                        <div class="mjc-ov-facts">
                            <div><div class="l">Executed</div><div class="v">{{ dateLabel(Record.ExecutedDate) }}</div></div>
                            <div><div class="l">Effective</div><div class="v">{{ dateLabel(Record.EffectiveDate) }}</div></div>
                            <div><div class="l">Notice we owe</div><div class="v">{{ DaysLabel(Record.RenewalNoticeDays) }}</div></div>
                            <div><div class="l">Cancel window</div><div class="v">{{ DaysLabel(Record.CancellationWindowDays) }}</div></div>
                            <div><div class="l">Annual increase</div><div class="v">{{ IncreaseLabel }}</div></div>
                            @if (HasSource) {
                                <div><div class="l">Created from</div>
                                    <div class="v">
                                        @if (CanOpenSource) {
                                            <button type="button" class="mjc-ov-link" (click)="OpenSource($event)">{{ SourceLabel }}</button>
                                        } @else { {{ SourceLabel }} }
                                    </div>
                                </div>
                            }
                        </div>
                    </article>
                    <article class="mjc-ov-card mjc-ov-card--wide">
                        <header><i class="fa-solid fa-person-walking"></i> Next step</header>
                        @if (NextMove) {
                            <p class="mjc-ov-next">{{ NextMove }}</p>
                        } @else {
                            <p class="mjc-ov-empty">No action needed.</p>
                        }
                    </article>
                </div>
            </div>
        </mj-collapsible-panel>
    `,
    styles: [`
        .mjc-ov { display: flex; flex-direction: column; gap: var(--mj-space-4); padding: var(--mj-space-3) var(--mj-space-4) var(--mj-space-5); }
        .mjc-ov-health { display: flex; flex-direction: column; gap: var(--mj-space-2); }
        .mjc-ov-alert {
            display: flex; align-items: center; gap: var(--mj-space-2);
            padding: var(--mj-space-2) var(--mj-space-3);
            background: var(--mj-status-warning-bg); color: var(--mj-status-warning-text);
            border-radius: var(--mj-radius-md); font-size: var(--mj-text-sm); font-weight: 600;
        }
        .mjc-ov-ok {
            display: flex; align-items: center; gap: var(--mj-space-2);
            padding: var(--mj-space-2) var(--mj-space-3);
            background: var(--mj-status-success-bg); color: var(--mj-status-success-text);
            border-radius: var(--mj-radius-md); font-size: var(--mj-text-sm); font-weight: 600;
        }
        .mjc-ov-strip { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: var(--mj-space-3); }
        @media (max-width: 900px) { .mjc-ov-strip { grid-template-columns: 1fr 1fr; } }
        .mjc-ov-kpi {
            background: var(--mj-bg-page); border: 1px solid var(--mj-border-default);
            border-radius: var(--mj-radius-md); padding: var(--mj-space-3) var(--mj-space-4);
        }
        .mjc-ov-kpi .l {
            font-size: var(--mj-text-xs); text-transform: uppercase; letter-spacing: .04em;
            color: var(--mj-text-muted); font-weight: 700;
        }
        .mjc-ov-kpi .v { font-size: 1.35rem; font-weight: 800; letter-spacing: -.02em; margin-top: 4px; line-height: 1.2; }
        .mjc-ov-kpi .s { color: var(--mj-text-muted); font-size: var(--mj-text-sm); margin-top: 2px; }
        .mjc-ov-kpi[data-tone='warning'] .v { color: var(--mj-status-warning-text); }
        .mjc-ov-kpi[data-tone='success'] .v { color: var(--mj-status-success-text); }
        .mjc-ov-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--mj-space-3); }
        @media (max-width: 800px) { .mjc-ov-grid { grid-template-columns: 1fr; } }
        .mjc-ov-card {
            background: var(--mj-bg-page); border: 1px solid var(--mj-border-default);
            border-radius: var(--mj-radius-md); padding: var(--mj-space-3) var(--mj-space-4);
        }
        .mjc-ov-card--wide { grid-column: 1 / -1; }
        .mjc-ov-card header {
            display: flex; align-items: center; gap: 8px;
            font-weight: 700; margin-bottom: var(--mj-space-3); color: var(--mj-text-primary);
        }
        .mjc-ov-card header i { color: var(--mj-brand-primary); width: 1.1rem; text-align: center; }
        .mjc-ov-facts { display: grid; grid-template-columns: 1fr 1fr; gap: var(--mj-space-3); }
        .mjc-ov-facts .l {
            font-size: var(--mj-text-xs); text-transform: uppercase; letter-spacing: .04em;
            color: var(--mj-text-muted); font-weight: 700;
        }
        .mjc-ov-facts .v { font-weight: 650; margin-top: 2px; }
        .mjc-ov-link {
            border: 0; padding: 0; background: transparent; color: var(--mj-text-link);
            cursor: pointer; font: inherit; font-weight: 650; text-align: left;
        }
        .mjc-ov-link:hover { text-decoration: underline; }
        .mjc-ov-next { margin: 0; font-size: 1.05rem; font-weight: 650; }
        .mjc-ov-empty { color: var(--mj-text-muted); margin: 0; }
    `],
})
export class MJCContractOverviewPanel extends BaseFormPanel<ContractEntity> {
    public dateLabel = dateLabel;
    public get State(): ContractState { return (this.Record?.State as ContractState) || 'Draft'; }
    public get TypeName(): string { return this.Record?.ContractType ?? ''; }
    public get CustomerName(): string { return this.Record?.CustomerOrganization ?? ''; }
    public get ContactName(): string { return this.Record?.PrimaryContactPerson ?? ''; }
    public get CompanyName(): string { return this.Record?.Company ?? ''; }
    public get TemplateName(): string { return this.Record?.ContractTemplate ?? ''; }
    public get IncreaseLabel(): string {
        const n = this.Record?.AnnualIncreasePercent;
        return n == null ? '—' : `${n}%`;
    }
    public DaysLabel(n: number | null | undefined): string {
        return n == null ? '—' : `${n} days`;
    }
    public get StateTone(): 'success' | 'warning' | 'muted' {
        switch (this.State) {
            case 'Active':
            case 'Executed': return 'success';
            case 'Terminated': return 'warning';
            default: return 'muted';
        }
    }
    public get EndClock(): string {
        if (this.Record?.TerminatedDate) return 'Terminated';
        const d = this.Record?.DaysToEnd;
        if (d == null) return 'Undated';
        return endsInText(d).replace(/^in /, '').replace(/^ended /, '') || '—';
    }
    public get EndTone(): 'success' | 'warning' | 'muted' {
        const d = this.Record?.DaysToEnd;
        if (this.State === 'Active' && (d == null || d <= 120)) return 'warning';
        if (d != null && d < 0) return 'warning';
        if (this.State === 'Active') return 'success';
        return 'muted';
    }
    public get NoticeClock(): string {
        const d = this.Record?.RenewalNoticeDeadline;
        if (!d) return 'None';
        const days = noticeDays(this.Record);
        // The deadline is set but the derived count is absent — a row read without the wrapper view's
        // columns. Print the date rather than guess a countdown from a day this panel does not know.
        if (days == null) return dateLabel(d);
        if (days < 0) return `${Math.abs(days)}d past`;
        if (days === 0) return 'Today';
        return `${days}d`;
    }
    public get NoticeTone(): 'success' | 'warning' | 'muted' {
        const d = this.Record?.RenewalNoticeDeadline;
        if (!d) return 'muted';
        const days = noticeDays(this.Record);
        if (days != null && days <= 30) return 'warning';
        return 'muted';
    }
    public get HasSource(): boolean {
        return !!this.Record?.CreatingEntity;
    }
    public get CanOpenSource(): boolean {
        return !!(this.Record?.CreatingEntity && this.Record?.CreatingRecordID);
    }
    public get SourceLabel(): string {
        return this.Record?.CreatingEntity ?? '';
    }
    public get Health(): string[] {
        const out: string[] = [];
        if (!this.Record) return out;
        if (this.Record.IsAwaitingDocument) {
            out.push('Executed agreement not attached.');
        }
        if (this.Record.IsInCancellationWindow) {
            out.push('Cancellation window is open.');
        }
        const end = this.Record.DaysToEnd;
        if (end != null && end < 0 && !this.Record.TerminatedDate) {
            out.push('The term has ended and no termination date is recorded.');
        } else if (this.State === 'Active' && end != null && end <= 120) {
            out.push(`${termEndsText(end)}.`);
        }
        const notice = noticeDays(this.Record);
        if (notice != null && notice < 0) {
            out.push('Renewal notice deadline has already passed.');
        } else if (notice != null && notice <= 30) {
            out.push(`Renewal notice due by ${dateLabel(this.Record.RenewalNoticeDeadline)}.`);
        }
        if (this.Record.HasModifications) {
            out.push('Standard agreement was modified.');
        }
        if (this.State === 'Active' && !this.Record.EndDate) {
            out.push('Active with no end date.');
        }
        return out;
    }
    public get NextMove(): string | null {
        if (this.Record?.IsAwaitingDocument) return 'Attach the executed agreement.';
        if (this.Record?.IsInCancellationWindow) return 'Cancellation window is open. Confirm whether the customer is renewing.';
        const notice = noticeDays(this.Record);
        if (notice != null && notice <= 30) {
            return `Send the renewal notice. Deadline ${dateLabel(this.Record?.RenewalNoticeDeadline)}.`;
        }
        const end = this.Record?.DaysToEnd;
        if (this.State === 'Active' && end != null && end <= 120) {
            return `Begin renewal discussion. ${termEndsText(end)}.`;
        }
        if (this.Record?.HasModifications) return 'Review the modifications to the standard agreement.';
        return null;
    }

    public OpenCustomer(event: MouseEvent): void {
        this.open(event, MJC_FOREIGN_ENTITIES.Organization, this.Record?.CustomerOrganizationID);
    }
    public OpenContact(event: MouseEvent): void {
        this.open(event, MJC_FOREIGN_ENTITIES.Person, this.Record?.PrimaryContactPersonID);
    }
    public OpenSource(event: MouseEvent): void {
        const entity = this.Record?.CreatingEntity;
        const id = this.Record?.CreatingRecordID;
        if (!entity || !id) return;
        this.open(event, entity, id);
    }
    private open(event: MouseEvent, entity: string, id: string | null | undefined): void {
        if (!id) return;
        event.preventDefault();
        this.FormComponent.OnFormNavigate({
            Kind: 'record',
            EntityName: entity,
            PrimaryKey: CompositeKey.FromID(id),
            OpenInNewTab: event.ctrlKey || event.metaKey,
        });
    }
}

/**
 * Days until the renewal-notice deadline, TAKEN FROM THE VIEW (bc-aidp-next-golive#168).
 *
 * This used to be `daysUntil(Record.RenewalNoticeDeadline)`, a local re-derivation that read the
 * stored day from UTC parts — right — and then took "today" from the SERVER'S UTC clock, which is
 * already tomorrow for the whole American evening. `vwContracts` derives `DaysToEnd` and
 * `DaysUntilNoticeDeadline` from `bt.Today`, the BUSINESS day, so from 6 PM Central `NoticeClock`,
 * `NoticeTone`, `Health` and `NextMove` were one day ahead of the `DaysToEnd` printed beside them on
 * the same card — and `NextMove`'s `notice <= 30` cutoff fired a day early.
 *
 * REPLACED RATHER THAN CORRECTED. Reading the business zone on the client would make the two agree
 * only while a browser clock and a cached engine setting agreed with the database. The view already
 * computed the answer, in the same row, from the same `bt.Today` as everything else the card prints;
 * the second implementation was the defect, not its anchor. `DaysToEnd` was always read this way,
 * three lines above, which is why the two disagreed at all.
 */
function noticeDays(record: ContractEntity | null | undefined): number | null {
    return record?.DaysUntilNoticeDeadline ?? null;
}

/* ── Field sections ───────────────────────────────────────────────────────── */

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:agreement',
    skipNullKeyWarning: true,
    metadata: { entity: E, slot: 'after-fields', sortKey: 95, contributionKey: 'agreement' },
})
@Component({
    selector: 'mjc-contract-agreement-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    styles: [FIELD_STYLES],
    template: `
        <mj-collapsible-panel SectionKey="agreement" SectionName="Agreement" Icon="fa-solid fa-file-contract"
            [Form]="FormComponent" [FormContext]="FormContext">
            <div class="mjc-fields-grid">
                @for (f of Fields; track f.name) {
                    <div class="mjc-fg" [class.mjc-fg--span]="f.span">
                        <mj-form-field [Record]="Record" [ShowLabel]="true" [FieldName]="f.name" [Type]="f.type"
                            [EditMode]="f.readOnly ? false : EditMode" [FormContext]="FormContext"
                            [LinkType]="f.link ?? 'None'"
                            (ValueChange)="OnFieldValueChange($event)"
                            (Navigate)="FormComponent.OnFormNavigate($event)"></mj-form-field>
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractAgreementPanel extends BaseFormPanel<ContractEntity> implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    public readonly Fields: ContractFieldSpec[] = [
        { name: 'ContractNumber', type: 'textbox', readOnly: true },
        { name: 'ContractTypeID', type: 'textbox', link: 'Record' },
        { name: 'ContractTemplateID', type: 'textbox', link: 'Record' },
        { name: 'SigningProviderURL', type: 'textbox', link: 'URL' },
        { name: 'HasModifications', type: 'checkbox', readOnly: true },
        { name: 'Description', type: 'textarea', span: true },
    ];

    /**
     * The template ID this panel last put in the field — how it tells its own default from a choice.
     *
     * Session-local on purpose: it is never read from the record, because the record cannot say who
     * wrote a value into it. See `MayWriteDefaultTemplate`, which owns what it means.
     */
    private lastDefaultedID: string | null = null;

    /**
     * A contract that arrives with its type already set — Explorer's `NewRecordValues`, or a New
     * clicked from a type-scoped list — gets its template here, before the form is ever drawn.
     *
     * The commoner path is a person choosing the type by hand, which never reaches `ngOnInit` and is
     * why `OnFieldValueChange` exists too. Both call the same method; neither is sufficient alone.
     */
    public async ngOnInit(): Promise<void> {
        await this.defaultTemplate();
    }

    /**
     * Re-decide the template whenever the CONTRACT TYPE changes (golive #218).
     *
     * `mj-form-field` emits this from its value setter, so it fires for a person's edit and NOT for
     * the programmatic assignment below — writing `Record.ContractTemplateID` directly bypasses the
     * setter. That asymmetry is what keeps this from re-entering itself.
     */
    public async OnFieldValueChange(event: { FieldName: string }): Promise<void> {
        if (event?.FieldName !== 'ContractTypeID') return;
        await this.defaultTemplate();
    }

    /**
     * Put the current standard-terms version in the field, if we are allowed to.
     *
     * THE CHEAP HALF OF THE RULE RUNS FIRST. `RecordWantsDefaultTemplate` needs no database, and it
     * is false for every saved contract — so opening an existing agreement costs no extra query at
     * all, and the full rule is still evaluated in one place, on `ShouldDefaultTemplate`, before
     * anything is written.
     */
    private async defaultTemplate(): Promise<void> {
        const record = this.Record;
        if (!record) return;

        const state = {
            isSaved: record.IsSaved,
            currentTemplateID: record.ContractTemplateID,
            lastDefaultedID: this.lastDefaultedID,
        };
        if (!MayWriteDefaultTemplate(state)) return;

        const templateRequired = await this.typeRequiresTemplate(record.ContractTypeID);
        // A type we could not READ decides nothing in either direction — see typeRequiresTemplate.
        if (templateRequired === null) return;

        // A DEFAULT LEAVES WITH THE TYPE THAT SUPPLIED IT. Checked BEFORE the default, because the
        // two are mutually exclusive and this is the branch the first cut of this panel missed: it
        // stopped at `!ShouldDefaultTemplate` and left an Order Form's template sitting on a Change
        // Order, which saved without complaint.
        if (ShouldWithdrawDefaultTemplate({ ...state, templateRequired })) {
            record.ContractTemplateID = null;
            this.lastDefaultedID = null;
            this.cdr.detectChanges();
            return;
        }

        if (!ShouldDefaultTemplate({ ...state, templateRequired })) return;

        const templateID = await this.currentTemplateID();
        if (!templateID) return;

        record.ContractTemplateID = templateID;
        this.lastDefaultedID = templateID;
        // The FK editor reads its value off the record every pass and resolves the name it shows
        // asynchronously, so the label catches up on its own once this pass has run.
        this.cdr.detectChanges();
    }

    /**
     * Does the contract's current type say its terms live in a template — `TemplateRequired`?
     *
     * READ FROM THE FLAG, NEVER FROM THE TYPE'S NAME. The columns on `ContractType` exist precisely
     * so no code branches on a name someone can rename; `ContractEntityServer` reads the same flag
     * to decide whether to REQUIRE the template this defaults.
     *
     * THREE-WAY, AND THE THIRD CASE IS LOAD-BEARING. `false` now means "this type does not want a
     * template", which WITHDRAWS one this panel defaulted — so a read that failed must not be folded
     * into it. It was `boolean` while defaulting was the only outcome, where swallowing a failure as
     * `false` merely declined to act; under the withdrawal it would quietly take away a default on
     * the strength of a query that never answered.
     *
     *   · `true`  — the type requires a template
     *   · `false` — the type does not, or there is no type at all: both known answers
     *   · `null`  — could not tell, and the caller does nothing in either direction
     */
    private async typeRequiresTemplate(typeID: string | null | undefined): Promise<boolean | null> {
        const id = (typeID ?? '').trim();
        if (!id) return false; // no type chosen — a KNOWN answer, and the one that withdraws

        const { ScopedRunView } = await import('../data/provider');
        const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
        try {
            const r = await rv.RunView<{ TemplateRequired: boolean }>({
                EntityName: MJC_ENTITIES.ContractType,
                Fields: ['TemplateRequired'],
                ExtraFilter: `ID = '${id.replace(/'/g, "''")}'`,
                ResultType: 'simple',
            });
            if (r?.Success !== true || r.Results?.[0] === undefined) return null;
            return r.Results[0].TemplateRequired === true;
        } catch {
            return null;
        }
    }

    /**
     * The newest Published, usable template — the one a new contract should start on.
     *
     * A FAILED OR EMPTY READ IS SILENT, and deliberately so. This is a convenience: the field stays
     * empty, the picker still works, and the server still refuses a save with no template when the
     * type demands one — which is the message the user needs and the one they would already get.
     * Announcing "could not default a template" on a form nobody has filled in yet reports our own
     * plumbing as the user's problem.
     */
    private async currentTemplateID(): Promise<string | null> {
        const { ScopedRunView } = await import('../data/provider');
        const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
        try {
            const r = await rv.RunView<{ ID: string }>({
                EntityName: MJC_ENTITIES.ContractTemplate,
                Fields: ['ID'],
                ExtraFilter: CurrentTemplateFilter,
                OrderBy: CurrentTemplateOrderBy,
                MaxRows: 1,
                ResultType: 'simple',
            });
            return r?.Success ? (r.Results?.[0]?.ID ?? null) : null;
        } catch {
            return null;
        }
    }
}

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:parties',
    skipNullKeyWarning: true,
    metadata: {
        entity: E, slot: 'after-fields', sortKey: 92, contributionKey: 'parties',
        replacesSectionKey: 'stakeholders',
    },
})
@Component({
    selector: 'mjc-contract-parties-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    styles: [FIELD_STYLES],
    template: `
        <mj-collapsible-panel SectionKey="parties" SectionName="Parties" Icon="fa-solid fa-building"
            [Form]="FormComponent" [FormContext]="FormContext">
            <div class="mjc-fields-grid">
                @for (f of Fields; track f.name) {
                    <div class="mjc-fg" [class.mjc-fg--span]="f.span">
                        <mj-form-field [Record]="Record" [ShowLabel]="true" [FieldName]="f.name" [Type]="f.type"
                            [EditMode]="f.readOnly ? false : EditMode" [FormContext]="FormContext"
                            [LinkType]="f.link ?? 'None'"
                            (Navigate)="FormComponent.OnFormNavigate($event)"></mj-form-field>
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractPartiesPanel extends BaseFormPanel<ContractEntity> {
    /**
     * Record links on these fields emit `Navigate` from `mj-form-field`. That output must be
     * forwarded to `FormComponent.OnFormNavigate`, which Explorer maps onto
     * `NavigationService.OpenEntityRecord`. Without the binding the cells look like links and
     * do nothing — Overview's customer/contact buttons already go through this path.
     */
    public readonly Fields: ContractFieldSpec[] = [
        { name: 'CustomerOrganizationID', type: 'textbox', link: 'Record' },
        { name: 'PrimaryContactPersonID', type: 'textbox', link: 'Record' },
        { name: 'CompanyID', type: 'textbox', link: 'Record' },
    ];
}

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:notes',
    skipNullKeyWarning: true,
    metadata: {
        entity: E, slot: 'after-fields', sortKey: 80, contributionKey: 'notes',
        replacesSectionKey: 'notesAndMetadata',
    },
})
@Component({
    selector: 'mjc-contract-notes-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    styles: [FIELD_STYLES],
    template: `
        <mj-collapsible-panel SectionKey="notes" SectionName="Notes" Icon="fa-solid fa-align-left"
            [Form]="FormComponent" [FormContext]="FormContext">
            <div class="mjc-fields-grid">
                @for (f of Fields; track f.name) {
                    <div class="mjc-fg" [class.mjc-fg--span]="f.span">
                        <mj-form-field [Record]="Record" [ShowLabel]="true" [FieldName]="f.name" [Type]="f.type"
                            [EditMode]="f.readOnly ? false : EditMode" [FormContext]="FormContext"
                            [LinkType]="f.link ?? 'None'"
                            (Navigate)="FormComponent.OnFormNavigate($event)"></mj-form-field>
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractNotesPanel extends BaseFormPanel<ContractEntity> {
    public readonly Fields: ContractFieldSpec[] = [
        { name: 'Notes', type: 'textarea', span: true },
    ];
}

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:provenance',
    skipNullKeyWarning: true,
    metadata: {
        entity: E, slot: 'after-fields', sortKey: 35, contributionKey: 'origin',
        replacesSectionKey: 'provenance',
    },
})
@Component({
    selector: 'mjc-contract-provenance-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule, BaseFormsModule, MJComboboxComponent, MJButtonDirective, MJAlertComponent],
    styles: [FIELD_STYLES],
    template: `
        <mj-collapsible-panel SectionKey="origin" SectionName="Provenance" Icon="fa-solid fa-diagram-project"
            [Form]="FormComponent" [FormContext]="FormContext">
            <div class="mjc-fields-grid">
                @if (EditMode && ShowLookup) {
                    <div class="mjc-fg mjc-fg--span">
                        <!-- Mirrors mj-form-field's own markup (mj-forms-field / -label / -control) so this
                             reads as an ordinary form line. It cannot BE an mj-form-field: that binds ONE
                             field, and the whole point here is that the two halves move together. -->
                        <div class="mj-forms-field">
                            <label class="mj-forms-field-label">Source deal</label>
                            <div class="mj-forms-field-control">
                                @if (Locked) {
                                    <span class="mj-forms-field-value">
                                        {{ LockedSummary }}
                                        <span class="mjc-chip mjc-chip--muted">Already recorded</span>
                                    </span>
                                    <button mjButton variant="flat" size="sm" type="button" (click)="Unlock()">
                                        Change source
                                    </button>
                                    <div class="mjc-hint">
                                        This contract already records where it came from — usually the deal that
                                        closed it. Re-pointing that is rewriting history, so it takes a deliberate
                                        second click.
                                    </div>
                                } @else {
                                    <mj-combobox
                                        [Data]="Deals"
                                        TextField="Label"
                                        ValueField="ID"
                                        [ValuePrimitive]="true"
                                        [Filterable]="false"
                                        Placeholder="Search deals by name, number or customer…"
                                        [ngModel]="PickedDealID"
                                        (ngModelChange)="PickDeal($event)"
                                        (FilterChange)="Search($event)" />

                                    @if (PickedDealID) {
                                        <button mjButton variant="flat" size="sm" type="button" (click)="ClearSource()">
                                            Clear
                                        </button>
                                    }

                                    <div class="mjc-hint">
                                        Starts with this customer's deals; typing searches every deal by name,
                                        number or customer. Choosing one fills both fields below — Save commits them.
                                    </div>
                                    <!-- Said out loud, because the combobox's own empty state reads "No data
                                         found" — indistinguishable from a search that genuinely matched nothing. -->
                                    @if (Loading) { <div class="mjc-hint">Searching deals…</div> }
                                    @if (LoadError) { <mj-alert Variant="warning" Size="sm" [Message]="LoadError" /> }
                                    @if (ForeignSource) {
                                        <mj-alert Variant="warning" Size="sm"
                                            [Message]="'This contract’s source is not a deal — the fields below name the record it points at. Choosing a deal here replaces it.'" />
                                    }
                                }
                            </div>
                        </div>
                    </div>
                } @else if (EditMode) {
                    <div class="mjc-fg mjc-fg--span">
                        <div class="mjc-hint">
                            No deal lookup here: this installation has no Deals entity, or you cannot read it.
                            The fields below stay read-only rather than offering two ids to type by hand.
                        </div>
                    </div>
                }
                @for (f of Fields; track f.name) {
                    <div class="mjc-fg" [class.mjc-fg--span]="f.span">
                        <mj-form-field [Record]="Record" [ShowLabel]="true" [FieldName]="f.name" [Type]="f.type"
                            [EditMode]="f.readOnly ? false : EditMode" [FormContext]="FormContext"
                            [LinkType]="f.link ?? 'None'"
                            (Navigate)="FormComponent.OnFormNavigate($event)"></mj-form-field>
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractProvenanceFieldsPanel extends BaseFormPanel<ContractEntity> {
    private readonly cdr = inject(ChangeDetectorRef);

    /**
     * THE RAW IDS STAY, AND STAY READ-ONLY. The lookup above is what WRITES them (golive #219).
     *
     * ── WHY THEY WERE READ-ONLY, WHICH HAS NOT CHANGED ────────────────────────────────────────
     *
     * `CreatingEntityID` is a real FK to `__mj.Entity` and `CreatingRecordID` is the row it names, under
     * `CK_Contract_CreatingPairBothOrNeither` — both or neither. Rendered as two ordinary inputs
     * (contracts#28 item 18) they produced exactly the two failures the shape invites: editing one
     * alone is a save the constraint refuses, and editing both silently re-points a contract's
     * provenance at an unrelated record. `CTR-000026` still carries the evidence — a hand-typed pair
     * naming `MJ: Explorer Navigation Items` with a record id that is not a UUID.
     *
     * ── WHAT #219 ADDS, AND WHY IT IS NOT A REVERSAL ──────────────────────────────────────────
     *
     * Story C-US1 says finance may attach a MANUALLY created contract to an existing deal. Item 18's
     * read-only made that impossible: the Close Won seam became not just the preferred writer but the
     * only one, and a contract typed in by hand could never show its deal. The answer is not to reopen
     * the fields — it is to write them through a control that cannot produce a half pair. The lookup
     * sets both halves from one chosen deal and clears both together; these two remain what they became
     * in item 18, a read-only audit of what the pair actually holds, sitting under a human-readable name.
     *
     * The SECTION is likewise kept rather than hidden (item 18 asked for it gone, on the premise that
     * the hero's Source Deal stat replaces it). With #219 that premise becomes true for deals — but the
     * pair is polymorphic and the stat renders only what it can resolve, so the ids stay as the one
     * place a reader can see the provenance verbatim, which is item 3 of #219.
     */
    public readonly Fields: ContractFieldSpec[] = [
        { name: 'CreatingEntityID', type: 'textbox', link: 'Record', readOnly: true },
        { name: 'CreatingRecordID', type: 'textbox', readOnly: true },
    ];

    /** Options for the picker. Never read directly — go through the `Deals` getter, which loads. */
    private _deals: DealChoice[] = [];
    /** Bound to the combobox. Mirrors `CreatingRecordID`, and is '' whenever the source is not a deal. */
    public PickedDealID = '';
    public Loading = false;
    /** Why the list is empty, when the reason is a failure rather than genuinely nothing. */
    public LoadError = '';
    /** The pair names a record of some OTHER entity — surfaced rather than silently shown as blank. */
    public ForeignSource = false;
    /** This contract arrived with provenance already recorded, so re-pointing takes a second click. */
    public Locked = false;
    /** Label of the deal currently linked, for the locked line. */
    public SelectedLabel = '';

    /**
     * Which contract the picker was loaded for — not merely whether it was.
     *
     * The form reuses one component instance as it navigates, so a boolean leaves the PREVIOUS
     * contract's candidates in the dropdown: a list scoped to the previous customer, which is a wrong
     * list rather than a stale one. Same defect, same fix, as the Supersedes picker (contracts#28
     * item 23).
     */
    private loadedFor: string | null = null;
    private searchTimer: ReturnType<typeof setTimeout> | null = null;

    /**
     * Is there a Deals entity this user can see?
     *
     * Resolved from METADATA BY NAME, never imported: sales depends on contracts, so this app may not
     * depend on sales (see `MJC_FOREIGN_ENTITIES.Deal`). A host without sales installed, or a user
     * without read permission, simply gets no picker — the read-only ids and the hint below say so
     * rather than rendering a control that can find nothing.
     */
    public get DealLookupAvailable(): boolean {
        return !!this.dealEntityID();
    }

    /**
     * Whether to render the lookup — AND the panel's single load trigger.
     *
     * `BaseFormPanel` has no lifecycle hook and the slot host sets `Record` before view init, so the
     * first template read is the earliest reliable moment to do per-record work. This is the FIRST
     * thing the template reads, which is the whole reason the trigger lives here rather than on
     * `Deals`: the options are read inside the unlocked branch only, so a contract that arrives with
     * provenance would never read them, `syncFromRecord()` would never run, and `Locked` would never
     * become true — the guard silently absent on exactly the records it exists to protect.
     *
     * Keyed on the record so navigating the form to another contract re-syncs and reloads.
     */
    public get ShowLookup(): boolean {
        if (!this.DealLookupAvailable) return false;
        const key = this.Record?.ID ?? 'new';
        if (this.loadedFor !== key) {
            this.loadedFor = key;
            this.syncFromRecord();
            void this.load('');
        }
        return true;
    }

    /** The candidate deals. Loaded by {@link ShowLookup}; this is a plain read. */
    public get Deals(): DealChoice[] {
        return this._deals;
    }

    /**
     * What the locked line says about the existing link.
     *
     * Deliberately does NOT claim the Close Won automation set it: nothing on the row records who
     * did, and a contract linked by hand, saved and reopened arrives locked the same way. The panel
     * says what it can actually see — the deal's name when the list has it, that the source is not a
     * deal when the entity half says so, and otherwise nothing more than that something is linked.
     * The raw ids sit directly below either way.
     */
    public get LockedSummary(): string {
        if (this.SelectedLabel) return this.SelectedLabel;
        if (this.ForeignSource) return 'Linked to a record that is not a deal';
        return 'A source record is already linked';
    }

    /** Release the re-point guard. Deliberate, and only ever by a click. */
    public Unlock(): void {
        this.Locked = false;
    }

    /**
     * Take a chosen deal — and write BOTH halves of the pair, always.
     *
     * This is the whole reason the control exists. There is no path here that sets one column: a
     * chosen deal writes the Deals entity id together with the deal's own id, and an empty selection
     * goes through {@link ClearSource}, which empties both. The database's both-or-neither constraint
     * (and the validator CodeGen derives from it) can therefore never be the thing that reports a
     * mistake this form allowed a person to make.
     */
    public PickDeal(dealID: string | null | undefined): void {
        const entityID = this.dealEntityID();
        const id = (dealID ?? '').trim();
        if (!entityID || !this.Record) return;
        if (!id) { this.ClearSource(); return; }

        this.Record.CreatingEntityID = entityID;
        this.Record.CreatingRecordID = id;
        this.PickedDealID = id;
        this.ForeignSource = false;
        this.SelectedLabel = this._deals.find((d) => d.ID === id)?.Label ?? '';
    }

    /** Empty BOTH halves. The constraint's other legal state, and #219's third acceptance criterion. */
    public ClearSource(): void {
        if (!this.Record) return;
        this.Record.CreatingEntityID = null;
        this.Record.CreatingRecordID = null;
        this.PickedDealID = '';
        this.ForeignSource = false;
        this.SelectedLabel = '';
    }

    /**
     * Re-query as the user types, debounced.
     *
     * SERVER-SIDE, with the combobox's own `Filterable` off. Client filtering would need every deal in
     * the database loaded to be correct, and it filters on the option LABEL — so a search that matched
     * a customer whose name the label abbreviates would hide rows the server just returned. One
     * authority for what matches, and it is the query.
     */
    public Search(text: string): void {
        if (this.searchTimer) clearTimeout(this.searchTimer);
        // Long enough that a typed word is one read, short enough to feel immediate.
        this.searchTimer = setTimeout(() => void this.load(text), 250);
    }

    /** The Deals entity's id, or null when this installation has no such entity. */
    private dealEntityID(): string | null {
        const entities = this.FormComponent?.ProviderToUse?.Entities;
        return entities?.find((e) => e.Name === MJC_FOREIGN_ENTITIES.Deal)?.ID ?? null;
    }

    /**
     * Read the record's pair into the control's own state.
     *
     * The pair is POLYMORPHIC, so "there is a `CreatingRecordID`" does not mean "a deal is selected".
     * Pre-selecting on the record id alone would show an unrelated record's id as the chosen deal; the
     * entity half has to agree first, and when it does not, `ForeignSource` says so out loud.
     *
     * `Locked` is captured HERE — from what the record ARRIVED with — and never recomputed live. A
     * live "already set, so lock it" would re-lock the instant a user picked a deal, which is the
     * guard eating the very edit it was there to confirm.
     */
    private syncFromRecord(): void {
        const entityID = this.Record?.CreatingEntityID ?? null;
        const recordID = this.Record?.CreatingRecordID ?? null;
        const dealEntityID = this.dealEntityID();
        const isDeal = !!entityID && !!dealEntityID && entityID.toLowerCase() === dealEntityID.toLowerCase();

        this.PickedDealID = isDeal ? String(recordID ?? '') : '';
        this.ForeignSource = !!entityID && !isDeal;
        this.Locked = !!entityID && !!recordID;
        this.SelectedLabel = '';
    }

    /**
     * Load the options.
     *
     * With nothing typed this is the contract's customer's deals — #219 item 2's "prefer deals for the
     * contract's customer organization" — ORed with the deal already linked, so a contract pointed at
     * a deal outside its customer still shows what it is pointed AT rather than a blank box. Typing
     * widens the search to every deal by name, number or customer. The clauses themselves live in
     * `@mj-biz-apps/contracts-entities`, where they can be unit-tested without Angular.
     */
    private async load(searchText: string): Promise<void> {
        if (!this.DealLookupAvailable) return;
        this.Loading = true;
        this.LoadError = '';
        try {
            const { ScopedRunView } = await import('../data/provider');
            const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
            const search = (searchText ?? '').trim();
            const filter = search
                ? DealSearchClause(null, search)
                : `(${DealSearchClause(this.Record?.CustomerOrganizationID)}) OR (${DealIDClause(this.Record?.CreatingRecordID)})`;

            const r = await rv.RunView<DealOption>({
                EntityName: MJC_FOREIGN_ENTITIES.Deal,
                Fields: ['ID', 'DealNumber', 'Name', 'Account'],
                ExtraFilter: filter,
                OrderBy: 'Name ASC',
                MaxRows: 100,
                ResultType: 'simple',
            });
            if (!r?.Success) throw new Error(r?.ErrorMessage || 'The deals could not be read.');

            this._deals = (r.Results ?? []).map((d) => ({ ...d, Label: DealOptionLabel(d) }));
            this.SelectedLabel = this._deals.find((d) => d.ID === this.PickedDealID)?.Label ?? this.SelectedLabel;
        } catch (e) {
            this._deals = [];
            this.LoadError = e instanceof Error ? e.message : String(e);
        } finally {
            this.Loading = false;
            this.cdr.detectChanges();
        }
    }
}

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:lifecycle-fields',
    skipNullKeyWarning: true,
    metadata: {
        entity: E, slot: 'after-fields', sortKey: 50, contributionKey: 'lifecycle',
        replacesSectionKey: 'contractLifecycle',
    },
})
@Component({
    selector: 'mjc-contract-lifecycle-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    styles: [FIELD_STYLES],
    template: `
        <mj-collapsible-panel SectionKey="lifecycle" SectionName="Change orders" Icon="fa-solid fa-code-branch"
            [Form]="FormComponent" [FormContext]="FormContext">
            <div class="mjc-fields-grid">
                @for (f of Fields; track f.name) {
                    <div class="mjc-fg" [class.mjc-fg--span]="f.span">
                        <mj-form-field [Record]="Record" [ShowLabel]="true" [FieldName]="f.name" [Type]="f.type"
                            [EditMode]="f.readOnly ? false : EditMode" [FormContext]="FormContext"
                            [LinkType]="f.link ?? 'None'"
                            (Navigate)="FormComponent.OnFormNavigate($event)"></mj-form-field>
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractLifecyclePanel extends BaseFormPanel<ContractEntity> {
    public readonly Fields: ContractFieldSpec[] = [
        { name: 'ParentContractID', type: 'textbox', link: 'Record' },
        { name: 'SupersededByContractID', type: 'textbox', link: 'Record', readOnly: true },
    ];
}

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:related-modifications',
    skipNullKeyWarning: true,
    metadata: {
        entity: E, slot: 'after-related', sortKey: 70, contributionKey: 'modifications',
        relatedEntity: MJC_ENTITIES.ContractTemplateModification, relatedJoinField: 'ContractID',
    },
})
@Component({
    selector: 'mjc-contract-modifications-panel',
    standalone: true,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <mj-collapsible-panel SectionKey="modifications" SectionName="Modifications" Icon="fa-solid fa-file-circle-exclamation"
            Variant="related-entity" [Form]="FormComponent" [FormContext]="FormContext" [DefaultExpanded]="false"
            [BadgeCount]="FormComponent.GetSectionRowCount('modifications')">
            @if (Record.IsSaved) {
                <mj-explorer-entity-data-grid
                    [Params]="FormComponent.BuildRelationshipViewParamsByEntityName(Entity, 'ContractID')"
                    [NewRecordValues]="FormComponent.NewRecordValues(Entity, 'ContractID')"
                    [AllowLoad]="FormComponent.IsSectionExpanded('modifications')"
                    [ShowToolbar]="true"
                    (Navigate)="FormComponent.OnFormNavigate($event)"
                    (AfterDataLoad)="OnDataLoad($event)">
                </mj-explorer-entity-data-grid>
            }
        </mj-collapsible-panel>
    `,
})
export class MJCContractModificationsPanel extends BaseFormPanel<ContractEntity> {
    public readonly Entity = MJC_ENTITIES.ContractTemplateModification;
    public OnDataLoad(event: AfterDataLoadEventArgs): void {
        this.FormComponent.SetSectionRowCount('modifications', event.totalRowCount);
    }
}
