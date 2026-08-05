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
import {
    MJLeftNavComponent, MJLeftNavContentComponent, MJPageLayoutComponent, MJPageHeaderComponent,
    MJPageBodyComponent, MJButtonDirective,
    type MJLeftNavSection, type MJLeftNavItem,
} from '@memberjunction/ng-ui-components';
import { NavigationService } from '@memberjunction/ng-shared';
import type { FormNavigationEvent } from '@memberjunction/ng-base-forms';
// Accounting's session-tab framework. It is marked TRANSFER-BACKLOG (destined for MJ base) and
// Marcelo explicitly authorised reuse now rather than waiting for the move — so contracts consumes
// it from @mj-biz-apps/accounting-ng, which is already a declared app dependency.
import { WorkspaceTabStripComponent, WorkspaceTabStore } from '@mj-biz-apps/accounting-ng';
import { RunView, CompositeKey, type RunViewParams } from '@memberjunction/core';
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
    .shell { display:flex; height:100%; min-height:0; }
    .pane { flex:1; min-width:0; overflow:auto; }
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
    imports: [
        CommonModule, FormsModule, BaseFormsModule, MJButtonDirective,
        MJPageLayoutComponent, MJPageHeaderComponent, MJPageBodyComponent,
        MJLeftNavComponent, MJLeftNavContentComponent, WorkspaceTabStripComponent,
    ],
    styles: [SHARED_STYLES],
    template: `
      <mj-page-layout>
        <mj-page-header Title="Contracts" Icon="fa-solid fa-file-signature"
                        Subtitle="Agreements, the terms that run them, and the billing they produce">
            <div actions>
                <button mjButton="primary" (click)="NewContract()">
                    <i class="fa-solid fa-plus"></i> New contract
                </button>
                <button mjButton (click)="Refresh()">
                    <i class="fa-solid fa-rotate"></i> Refresh
                </button>
            </div>
        </mj-page-header>

        <mj-page-body [Flex]="true" [Padding]="false" Direction="row">
        <mj-left-nav
            [Sections]="NavSections"
            [ActiveId]="ActiveNav"
            MobileTitle="Contracts"
            (ItemClicked)="OnNav($event)"
        ></mj-left-nav>

        <mj-left-nav-content>
        <div class="wrap" *ngIf="ActiveNav === 'contracts'">
            <!-- ===================== ROSTER ===================== -->
            <ng-container>
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
                        (AfterDataLoad)="OnRosterLoaded()"
                        (AfterRowClick)="OpenRow($event)"
                        (Navigate)="OnNavigate($event)"
                    ></mj-explorer-entity-data-grid>
                    <div class="note info" *ngIf="!Workspace.Count">
                        <strong>New contract</strong> in the toolbar opens the contract form. <strong>Double-click</strong> any
                        row to open that contract as its own MJ record tab — the standard Explorer way to view a record,
                        so several contracts stay open side by side and the browser's history works.
                    </div>
                </div>
            </ng-container>

            <!-- ===================== WORKSPACE (session tabs) ===================== -->
            <div class="card" *ngIf="Workspace.Count">
                <mj-workspace-tab-strip
                    [Tabs]="Workspace.Tabs"
                    [ActiveId]="Workspace.ActiveId"
                    [ShowNewTab]="false"
                    (TabSelected)="Workspace.Activate($event)"
                    (TabClosed)="Workspace.Close($event)"
                ></mj-workspace-tab-strip>

                <ng-container *ngIf="OpenContract as c">
                    <div class="ident">
                        <span class="name">{{ c.ContractNumber }}</span>
                        <span class="badge" [ngClass]="Tone(c.Status)">{{ c.Status }}</span>
                        <span class="badge" *ngIf="c.AutoRenew">Auto-renew</span>
                        <span class="right" style="margin-left:auto;">
                            <button mjButton (click)="OpenAsRecordTab(c)">
                                <i class="fa-solid fa-up-right-from-square"></i> Open as record
                            </button>
                        </span>
                    </div>

                    <div class="grid2">
                        <div class="fld"><span class="k">Effective</span><span class="v">{{ c.EffectiveDate ? (c.EffectiveDate | date: 'mediumDate') : '—' }}</span></div>
                        <div class="fld"><span class="k">Executed</span><span class="v">{{ c.ExecutedDate ? (c.ExecutedDate | date: 'mediumDate') : '—' }}</span></div>
                        <div class="fld"><span class="k">Priced as of</span><span class="v">{{ c.PricedAt ? (c.PricedAt | date: 'mediumDate') : '—' }}</span></div>
                        <div class="fld"><span class="k">Auto-renew</span><span class="v">{{ c.AutoRenew ? 'Yes' : 'No' }}</span></div>
                        <div class="fld"><span class="k">Cancellation window</span><span class="v">{{ c.CancellationWindowDays != null ? c.CancellationWindowDays + ' days' : '—' }}</span></div>
                        <div class="fld"><span class="k">External reference</span><span class="v">{{ c.ExternalReferenceID || '—' }}</span></div>
                    </div>

                    <div class="card-head">Terms</div>
                    <mj-explorer-entity-data-grid [Params]="WsTermsParams" [Height]="200"></mj-explorer-entity-data-grid>

                    <div class="card-head">Coverage</div>
                    <mj-explorer-entity-data-grid [Params]="WsLinesParams" [Height]="200"></mj-explorer-entity-data-grid>

                    <div class="card-head">Billing events</div>
                    <mj-explorer-entity-data-grid [Params]="WsEventsParams" [Height]="200"></mj-explorer-entity-data-grid>
                </ng-container>
            </div>
        </div>

        <!-- ===================== BILLING WORKLIST ===================== -->
        <div class="wrap" *ngIf="ActiveNav === 'billing'">
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
                <div class="kpi"><div class="label">Scheduled</div><div class="value">{{ EventCounts.Scheduled }}</div><div class="foot">awaiting generation</div></div>
                <div class="kpi"><div class="label">Generated</div><div class="value">{{ EventCounts.Generated }}</div><div class="foot">orders produced</div></div>
                <div class="kpi"><div class="label">Failed</div><div class="value err">{{ EventCounts.Failed }}</div><div class="foot">needs a human</div></div>
                <div class="kpi"><div class="label">Skipped</div><div class="value warn">{{ EventCounts.Skipped }}</div><div class="foot">deliberately not billed</div></div>
            </div>
            <div class="card" *ngIf="FailedEvents.length">
                <div class="card-head">Failed<span class="right">{{ FailedEvents.length }}</span></div>
                <div class="note err" *ngFor="let e of FailedEvents">
                    <div><strong>{{ e.ScheduledDate | date: 'mediumDate' }}</strong> — {{ e.FailureReason }}</div>
                </div>
            </div>
            <div class="card">
                <div class="card-head">All billing events</div>
                <mj-explorer-entity-data-grid
                    [Params]="AllEventsParams" [Height]="420"
                    [ShowToolbar]="true" [ToolbarConfig]="RosterToolbar"
                ></mj-explorer-entity-data-grid>
            </div>
        </div>

        <!-- ===================== AMENDMENTS ===================== -->
        <div class="wrap" *ngIf="ActiveNav === 'amendments'">
            <div class="head">
                <div>
                    <div class="eyebrow">Change control</div>
                    <h1>Amendments</h1>
                    <p class="sub">
                        Amendments change a <strong>live</strong> term. Renewals start a new one — conflating the two is the
                        most common contract-model mistake, so they are deliberately different screens.
                    </p>
                </div>
            </div>
            <div class="card">
                <mj-explorer-entity-data-grid
                    [Params]="AllAmendmentsParams" [Height]="460"
                    [ShowToolbar]="true" [ToolbarConfig]="RosterToolbar"
                ></mj-explorer-entity-data-grid>
            </div>
        </div>

        <!-- ===================== SETUP: CONTRACT TYPES ===================== -->
        <div class="wrap" *ngIf="ActiveNav === 'types'">
            <div class="head">
                <div>
                    <div class="eyebrow">Setup</div>
                    <h1>Contract types</h1>
                    <p class="sub">
                        Configuration-as-data: the columns <em>are</em> the rules. A type carries the default term, cadence,
                        escalation and its cap, notice and cancellation windows — and the engine reads them rather than
                        branching on a type name.
                    </p>
                </div>
            </div>
            <div class="card">
                <mj-explorer-entity-data-grid
                    [Params]="TypesParams" [Height]="460"
                    [ShowToolbar]="true" [ToolbarConfig]="RosterToolbar"
                ></mj-explorer-entity-data-grid>
            </div>
        </div>
        </mj-left-nav-content>
        </mj-page-body>
      </mj-page-layout>
    `,
})
export class MJCContractsSectionComponent extends BaseResourceComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);
    /** MJ's own navigator — this is what actually opens a record tab. */
    private readonly nav = inject(NavigationService);

    public Contracts: ContractRow[] = [];
    public Terms: TermRow[] = [];
    public Events: EventRow[] = [];
    public ActiveNav: string = 'contracts';
    public EventCounts = { Scheduled: 0, Generated: 0, Failed: 0, Skipped: 0 };

    /** Session tabs for the viewing space — accounting's store, state typed to our roster row. */
    public readonly Workspace = new WorkspaceTabStore<ContractRow>();
    public WsTermsParams: RunViewParams = { EntityName: ENTITY_TERMS };
    public WsLinesParams: RunViewParams = { EntityName: ENTITY_LINES };
    public WsEventsParams: RunViewParams = { EntityName: ENTITY_EVENTS };

    public AllEventsParams: RunViewParams = { EntityName: ENTITY_EVENTS, OrderBy: 'ScheduledDate' };
    public AllAmendmentsParams: RunViewParams = { EntityName: ENTITY_AMENDMENTS, OrderBy: 'AmendmentNumber' };
    public TypesParams: RunViewParams = { EntityName: 'MJ_BizApps_Contracts: Contract Types', OrderBy: 'Name' };
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

    /**
     * The rail. MJ's own `<mj-left-nav>` — top nav crosses SECTIONS, left nav moves within one, and
     * everything here is one section: the agreements and the machinery that bills them. Setup is its
     * own group because configuration is a different job from operating the book.
     */
    public get NavSections(): MJLeftNavSection[] {
        return [
            {
                items: [
                    { id: 'contracts', icon: 'fa-solid fa-file-signature', label: 'Contracts', description: 'The agreement roster', badge: this.Contracts.length || undefined },
                    { id: 'billing', icon: 'fa-solid fa-conveyor-belt', label: 'Billing worklist', description: 'Due, generated and failed', badge: this.EventCounts.Failed || undefined },
                    { id: 'amendments', icon: 'fa-solid fa-file-pen', label: 'Amendments', description: 'Mid-term changes' },
                ],
            },
            {
                label: 'Setup',
                items: [{ id: 'types', icon: 'fa-solid fa-sliders', label: 'Contract types', description: 'Defaults and rules' }],
            },
        ];
    }

    /**
     * THE VIEWING SPACE. The grid only EMITS a navigation intent — it does not navigate — so the host
     * has to act on it, which is the step that was missing: rows were 'opening' into nothing.
     * Handing it to NavigationService opens the record as a real MJ record tab, which is Explorer's
     * standard viewing space: several contracts stay open at once and browser history works.
     */
    public OnNavigate(event: FormNavigationEvent): void {
        if (event.Kind === 'record' && event.PrimaryKey) {
            this.nav.OpenEntityRecord(event.EntityName, event.PrimaryKey);
        } else if (event.Kind === 'new-record') {
            this.nav.OpenNewEntityRecord(event.EntityName);
        }
    }

    /**
     * Clicking a row opens it in the WORKSPACE — the viewing space — rather than throwing the user
     * out to a record tab. Session tabs (accounting's framework) mean several contracts stay open
     * side by side and switching between them keeps their state, which is how contracts are actually
     * read: a renewal beside its predecessor. 'Open as record' is still one click away for the full
     * MJ form.
     */
    public OpenRow(args: AfterRowClickEventArgs): void {
        const row = args?.row as Record<string, unknown> | undefined;
        const id = row?.['ID'];
        if (typeof id !== 'string') return;
        const contract = this.Contracts.find((c) => c.ID === id);
        if (!contract) return;

        const existing = this.Workspace.Tabs.find((t) => t.Id === id);
        if (existing) {
            this.Workspace.Activate(id);
        } else {
            this.Workspace.Open({
                Id: id,
                Label: contract.ContractNumber,
                Icon: 'fa-solid fa-file-signature',
                Status: 'complete',
                State: contract,
            });
        }
        this.scopeWorkspaceGrids(id);
        this.cdr.detectChanges();
    }

    public OpenAsRecordTab(c: ContractRow): void {
        this.nav.OpenEntityRecord(ENTITY_CONTRACTS, CompositeKey.FromID(c.ID));
    }

    /** The contract shown in the active workspace tab. */
    public get OpenContract(): ContractRow | null {
        const id = this.Workspace.ActiveId;
        return id ? (this.Contracts.find((c) => c.ID === id) ?? null) : null;
    }

    private scopeWorkspaceGrids(contractID: string): void {
        const termIDs = (this.termsByContract.get(contractID) ?? []).map((t) => `'${t.ID}'`);
        const termScope = termIDs.length ? `ContractTermID IN (${termIDs.join(',')})` : '1=0';
        this.WsTermsParams = { EntityName: ENTITY_TERMS, ExtraFilter: `ContractID='${contractID}'`, OrderBy: 'TermNumber' };
        this.WsLinesParams = { EntityName: ENTITY_LINES, ExtraFilter: termScope, OrderBy: 'DisplayOrder' };
        this.WsEventsParams = { EntityName: ENTITY_EVENTS, ExtraFilter: termScope, OrderBy: 'ScheduledDate' };
    }

    /** Header action — same destination the grid's own New button reaches. */
    public NewContract(): void {
        this.nav.OpenNewEntityRecord(ENTITY_CONTRACTS);
    }

    public async Refresh(): Promise<void> {
        this.ContractsParams = { ...this.ContractsParams };
        await this.load();
    }

    public OnNav(item: MJLeftNavItem): void {
        this.ActiveNav = item.id;
        this.cdr.detectChanges();
    }

    public get FailedEvents(): EventRow[] {
        return this.Events.filter((e) => e.Status === 'Failed');
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



    public Tone(status: string | null): string {
        return toneFor(status);
    }



    /** The grid reloaded — a contract may have just been created, so refresh the strip + lookups. */
    public async OnRosterLoaded(): Promise<void> {
        await this.load();
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

        this.EventCounts = {
            Scheduled: this.Events.filter((e) => e.Status === 'Scheduled').length,
            Generated: this.Events.filter((e) => e.Status === 'Generated').length,
            Failed: this.Events.filter((e) => e.Status === 'Failed').length,
            Skipped: this.Events.filter((e) => e.Status === 'Skipped').length,
        };

        this.termsByContract = new Map();
        for (const t of this.Terms) {
            const list = this.termsByContract.get(t.ContractID) ?? [];
            list.push(t);
            this.termsByContract.set(t.ContractID, list);
        }
        this.cdr.detectChanges();
    }
}
