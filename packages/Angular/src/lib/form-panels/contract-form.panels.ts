/**
 * @fileoverview Contract form body — Overview plus organized rail sections.
 *
 * Replaces leftover generated field dumps (Contract Details, Stakeholders, Provenance,
 * Lifecycle, Notes) with:
 *   Overview (exec briefing) · Agreement · Parties · Dates · Renewal · Notes
 *   Modifications · Documents · Lineage · Re-papering · Provenance
 *
 * Dates / Renewal / Documents / Lineage / Re-papering already live in sibling files.
 * `contributionKey` equals each panel's `SectionKey`. Overview is the only
 * `inclusion: 'Primary'` so it leads; the rest sort into the related band by sortKey.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { Component, ViewEncapsulation } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CompositeKey } from '@memberjunction/core';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import type { AfterDataLoadEventArgs } from '@memberjunction/ng-entity-viewer';
import { ContractEntity, type ContractState } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from '../data/entity-names';

const E = MJC_ENTITIES.Contract;

type ContractFieldType =
    | 'textbox' | 'textarea' | 'number' | 'datepicker' | 'checkbox'
    | 'select' | 'autocomplete' | 'code' | 'dropdownlist' | 'numerictextbox';

interface ContractFieldSpec {
    name: string;
    type: ContractFieldType;
    link?: 'Record' | 'URL';
    span?: boolean;
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

function dateLabel(d: Date | string | null | undefined): string {
    if (!d) return '—';
    return new Date(d).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
}

function endsInText(days: number | null | undefined): string {
    if (days == null) return '';
    if (days < 0) return `ended ${Math.abs(days)} days ago`;
    if (days === 0) return 'ends today';
    if (days < 60) return `in ${days} days`;
    const months = Math.round(days / 30);
    return `in ${months} month${months === 1 ? '' : 's'}`;
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
                        Nothing on this agreement is asking for a person.
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
                        <div class="s">{{ Record.AutoRenew ? 'as the paper states' : 'someone must act' }}</div>
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
                            <div><div class="l">Selling as</div><div class="v">{{ CompanyName || '—' }}</div></div>
                            <div><div class="l">Agreement</div><div class="v">{{ TemplateName || 'no standard terms' }}</div></div>
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
                            <div><div class="l">Created from</div>
                                <div class="v">
                                    @if (CanOpenSource) {
                                        <button type="button" class="mjc-ov-link" (click)="OpenSource($event)">{{ SourceLabel }}</button>
                                    } @else { {{ SourceLabel }} }
                                </div>
                            </div>
                        </div>
                    </article>
                    <article class="mjc-ov-card mjc-ov-card--wide">
                        <header><i class="fa-solid fa-person-walking"></i> What needs a person</header>
                        @if (NextMove) {
                            <p class="mjc-ov-next">{{ NextMove }}</p>
                        } @else {
                            <p class="mjc-ov-empty">No action sitting on this agreement right now.</p>
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
        const days = daysUntil(d);
        if (days == null) return dateLabel(d);
        if (days < 0) return `${Math.abs(days)}d past`;
        if (days === 0) return 'Today';
        return `${days}d`;
    }
    public get NoticeTone(): 'success' | 'warning' | 'muted' {
        const d = this.Record?.RenewalNoticeDeadline;
        if (!d) return 'muted';
        const days = daysUntil(d);
        if (days != null && days <= 30) return 'warning';
        return 'muted';
    }
    public get CanOpenSource(): boolean {
        return !!(this.Record?.CreatingEntity && this.Record?.CreatingRecordID);
    }
    public get SourceLabel(): string {
        if (!this.Record?.CreatingEntity) return 'Entered directly';
        return this.Record.CreatingEntity;
    }
    public get Health(): string[] {
        const out: string[] = [];
        if (!this.Record) return out;
        if (this.Record.IsAwaitingDocument) {
            out.push('This type expects an executed document and none is attached.');
        }
        if (this.Record.IsInCancellationWindow) {
            out.push('The cancellation window is open — a customer can walk without renewing.');
        }
        const end = this.Record.DaysToEnd;
        if (end != null && end < 0 && !this.Record.TerminatedDate) {
            out.push('The term has ended and no termination date is recorded.');
        } else if (this.State === 'Active' && end != null && end <= 120) {
            out.push(`Term ends ${endsInText(end)} — this belongs on the renewals watchlist.`);
        }
        const notice = daysUntil(this.Record.RenewalNoticeDeadline);
        if (notice != null && notice < 0) {
            out.push('Renewal notice deadline has already passed.');
        } else if (notice != null && notice <= 30) {
            out.push(`We owe written notice by ${dateLabel(this.Record.RenewalNoticeDeadline)}.`);
        }
        if (this.Record.HasModifications) {
            out.push('The standard agreement was modified — read the paper.');
        }
        if (this.State === 'Active' && !this.Record.EndDate) {
            out.push('Active with no end date — the watchlist cannot see this.');
        }
        return out;
    }
    public get NextMove(): string | null {
        if (this.Record?.IsAwaitingDocument) return 'Attach the executed document. Finance cannot process paper they cannot see.';
        if (this.Record?.IsInCancellationWindow) return 'Cancellation window is open. Confirm whether this renews or walks.';
        const notice = daysUntil(this.Record?.RenewalNoticeDeadline);
        if (notice != null && notice <= 30) {
            return `Send the renewal notice. Deadline ${dateLabel(this.Record?.RenewalNoticeDeadline)}.`;
        }
        const end = this.Record?.DaysToEnd;
        if (this.State === 'Active' && end != null && end <= 120) {
            return `Start the renewal conversation. Term ends ${endsInText(end)}.`;
        }
        if (this.Record?.HasModifications) return 'Read the deviations before anyone treats this as a standard agreement.';
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

function daysUntil(d: Date | string | null | undefined): number | null {
    if (!d) return null;
    const iso = d instanceof Date
        ? `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`
        : String(d).slice(0, 10);
    const t = Date.parse(`${iso}T00:00:00Z`);
    if (!Number.isFinite(t)) return null;
    const now = new Date();
    const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    return Math.round((t - today) / 86_400_000);
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
                            [EditMode]="EditMode" [FormContext]="FormContext" [LinkType]="f.link ?? 'None'"
                            (Navigate)="FormComponent.OnFormNavigate($event)"></mj-form-field>
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractAgreementPanel extends BaseFormPanel<ContractEntity> {
    public readonly Fields: ContractFieldSpec[] = [
        { name: 'ContractNumber', type: 'textbox' },
        { name: 'ContractTypeID', type: 'textbox', link: 'Record' },
        { name: 'ContractTemplateID', type: 'textbox', link: 'Record' },
        { name: 'SigningProviderURL', type: 'textbox', link: 'URL' },
        { name: 'HasModifications', type: 'checkbox' },
        { name: 'Description', type: 'textarea', span: true },
    ];
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
                            [EditMode]="EditMode" [FormContext]="FormContext" [LinkType]="f.link ?? 'None'"
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
                            [EditMode]="EditMode" [FormContext]="FormContext" [LinkType]="f.link ?? 'None'"
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
    imports: [CommonModule, BaseFormsModule],
    styles: [FIELD_STYLES],
    template: `
        <mj-collapsible-panel SectionKey="origin" SectionName="Provenance" Icon="fa-solid fa-diagram-project"
            [Form]="FormComponent" [FormContext]="FormContext">
            <div class="mjc-fields-grid">
                @for (f of Fields; track f.name) {
                    <div class="mjc-fg" [class.mjc-fg--span]="f.span">
                        <mj-form-field [Record]="Record" [ShowLabel]="true" [FieldName]="f.name" [Type]="f.type"
                            [EditMode]="EditMode" [FormContext]="FormContext" [LinkType]="f.link ?? 'None'"
                            (Navigate)="FormComponent.OnFormNavigate($event)"></mj-form-field>
                    </div>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractProvenanceFieldsPanel extends BaseFormPanel<ContractEntity> {
    public readonly Fields: ContractFieldSpec[] = [
        { name: 'CreatingEntityID', type: 'textbox', link: 'Record' },
        { name: 'CreatingRecordID', type: 'textbox' },
    ];
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
                            [EditMode]="EditMode" [FormContext]="FormContext" [LinkType]="f.link ?? 'None'"
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
        { name: 'SupersededByContractID', type: 'textbox', link: 'Record' },
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
