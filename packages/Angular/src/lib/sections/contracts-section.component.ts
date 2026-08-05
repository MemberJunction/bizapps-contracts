/**
 * @fileoverview The Contracts Explorer tabs — the roster, the contract workspace, and the billing
 * worklist. These are the mockups in `design-docs/ui-design/mockups/` rendered against live data.
 *
 * Each class is registered with `@RegisterClass(BaseResourceComponent, '<DriverClass>')` under the
 * name the Application's `DefaultNavItems` references in
 * `metadata/applications/.contracts-application.json`. That pairing IS the wiring — metadata without
 * a registered class gives a dead tab, a registered class without metadata never appears, and
 * neither half errors on its own.
 *
 * WHAT IS HAND-BUILT AND WHAT IS NOT. Tabular sections render `<mj-explorer-entity-data-grid>`, the
 * same component bizapps-orders uses in ~85 places: we inherit sorting, paging, the toolbar, column
 * formatting and — the part that matters — `NavigateOnDoubleClick`, so opening a row in the record
 * viewer is native behaviour we did not write. What IS hand-built is only what a generic grid cannot
 * express: the roster's health strip, the identity band, the term timeline, and the selection context
 * that decides which child grid is looking at what.
 *
 * DATA ACCESS is `RunView`/`RunViews` only (master plan §11.1). Reads that only display use
 * `ResultType: 'simple'` with an explicit `Fields` list — entity objects would pay for mutation
 * machinery nothing here uses.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClass } from '@memberjunction/global';
import { BaseResourceComponent } from '@memberjunction/ng-shared';
import { BaseFormsModule } from '@memberjunction/ng-base-forms';
import { RunView, type RunViewParams } from '@memberjunction/core';
import type { ResourceData } from '@memberjunction/core-entities';
import type { AfterRowClickEventArgs } from '@memberjunction/ng-entity-viewer';

const ENTITY_CONTRACTS = 'MJ_BizApps_Contracts: Contracts';
const ENTITY_TERMS = 'MJ_BizApps_Contracts: Contract Terms';
const ENTITY_LINES = 'MJ_BizApps_Contracts: Contract Lines';
const ENTITY_SCHEDULES = 'MJ_BizApps_Contracts: Contract Billing Schedules';
const ENTITY_EVENTS = 'MJ_BizApps_Contracts: Contract Billing Events';
const ENTITY_COMMITMENTS = 'MJ_BizApps_Contracts: Contract Commitments';
const ENTITY_AMENDMENTS = 'MJ_BizApps_Contracts: Contract Amendments';
const ENTITY_EVENTLOG = 'MJ_BizApps_Contracts: Contract Events';

interface ContractRow {
    ID: string;
    ContractNumber: string;
    Status: string;
    Description: string | null;
    EffectiveDate: string | null;
    ExecutedDate: string | null;
    PricedAt: string | null;
    AutoRenew: boolean;
    CancellationWindowDays: number | null;
    ExternalReferenceID: string | null;
}

interface TermRow {
    ID: string;
    ContractID: string;
    TermNumber: number;
    Status: string;
    StartDate: string | null;
    EndDate: string | null;
    CommittedAmount: number | null;
    EscalationPercent: number | null;
    MaxEscalationPercent: number | null;
    RenewalNoticeDays: number | null;
    EscalationBasis: string | null;
    BillingFrequency: string | null;
    RenewalProbability: number | null;
    ExecutedDate: string | null;
}

interface EventRow {
    ID: string;
    ContractTermID: string;
    ScheduledDate: string | null;
    Status: string;
    ComputedAmount: number | null;
    FailureReason: string | null;
}

/** Shared look for both tabs — MJ tokens with fallbacks, so it tracks the host theme. */
const SHARED_STYLES = `
    :host { display:block; height:100%; overflow:auto; background:var(--mj-bg-page,#f8fafc); color:var(--mj-text-primary,#1e293b); }
    .wrap { padding:20px 24px 40px; }
    .head { display:flex; align-items:flex-start; gap:16px; margin-bottom:18px; }
    .head h1 { margin:0; font-size:20px; font-weight:700; letter-spacing:-.01em; display:flex; align-items:center; gap:10px; }
    .head .eyebrow { font-size:12px; font-weight:600; letter-spacing:.05em; text-transform:uppercase; color:var(--mj-text-secondary,#475569); margin-bottom:3px; }
    .head .sub { margin:4px 0 0; font-size:13px; color:var(--mj-text-secondary,#475569); max-width:80ch; }
    .head .actions { margin-left:auto; display:flex; gap:8px; }
    .btn { display:inline-flex; align-items:center; gap:7px; height:32px; padding:0 13px; border-radius:var(--mj-radius-md,6px);
           border:1px solid var(--mj-border-strong,#cbd5e1); background:var(--mj-bg-surface,#fff); color:inherit;
           font-size:13px; font-weight:600; font-family:inherit; cursor:pointer; }
    .btn:hover { background:var(--mj-bg-surface-hover,#f1f5f9); }
    .btn.primary { background:var(--mj-brand-primary,#0076b6); border-color:var(--mj-brand-primary,#0076b6); color:#fff; }
    .kpis { display:grid; grid-template-columns:repeat(4,1fr); gap:12px; margin-bottom:18px; }
    .kpi { background:var(--mj-bg-surface,#fff); border:1px solid var(--mj-border-default,#e2e8f0); border-radius:var(--mj-radius-lg,10px); padding:13px 15px; }
    .kpi .label { font-size:11.5px; font-weight:700; letter-spacing:.05em; text-transform:uppercase; color:var(--mj-text-muted,#64748b); }
    .kpi .value { font-size:24px; font-weight:700; margin-top:5px; letter-spacing:-.02em; }
    .kpi .value.warn { color:var(--mj-status-warning-text,#b45309); }
    .kpi .value.err { color:var(--mj-status-error-text,#b91c1c); }
    .kpi .foot { font-size:12px; color:var(--mj-text-secondary,#475569); margin-top:3px; }
    .card { background:var(--mj-bg-surface,#fff); border:1px solid var(--mj-border-default,#e2e8f0); border-radius:var(--mj-radius-lg,10px); overflow:hidden; margin-bottom:16px; }
    .card-head { display:flex; align-items:center; gap:10px; padding:12px 16px; border-bottom:1px solid var(--mj-border-subtle,#f1f5f9); font-weight:700; font-size:13.5px; }
    .card-head .right { margin-left:auto; font-weight:400; font-size:12.5px; color:var(--mj-text-secondary,#475569); }
    .searchrow { padding:12px 16px; display:flex; gap:8px; align-items:center; flex-wrap:wrap; border-bottom:1px solid var(--mj-border-subtle,#f1f5f9); }
    input.f, select.f { height:32px; padding:0 10px; border:1px solid var(--mj-border-strong,#cbd5e1); border-radius:var(--mj-radius-md,6px);
                        font-size:13px; font-family:inherit; background:var(--mj-bg-surface,#fff); color:inherit; }
    input.f { min-width:260px; flex:1; }
    .badge { display:inline-flex; align-items:center; gap:5px; height:22px; padding:0 9px; border-radius:999px; font-size:11.5px; font-weight:700; white-space:nowrap;
             background:var(--mj-color-neutral-100,#f1f5f9); color:var(--mj-text-secondary,#475569); }
    .badge.ok { background:var(--mj-status-success-bg,#f0fdf4); color:var(--mj-status-success-text,#15803d); }
    .badge.warn { background:var(--mj-status-warning-bg,#fffbeb); color:var(--mj-status-warning-text,#b45309); }
    .badge.err { background:var(--mj-status-error-bg,#fef2f2); color:var(--mj-status-error-text,#b91c1c); }
    .badge.info { background:var(--mj-status-info-bg,#eff6ff); color:var(--mj-status-info-text,#1d4ed8); }
    .empty { padding:26px 16px; text-align:center; color:var(--mj-text-muted,#64748b); font-size:13px; }
    .tabs { display:flex; gap:2px; border-bottom:1px solid var(--mj-border-default,#e2e8f0); padding:0 16px; overflow-x:auto; background:var(--mj-bg-surface,#fff); }
    .tabs button { border:none; background:transparent; font-family:inherit; font-size:13.5px; font-weight:600; color:var(--mj-text-secondary,#475569);
                   padding:11px 13px; cursor:pointer; border-bottom:2px solid transparent; white-space:nowrap; }
    .tabs button:hover { color:var(--mj-text-primary,#1e293b); }
    .tabs button.active { color:var(--mj-brand-primary,#0076b6); border-bottom-color:var(--mj-brand-primary,#0076b6); }
    .tabs button .n { font-size:11px; font-weight:700; background:var(--mj-color-neutral-100,#f1f5f9); border-radius:9px; padding:1px 6px; margin-left:6px; }
    .ident { display:flex; align-items:center; gap:10px; padding:13px 16px; border-bottom:1px solid var(--mj-border-subtle,#f1f5f9); flex-wrap:wrap; }
    .ident .name { font-size:16px; font-weight:700; letter-spacing:-.01em; }
    .grid2 { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:12px 20px; padding:16px; }
    .fld { display:flex; flex-direction:column; gap:3px; min-width:0; }
    .fld .k { font-size:11.5px; font-weight:600; color:var(--mj-text-secondary,#475569); }
    .fld .v { font-size:13.5px; font-weight:600; }
    .tl { padding:8px 16px 16px; }
    .tl-row { display:grid; grid-template-columns:104px 1fr; gap:14px; padding:11px 0; border-bottom:1px solid var(--mj-border-subtle,#f1f5f9); }
    .tl-row:last-child { border-bottom:none; }
    .tl-when { font-size:12px; color:var(--mj-text-secondary,#475569); }
    .tl-bar { height:26px; border-radius:var(--mj-radius-sm,4px); background:var(--mj-color-neutral-100,#f1f5f9); overflow:hidden; display:flex; }
    .tl-fill { display:flex; align-items:center; padding:0 9px; font-size:12px; font-weight:600; color:#fff; }
    .tl-fill.done { background:var(--mj-color-neutral-400,#94a3b8); }
    .tl-fill.active { background:var(--mj-brand-primary,#0076b6); }
    .tl-fill.future { background:var(--mj-color-neutral-300,#cbd5e1); color:var(--mj-text-secondary,#475569); }
    .tl-meta { margin-top:6px; font-size:12px; color:var(--mj-text-secondary,#475569); display:flex; gap:14px; flex-wrap:wrap; }
    .note { display:flex; gap:10px; padding:11px 13px; border-radius:var(--mj-radius-md,6px); font-size:12.5px; line-height:1.5; margin:12px 16px; }
    .note.err { background:var(--mj-status-error-bg,#fef2f2); color:var(--mj-status-error-text,#b91c1c); }
    .note.info { background:var(--mj-status-info-bg,#eff6ff); color:var(--mj-status-info-text,#1d4ed8); }
    .mono { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size:12.5px; }
    .muted { color:var(--mj-text-muted,#64748b); }
`;

/** Maps every status vocabulary in the app onto four badge tones. */
function toneFor(status: string | null | undefined): string {
    switch (status) {
        case 'Active':
        case 'Generated':
        case 'Completed':
        case 'Applied':
        case 'Approved':
            return 'ok';
        case 'PendingSignature':
        case 'Pending':
        case 'Scheduled':
        case 'PendingApproval':
        case 'Open':
            return 'info';
        case 'Failed':
        case 'Terminated':
        case 'Rejected':
            return 'err';
        case 'Expired':
        case 'Superseded':
        case 'Skipped':
            return 'warn';
        default:
            return '';
    }
}

// =====================================================================================
// TAB 1 — the roster + the contract workspace
// =====================================================================================

@RegisterClass(BaseResourceComponent, 'ContractsSectionResource')
@Component({
    selector: 'mjc-contracts-section',
    standalone: true,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    styles: [SHARED_STYLES],
    template: `
        <div class="wrap">
            <!-- ===================== ROSTER ===================== -->
            <ng-container *ngIf="!SelectedContract">
                <div class="head">
                    <div>
                        <div class="eyebrow">Viewing</div>
                        <h1>Contracts</h1>
                        <p class="sub">
                            Every agreement this organization has committed to — what was promised, for how long, and what it
                            is billing. Select a contract to open its workspace; double-click any grid row to open the record.
                        </p>
                    </div>
                </div>

                <div class="kpis">
                    <div class="kpi">
                        <div class="label">Active contracted value</div>
                        <div class="value">{{ TotalCommitted | currency: 'USD' : 'symbol' : '1.0-0' }}</div>
                        <div class="foot">across {{ ActiveCount }} active contracts</div>
                    </div>
                    <div class="kpi">
                        <div class="label">Renewing next 90 days</div>
                        <div class="value">{{ RenewingCount }}</div>
                        <div class="foot">terms reaching their end date</div>
                    </div>
                    <div class="kpi">
                        <div class="label">Billing scheduled</div>
                        <div class="value warn">{{ ScheduledCount }}</div>
                        <div class="foot">events awaiting generation</div>
                    </div>
                    <div class="kpi">
                        <div class="label">Failed billing</div>
                        <div class="value err">{{ FailedCount }}</div>
                        <div class="foot">never auto-retried — needs a human</div>
                    </div>
                </div>

                <div class="card">
                    <div class="card-head">
                        All contracts
                        <span class="right">{{ Contracts.length }} total</span>
                    </div>
                    <mj-explorer-entity-data-grid
                        [Params]="ContractsParams"
                        [Height]="420"
                        [ShowToolbar]="true"
                        [ToolbarConfig]="RosterToolbar"
                        (AfterRowClick)="OpenContract($event)"
                        (AfterDataLoad)="OnRosterLoaded()"
                    ></mj-explorer-entity-data-grid>
                    <div class="note info">
                        <strong>New contract</strong> in the toolbar opens MJ's record form — save it and it appears here.
                        Single-click a row to open its workspace below; double-click to open the raw record.
                    </div>
                </div>
            </ng-container>

            <!-- ===================== WORKSPACE ===================== -->
            <ng-container *ngIf="SelectedContract as c">
                <div class="head">
                    <div>
                        <div class="eyebrow">Viewing contract</div>
                        <h1>
                            {{ c.ContractNumber }}
                            <span class="badge" [ngClass]="Tone(c.Status)">{{ c.Status }}</span>
                            <span class="badge" *ngIf="c.AutoRenew">Auto-renew</span>
                        </h1>
                        <p class="sub">{{ c.Description || 'No description recorded.' }}</p>
                    </div>
                    <div class="actions">
                        <button class="btn" (click)="CloseContract()">← All contracts</button>
                    </div>
                </div>

                <div class="card">
                    <div class="tabs">
                        <button *ngFor="let t of Tabs" [class.active]="t.key === ActiveTab" (click)="ActiveTab = t.key">
                            {{ t.label }}<span class="n" *ngIf="t.count !== null">{{ t.count }}</span>
                        </button>
                    </div>

                    <!-- OVERVIEW -->
                    <ng-container *ngIf="ActiveTab === 'overview'">
                        <div class="grid2">
                            <div class="fld"><span class="k">Status</span><span class="v">{{ c.Status }}</span></div>
                            <div class="fld"><span class="k">Effective</span><span class="v">{{ c.EffectiveDate ? (c.EffectiveDate | date: 'mediumDate') : '—' }}</span></div>
                            <div class="fld"><span class="k">Executed</span><span class="v">{{ c.ExecutedDate ? (c.ExecutedDate | date: 'mediumDate') : '—' }}</span></div>
                            <div class="fld"><span class="k">Priced as of</span><span class="v">{{ c.PricedAt ? (c.PricedAt | date: 'mediumDate') : '—' }}</span></div>
                            <div class="fld"><span class="k">Auto-renew</span><span class="v">{{ c.AutoRenew ? 'Yes' : 'No' }}</span></div>
                            <div class="fld"><span class="k">Cancellation window</span><span class="v">{{ c.CancellationWindowDays != null ? c.CancellationWindowDays + ' days' : '—' }}</span></div>
                            <div class="fld"><span class="k">External reference</span><span class="v">{{ c.ExternalReferenceID || '—' }}</span></div>
                            <div class="fld"><span class="k">Terms</span><span class="v">{{ SelectedTerms.length }}</span></div>
                            <div class="fld"><span class="k">Total committed</span><span class="v">{{ CommittedFor(c.ID) | currency: 'USD' : 'symbol' : '1.0-0' }}</span></div>
                        </div>
                        <div class="note info" *ngIf="c.PricedAt">
                            Prices on this agreement were resolved from the catalog as of
                            <strong>{{ c.PricedAt | date: 'mediumDate' }}</strong> and locked. Renewals escalate from the
                            contract's own prior price rather than re-reading the catalog.
                        </div>
                    </ng-container>

                    <!-- TERMS -->
                    <ng-container *ngIf="ActiveTab === 'terms'">
                        <div class="tl" *ngIf="SelectedTerms.length; else noTerms">
                            <div class="tl-row" *ngFor="let t of SelectedTerms">
                                <div class="tl-when">
                                    Term {{ t.TermNumber }}<br />
                                    <span class="muted">{{ t.StartDate | date: 'yyyy' }}</span>
                                </div>
                                <div>
                                    <div class="tl-bar">
                                        <div class="tl-fill" [ngClass]="TermFill(t)" [style.width.%]="100">
                                            {{ t.StartDate | date: 'mediumDate' }} – {{ t.EndDate | date: 'mediumDate' }} · {{ t.Status }}
                                        </div>
                                    </div>
                                    <div class="tl-meta">
                                        <span>Committed <strong>{{ t.CommittedAmount | currency: 'USD' : 'symbol' : '1.0-0' }}</strong></span>
                                        <span>{{ t.BillingFrequency }}</span>
                                        <span *ngIf="t.EscalationPercent != null">
                                            +{{ t.EscalationPercent * 100 | number: '1.0-2' }}%
                                            <span class="muted" *ngIf="t.MaxEscalationPercent != null">(cap {{ t.MaxEscalationPercent * 100 | number: '1.0-2' }}%)</span>
                                            <span class="muted" *ngIf="t.EscalationBasis"> on {{ t.EscalationBasis }}</span>
                                        </span>
                                        <span *ngIf="t.RenewalNoticeDays != null">{{ t.RenewalNoticeDays }}d notice</span>
                                        <span *ngIf="t.RenewalProbability != null">renewal {{ t.RenewalProbability * 100 | number: '1.0-0' }}%</span>
                                        <span *ngIf="t.ExecutedDate">executed {{ t.ExecutedDate | date: 'mediumDate' }}</span>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <ng-template #noTerms><div class="empty">No terms on this contract yet.</div></ng-template>
                        <div class="searchrow" style="border-top:1px solid var(--mj-border-subtle,#f1f5f9);border-bottom:none;">
                            <span class="muted" style="font-size:12.5px;">Select a term to scope Coverage and Billing:</span>
                            <select class="f" [(ngModel)]="SelectedTermID" (ngModelChange)="OnTermChange()">
                                <option [ngValue]="null">— all terms —</option>
                                <option *ngFor="let t of SelectedTerms" [ngValue]="t.ID">Term {{ t.TermNumber }} ({{ t.Status }})</option>
                            </select>
                        </div>
                    </ng-container>

                    <!-- GRID-BACKED TABS -->
                    <ng-container *ngIf="ActiveTab === 'coverage'">
                        <mj-explorer-entity-data-grid [Params]="LinesParams" [Height]="420"></mj-explorer-entity-data-grid>
                    </ng-container>
                    <ng-container *ngIf="ActiveTab === 'billing'">
                        <mj-explorer-entity-data-grid [Params]="SchedulesParams" [Height]="180"></mj-explorer-entity-data-grid>
                        <div class="card-head" style="border-top:1px solid var(--mj-border-subtle,#f1f5f9);">Billing events</div>
                        <mj-explorer-entity-data-grid [Params]="EventsParams" [Height]="300"></mj-explorer-entity-data-grid>
                    </ng-container>
                    <ng-container *ngIf="ActiveTab === 'commitments'">
                        <mj-explorer-entity-data-grid [Params]="CommitmentsParams" [Height]="380"></mj-explorer-entity-data-grid>
                    </ng-container>
                    <ng-container *ngIf="ActiveTab === 'amendments'">
                        <mj-explorer-entity-data-grid [Params]="AmendmentsParams" [Height]="380"></mj-explorer-entity-data-grid>
                    </ng-container>
                    <ng-container *ngIf="ActiveTab === 'documents'">
                        <div class="empty">
                            Documents attach through MJ's polymorphic <span class="mono">__mj.FileEntityRecordLink</span>
                            (EntityID + RecordID) — not a column on this schema.
                            <br /><br />
                            The record-scoped file panel does not exist in MJ yet: <span class="mono">ng-file-storage</span>
                            ships category-scoped browsers only. <strong>&lt;mj-record-files&gt;</strong> is one of the two
                            components this app is building to donate back.
                        </div>
                    </ng-container>
                    <ng-container *ngIf="ActiveTab === 'history'">
                        <mj-explorer-entity-data-grid [Params]="EventLogParams" [Height]="380"></mj-explorer-entity-data-grid>
                        <div class="note info">
                            This is the immutable <strong>system</strong> record. Customer-visible events also write a
                            <span class="mono">common.Activity</span> row so the agreement appears on the account timeline —
                            two different things, neither replacing the other.
                        </div>
                    </ng-container>
                </div>
            </ng-container>
        </div>
    `,
})
export class MJCContractsSectionComponent extends BaseResourceComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    public Contracts: ContractRow[] = [];
    public Terms: TermRow[] = [];
    public Events: EventRow[] = [];
    public SelectedContract: ContractRow | null = null;
    public SelectedTermID: string | null = null;
    public ActiveTab = 'overview';
    /**
     * The toolbar MJ already ships — search, add, refresh, export. Turning these on is why this
     * component has no search box and no "new" button of its own: creating a contract opens MJ's
     * record form, and a saved record shows up in this same grid.
     */
    public readonly RosterToolbar = {
        showSearch: true,
        searchPlaceholder: 'Search contracts…',
        showAdd: true,
        showRefresh: true,
        showExport: true,
    };

    public ContractsParams: RunViewParams = { EntityName: ENTITY_CONTRACTS, OrderBy: 'ContractNumber' };
    public LinesParams: RunViewParams = { EntityName: ENTITY_LINES };
    public SchedulesParams: RunViewParams = { EntityName: ENTITY_SCHEDULES };
    public EventsParams: RunViewParams = { EntityName: ENTITY_EVENTS };
    public CommitmentsParams: RunViewParams = { EntityName: ENTITY_COMMITMENTS };
    public AmendmentsParams: RunViewParams = { EntityName: ENTITY_AMENDMENTS };
    public EventLogParams: RunViewParams = { EntityName: ENTITY_EVENTLOG };

    private termsByContract = new Map<string, TermRow[]>();

    public async ngOnInit(): Promise<void> {
        await this.load();
    }

    public override async GetResourceDisplayName(_data: ResourceData): Promise<string> {
        return 'Contracts';
    }
    public override async GetResourceIconClass(_data: ResourceData): Promise<string> {
        return 'fa-solid fa-file-signature';
    }

    public get Tabs(): { key: string; label: string; count: number | null }[] {
        return [
            { key: 'overview', label: 'Overview', count: null },
            { key: 'terms', label: 'Terms', count: this.SelectedTerms.length },
            { key: 'coverage', label: 'Coverage', count: null },
            { key: 'billing', label: 'Billing', count: null },
            { key: 'commitments', label: 'Commitments', count: null },
            { key: 'amendments', label: 'Amendments', count: null },
            { key: 'documents', label: 'Documents', count: null },
            { key: 'history', label: 'History', count: null },
        ];
    }

    public get ActiveCount(): number {
        return this.Contracts.filter((c) => c.Status === 'Active').length;
    }
    public get TotalCommitted(): number {
        return this.Terms.filter((t) => t.Status === 'Active').reduce((s, t) => s + (t.CommittedAmount ?? 0), 0);
    }
    public get ScheduledCount(): number {
        return this.Events.filter((e) => e.Status === 'Scheduled').length;
    }
    public get FailedCount(): number {
        return this.Events.filter((e) => e.Status === 'Failed').length;
    }
    public get RenewingCount(): number {
        const now = Date.now();
        const horizon = now + 90 * 24 * 60 * 60 * 1000;
        return this.Terms.filter((t) => {
            if (!t.EndDate) return false;
            const end = new Date(t.EndDate).getTime();
            return end >= now && end <= horizon;
        }).length;
    }

    public get SelectedTerms(): TermRow[] {
        return this.SelectedContract ? (this.termsByContract.get(this.SelectedContract.ID) ?? []) : [];
    }

    public CommittedFor(contractID: string): number {
        return (this.termsByContract.get(contractID) ?? []).reduce((s, t) => s + (t.CommittedAmount ?? 0), 0);
    }

    public Tone(status: string | null): string {
        return toneFor(status);
    }

    public TermFill(t: TermRow): string {
        if (t.Status === 'Active') return 'active';
        if (t.Status === 'Completed' || t.Status === 'Terminated') return 'done';
        return 'future';
    }

    public OpenContract(args: AfterRowClickEventArgs): void {
        const row = args?.row as Record<string, unknown> | undefined;
        const id = row?.['ID'];
        if (typeof id !== 'string') return;
        this.SelectedContract = this.Contracts.find((c) => c.ID === id) ?? null;
        this.ActiveTab = 'overview';
        this.SelectedTermID = null;
        this.scopeChildGrids();
        this.cdr.detectChanges();
    }

    /** The grid reloaded — a contract may have just been created, so refresh the strip + lookups. */
    public async OnRosterLoaded(): Promise<void> {
        await this.load();
    }

    public CloseContract(): void {
        this.SelectedContract = null;
        this.SelectedTermID = null;
        this.cdr.detectChanges();
    }

    public OnTermChange(): void {
        this.scopeChildGrids();
        this.cdr.detectChanges();
    }

    /**
     * Aims every child grid at the current selection. Params objects are REASSIGNED rather than
     * mutated — an in-place edit would not trip Angular's input change detection, so the grid would
     * keep showing the previous contract's rows.
     */
    private scopeChildGrids(): void {
        const c = this.SelectedContract;
        if (!c) return;
        const termIDs = (this.termsByContract.get(c.ID) ?? []).map((t) => `'${t.ID}'`);
        const termScope = this.SelectedTermID
            ? `ContractTermID='${this.SelectedTermID}'`
            : termIDs.length
              ? `ContractTermID IN (${termIDs.join(',')})`
              : `1=0`;

        this.LinesParams = { EntityName: ENTITY_LINES, ExtraFilter: termScope, OrderBy: 'DisplayOrder' };
        this.SchedulesParams = { EntityName: ENTITY_SCHEDULES, ExtraFilter: termScope };
        this.EventsParams = { EntityName: ENTITY_EVENTS, ExtraFilter: termScope, OrderBy: 'ScheduledDate' };
        this.CommitmentsParams = { EntityName: ENTITY_COMMITMENTS, ExtraFilter: termScope };
        this.AmendmentsParams = { EntityName: ENTITY_AMENDMENTS, ExtraFilter: termScope, OrderBy: 'AmendmentNumber' };
        this.EventLogParams = { EntityName: ENTITY_EVENTLOG, ExtraFilter: `ContractID='${c.ID}'`, OrderBy: 'EventDate DESC' };
    }

    /** One `RunViews` batch — three round trips for data always needed together would be three too many. */
    private async load(): Promise<void> {
        const rv = new RunView();
        const [contracts, terms, events] = await rv.RunViews([
            {
                EntityName: ENTITY_CONTRACTS,
                Fields: ['ID', 'ContractNumber', 'Status', 'Description', 'EffectiveDate', 'ExecutedDate', 'PricedAt', 'AutoRenew', 'CancellationWindowDays', 'ExternalReferenceID'],
                OrderBy: 'ContractNumber',
                ResultType: 'simple',
            },
            {
                EntityName: ENTITY_TERMS,
                Fields: ['ID', 'ContractID', 'TermNumber', 'Status', 'StartDate', 'EndDate', 'CommittedAmount', 'EscalationPercent', 'MaxEscalationPercent', 'RenewalNoticeDays', 'EscalationBasis', 'BillingFrequency', 'RenewalProbability', 'ExecutedDate'],
                OrderBy: 'TermNumber',
                ResultType: 'simple',
            },
            {
                EntityName: ENTITY_EVENTS,
                Fields: ['ID', 'ContractTermID', 'ScheduledDate', 'Status', 'ComputedAmount', 'FailureReason'],
                OrderBy: 'ScheduledDate',
                ResultType: 'simple',
            },
        ]);

        // RunView reports failure via Success — it does not throw — so each result is checked.
        this.Contracts = contracts?.Success ? (contracts.Results as ContractRow[]) : [];
        this.Terms = terms?.Success ? (terms.Results as TermRow[]) : [];
        this.Events = events?.Success ? (events.Results as EventRow[]) : [];

        this.termsByContract = new Map();
        for (const t of this.Terms) {
            const list = this.termsByContract.get(t.ContractID) ?? [];
            list.push(t);
            this.termsByContract.set(t.ContractID, list);
        }
        this.cdr.detectChanges();
    }
}

// =====================================================================================
// TAB 2 — the billing worklist
// =====================================================================================

@RegisterClass(BaseResourceComponent, 'ContractsBillingResource')
@Component({
    selector: 'mjc-contracts-billing',
    standalone: true,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    styles: [SHARED_STYLES],
    template: `
        <div class="wrap">
            <div class="head">
                <div>
                    <div class="eyebrow">Automation</div>
                    <h1>Billing worklist</h1>
                    <p class="sub">
                        What the scheduled job is about to do, and what it could not do. A failed event is never retried
                        automatically — retrying into a duplicate bill is worse than a late one — so anything red here stays
                        red until a person clears it.
                    </p>
                </div>
            </div>

            <div class="kpis">
                <div class="kpi"><div class="label">Scheduled</div><div class="value">{{ Counts.Scheduled }}</div><div class="foot">awaiting generation</div></div>
                <div class="kpi"><div class="label">Generated</div><div class="value">{{ Counts.Generated }}</div><div class="foot">orders produced</div></div>
                <div class="kpi"><div class="label">Failed</div><div class="value err">{{ Counts.Failed }}</div><div class="foot">needs a human</div></div>
                <div class="kpi"><div class="label">Skipped</div><div class="value warn">{{ Counts.Skipped }}</div><div class="foot">deliberately not billed</div></div>
            </div>

            <div class="card" *ngIf="Failed.length">
                <div class="card-head">Failed<span class="right">{{ Failed.length }}</span></div>
                <div class="note err" *ngFor="let e of Failed">
                    <div>
                        <strong>{{ e.ScheduledDate | date: 'mediumDate' }}</strong> — {{ e.FailureReason }}
                    </div>
                </div>
            </div>

            <div class="card">
                <div class="card-head">All billing events</div>
                <div class="searchrow">
                    <select class="f" [(ngModel)]="StatusFilter" (ngModelChange)="ApplyFilter()">
                        <option value="">All statuses</option>
                        <option value="Scheduled">Scheduled</option>
                        <option value="Generated">Generated</option>
                        <option value="Failed">Failed</option>
                        <option value="Skipped">Skipped</option>
                    </select>
                </div>
                <mj-explorer-entity-data-grid [Params]="EventsParams" [Height]="420"></mj-explorer-entity-data-grid>
            </div>
        </div>
    `,
})
export class MJCContractsBillingComponent extends BaseResourceComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    public Counts = { Scheduled: 0, Generated: 0, Failed: 0, Skipped: 0 };
    public Failed: EventRow[] = [];
    public StatusFilter = '';
    public EventsParams: RunViewParams = { EntityName: ENTITY_EVENTS, OrderBy: 'ScheduledDate' };

    public async ngOnInit(): Promise<void> {
        const rv = new RunView();
        const res = await rv.RunView<EventRow>({
            EntityName: ENTITY_EVENTS,
            Fields: ['ID', 'ContractTermID', 'ScheduledDate', 'Status', 'ComputedAmount', 'FailureReason'],
            OrderBy: 'ScheduledDate',
            ResultType: 'simple',
        });
        const rows = res?.Success ? res.Results : [];
        this.Counts = {
            Scheduled: rows.filter((r) => r.Status === 'Scheduled').length,
            Generated: rows.filter((r) => r.Status === 'Generated').length,
            Failed: rows.filter((r) => r.Status === 'Failed').length,
            Skipped: rows.filter((r) => r.Status === 'Skipped').length,
        };
        this.Failed = rows.filter((r) => r.Status === 'Failed');
        this.cdr.detectChanges();
    }

    public override async GetResourceDisplayName(_data: ResourceData): Promise<string> {
        return 'Billing worklist';
    }
    public override async GetResourceIconClass(_data: ResourceData): Promise<string> {
        return 'fa-solid fa-conveyor-belt';
    }

    public ApplyFilter(): void {
        this.EventsParams = {
            EntityName: ENTITY_EVENTS,
            ExtraFilter: this.StatusFilter ? `Status='${this.StatusFilter}'` : undefined,
            OrderBy: 'ScheduledDate',
        };
        this.cdr.detectChanges();
    }
}
