/**
 * @fileoverview The Contracts Explorer section — the four mockup pages, live.
 *
 * STRUCTURE MIRRORS bizapps-orders: `mj-page-layout` > `mj-page-header` (title, icon, subtitle and an
 * `[actions]` slot) > `mj-page-body Direction="row"` > `mj-left-nav` + `mj-left-nav-content`. Top nav
 * crosses SECTIONS; the rail moves within one, and everything here is one section — the agreements
 * and the machinery that bills them.
 *
 * THE FOUR PAGES, ported from `design-docs/ui-design/mockups/`:
 *   contracts  — the roster: health strip + grid          (contracts-list.html)
 *   workspace  — one agreement, section-tabbed, EDITABLE  (contract-workspace.html)
 *   create     — Fast / Detailed entry                    (contract-create.html)
 *   billing    — what the scheduled job will + will not do(billing-worklist.html)
 *
 * WHAT IS MJ'S AND WHAT IS OURS. Every tabular section is `<mj-explorer-entity-data-grid>`, so we
 * inherit sorting, paging, its toolbar (search / add / refresh / export) and column formatting.
 * Chrome is MJ's page primitives; buttons are `mjButton`. Hand-built is only what MJ offers nothing
 * for: the health strip, the identity band, the term timeline and the entry forms. Colour, spacing
 * and radius come from `--mj-*` tokens throughout, so this tracks the host theme.
 *
 * DATA ACCESS is the four sanctioned methods only (master plan §11.1): `RunView`/`RunViews` to read,
 * `Metadata.GetEntityObject` + `BaseEntity.Save()` to write. No bespoke fetch anywhere.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClass } from '@memberjunction/global';
import { BaseResourceComponent, NavigationService } from '@memberjunction/ng-shared';
import { BaseFormsModule } from '@memberjunction/ng-base-forms';
import type { FormNavigationEvent } from '@memberjunction/ng-base-forms';
import {
    MJLeftNavComponent, MJLeftNavContentComponent, MJPageLayoutComponent, MJPageHeaderComponent,
    MJPageBodyComponent, MJButtonDirective,
    type MJLeftNavSection, type MJLeftNavItem,
} from '@memberjunction/ng-ui-components';
import { RunView, Metadata, CompositeKey, type RunViewParams } from '@memberjunction/core';
import type { ResourceData } from '@memberjunction/core-entities';
import type { AfterRowClickEventArgs } from '@memberjunction/ng-entity-viewer';
import type { mjBizAppsContractsContractEntity, mjBizAppsContractsContractTermEntity } from '@mj-biz-apps/contracts-entities';
// Accounting's session-tab framework — marked TRANSFER-BACKLOG (destined for MJ base); Marcelo
// authorised using it now rather than waiting for the move.
import { WorkspaceTabStripComponent, WorkspaceTabStore } from '@mj-biz-apps/accounting-ng';

const E_CONTRACTS = 'MJ_BizApps_Contracts: Contracts';
const E_TYPES = 'MJ_BizApps_Contracts: Contract Types';
const E_TERMS = 'MJ_BizApps_Contracts: Contract Terms';
const E_LINES = 'MJ_BizApps_Contracts: Contract Lines';
const E_SCHEDULES = 'MJ_BizApps_Contracts: Contract Billing Schedules';
const E_EVENTS = 'MJ_BizApps_Contracts: Contract Billing Events';
const E_COMMITMENTS = 'MJ_BizApps_Contracts: Contract Commitments';
const E_AMENDMENTS = 'MJ_BizApps_Contracts: Contract Amendments';
const E_EVENTLOG = 'MJ_BizApps_Contracts: Contract Events';
const E_COMPANIES = 'MJ: Companies';
const E_ORGS = 'MJ_BizApps_Common: Organizations';
const E_PEOPLE = 'MJ_BizApps_Common: People';
const E_USERS = 'MJ: Users';
const E_PAYTERMS = 'MJ_BizApps_Orders: Payment Terms Types';
const E_CURRENCIES = 'MJ_BizApps_Accounting: Currencies';

interface ContractRow {
    ID: string; ContractNumber: string; Status: string; Description: string | null;
    EffectiveDate: string | null; ExecutedDate: string | null; PricedAt: string | null;
    AutoRenew: boolean; CancellationWindowDays: number | null; ExternalReferenceID: string | null;
}
interface TermRow {
    ID: string; ContractID: string; TermNumber: number; Status: string;
    StartDate: string | null; EndDate: string | null; CommittedAmount: number | null;
    EscalationPercent: number | null; MaxEscalationPercent: number | null; RenewalNoticeDays: number | null;
    BillingFrequency: string | null; ExecutedDate: string | null;
}
interface EventRow {
    ID: string; ContractTermID: string; ScheduledDate: string | null; Status: string;
    ComputedAmount: number | null; FailureReason: string | null;
}
interface Lookup { ID: string; Name: string }

/** What the create page edits. Plain data — it becomes a BaseEntity only at save. */
interface Draft {
    // --- Contract. Every field below is a real column; nothing here is invented.
    ContractNumber: string; ContractTypeID: string; CompanyID: string; CustomerOrganizationID: string;
    CustomerPersonID: string; PrimaryContactPersonID: string; OwnerUserID: string; ParentContractID: string;
    Status: string; Description: string; EffectiveDate: string; ExecutedDate: string; PricedAt: string;
    AutoRenew: boolean; CancellationWindowDays: number | null; TerminationPolicy: string; ExternalReferenceID: string;
    // --- Optional first ContractTerm, created in the same action.
    CreateTerm: boolean;
    TermStart: string; TermEnd: string; CommittedAmount: number | null; BillingFrequency: string;
    AnchorMonth: number | null; AnchorDay: number | null; PaymentTermsTypeID: string; CurrencyID: string;
    EscalationPercent: number | null; EscalationBasis: string; MaxEscalationPercent: number | null;
    RenewalNoticeDays: number | null; RenewalProbability: number | null;
    EarlyTerminationDate: string; TermExecutedDate: string; TermNotes: string;
}

/** One open contract in the workspace: the row plus its own edit buffer, so tabs never share state. */
interface TabState { Row: ContractRow; Edit: Partial<Draft> }

@RegisterClass(BaseResourceComponent, 'ContractsSectionResource')
@Component({
    selector: 'mjc-contracts-section',
    standalone: true,
    imports: [
        CommonModule, FormsModule, BaseFormsModule, MJButtonDirective,
        MJPageLayoutComponent, MJPageHeaderComponent, MJPageBodyComponent,
        MJLeftNavComponent, MJLeftNavContentComponent, WorkspaceTabStripComponent,
    ],
    styles: [
        `
        .wrap { padding: var(--mj-space-5, 20px) var(--mj-space-6, 24px) var(--mj-space-10, 40px); }
        .sechead { margin-bottom: var(--mj-space-4, 16px); }
        .sechead h2 { margin: 0; font-size: 18px; font-weight: 700; letter-spacing: -.01em; color: var(--mj-text-primary, #1e293b); }
        .sechead p { margin: 4px 0 0; font-size: 13px; color: var(--mj-text-secondary, #475569); max-width: 82ch; line-height: 1.55; }

        .kpis { display: grid; grid-template-columns: repeat(4, 1fr); gap: var(--mj-space-3, 12px); margin-bottom: var(--mj-space-4, 16px); }
        .kpi { background: var(--mj-bg-surface, #fff); border: 1px solid var(--mj-border-default, #e2e8f0); border-radius: var(--mj-radius-lg, 10px); padding: 13px 15px; }
        .kpi .l { font-size: 11.5px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--mj-text-muted, #64748b); }
        .kpi .v { font-size: 24px; font-weight: 700; margin-top: 5px; letter-spacing: -.02em; color: var(--mj-text-primary, #1e293b); }
        .kpi .v.warn { color: var(--mj-status-warning-text, #b45309); }
        .kpi .v.err { color: var(--mj-status-error-text, #b91c1c); }
        .kpi .f { font-size: 12px; color: var(--mj-text-secondary, #475569); margin-top: 3px; }

        .card { background: var(--mj-bg-surface, #fff); border: 1px solid var(--mj-border-default, #e2e8f0); border-radius: var(--mj-radius-lg, 10px); overflow: hidden; margin-bottom: var(--mj-space-4, 16px); }
        .ch { display: flex; align-items: center; gap: 10px; padding: 12px 16px; border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9); font-weight: 700; font-size: 13.5px; color: var(--mj-text-primary, #1e293b); }
        .ch .r { margin-left: auto; font-weight: 400; font-size: 12.5px; color: var(--mj-text-secondary, #475569); }
        .cb { padding: var(--mj-space-4, 16px); }

        .badge { display: inline-flex; align-items: center; gap: 5px; height: 22px; padding: 0 9px; border-radius: 999px; font-size: 11.5px; font-weight: 700; white-space: nowrap; background: var(--mj-color-neutral-100, #f1f5f9); color: var(--mj-text-secondary, #475569); }
        .badge.ok { background: var(--mj-status-success-bg, #f0fdf4); color: var(--mj-status-success-text, #15803d); }
        .badge.warn { background: var(--mj-status-warning-bg, #fffbeb); color: var(--mj-status-warning-text, #b45309); }
        .badge.err { background: var(--mj-status-error-bg, #fef2f2); color: var(--mj-status-error-text, #b91c1c); }
        .badge.info { background: var(--mj-status-info-bg, #eff6ff); color: var(--mj-status-info-text, #1d4ed8); }

        .ident { display: flex; align-items: center; gap: 10px; padding: 13px 16px; border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9); flex-wrap: wrap; }
        .ident .n { font-size: 16px; font-weight: 700; letter-spacing: -.01em; color: var(--mj-text-primary, #1e293b); }
        .ident .sp { margin-left: auto; display: flex; gap: 8px; }

        .tabs { display: flex; gap: 2px; border-bottom: 1px solid var(--mj-border-default, #e2e8f0); padding: 0 16px; overflow-x: auto; }
        .tabs button { border: none; background: transparent; font-family: inherit; font-size: 13.5px; font-weight: 600; color: var(--mj-text-secondary, #475569); padding: 11px 13px; cursor: pointer; border-bottom: 2px solid transparent; white-space: nowrap; }
        .tabs button:hover { color: var(--mj-text-primary, #1e293b); }
        .tabs button.on { color: var(--mj-brand-primary, #0076b6); border-bottom-color: var(--mj-brand-primary, #0076b6); }
        .tabs button .n { font-size: 11px; font-weight: 700; background: var(--mj-color-neutral-100, #f1f5f9); border-radius: 9px; padding: 1px 6px; margin-left: 6px; }

        .fg { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px 18px; }
        .fld { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
        .fld > span { font-size: 12px; font-weight: 600; color: var(--mj-text-secondary, #475569); }
        .fld .hint { font-size: 11.5px; color: var(--mj-text-muted, #64748b); font-weight: 400; line-height: 1.45; }
        .fld .ro { height: 32px; line-height: 32px; font-size: 13.5px; font-weight: 600; color: var(--mj-text-primary, #1e293b); }
        .s2 { grid-column: span 2; }
        .s3 { grid-column: span 3; }
        .in, .sel, .ta {
            padding: 0 10px; height: 32px; width: 100%;
            border: 1px solid var(--mj-border-strong, #cbd5e1); border-radius: var(--mj-radius-md, 6px);
            background: var(--mj-bg-surface, #fff); color: var(--mj-text-primary, #1e293b);
            font-family: inherit; font-size: 13px;
        }
        .ta { height: auto; padding: 8px 10px; resize: vertical; }
        .in:focus, .sel:focus, .ta:focus { outline: none; border-color: var(--mj-brand-primary, #0076b6); box-shadow: 0 0 0 3px var(--mj-brand-primary-tint, #e6f1f9); }
        legend.lg { font-size: 11.5px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--mj-text-muted, #64748b); padding: 0 0 9px; }
        fieldset.pl { border: none; margin: 0 0 22px; padding: 0; min-width: 0; }

        .tl-row { display: grid; grid-template-columns: 104px 1fr; gap: 14px; padding: 11px 0; border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9); }
        .tl-row:last-child { border-bottom: none; }
        .tl-w { font-size: 12px; color: var(--mj-text-secondary, #475569); }
        .tl-bar { height: 26px; border-radius: var(--mj-radius-sm, 4px); background: var(--mj-color-neutral-100, #f1f5f9); overflow: hidden; display: flex; }
        .tl-fill { display: flex; align-items: center; padding: 0 9px; font-size: 12px; font-weight: 600; color: #fff; }
        .tl-fill.done { background: var(--mj-color-neutral-400, #94a3b8); }
        .tl-fill.now { background: var(--mj-brand-primary, #0076b6); }
        .tl-fill.next { background: var(--mj-color-neutral-300, #cbd5e1); color: var(--mj-text-secondary, #475569); }
        .tl-m { margin-top: 6px; font-size: 12px; color: var(--mj-text-secondary, #475569); display: flex; gap: 14px; flex-wrap: wrap; }

        .note { display: flex; gap: 10px; padding: 11px 13px; border-radius: var(--mj-radius-md, 6px); font-size: 12.5px; line-height: 1.5; margin: 12px 16px; }
        .note.info { background: var(--mj-status-info-bg, #eff6ff); color: var(--mj-status-info-text, #1d4ed8); }
        .note.err { background: var(--mj-status-error-bg, #fef2f2); color: var(--mj-status-error-text, #b91c1c); }
        .note.gap { background: var(--mj-color-neutral-100, #f1f5f9); color: var(--mj-text-secondary, #475569); }
        .note.ok { background: var(--mj-status-success-bg, #f0fdf4); color: var(--mj-status-success-text, #15803d); }

        .foot { display: flex; align-items: center; gap: 10px; padding: 12px 16px; border-top: 1px solid var(--mj-border-subtle, #f1f5f9); background: var(--mj-bg-surface-card, #f8fafc); }
        .foot .msg { font-size: 12.5px; color: var(--mj-text-secondary, #475569); max-width: 62ch; }
        .foot .sp { margin-left: auto; display: flex; gap: 8px; }
        .modes { display: inline-flex; border: 1px solid var(--mj-border-strong, #cbd5e1); border-radius: var(--mj-radius-md, 6px); overflow: hidden; }
        .modes button { border: none; background: var(--mj-bg-surface, #fff); font-family: inherit; font-size: 12.5px; font-weight: 600; color: var(--mj-text-secondary, #475569); padding: 6px 14px; cursor: pointer; }
        .modes button + button { border-left: 1px solid var(--mj-border-default, #e2e8f0); }
        .modes button.on { background: var(--mj-brand-primary, #0076b6); color: var(--mj-text-inverse, #fff); }
        .empty { padding: 26px 16px; text-align: center; color: var(--mj-text-muted, #64748b); font-size: 13px; }
        `,
    ],
    template: `
    <mj-page-layout>
        <mj-page-header Title="Contracts" Icon="fa-solid fa-file-signature"
                        Subtitle="Agreements, the terms that run them, and the billing they produce">
            <div actions>
                <button mjButton="primary" (click)="GoCreate()"><i class="fa-solid fa-plus"></i> New contract</button>
                <button mjButton (click)="Refresh()"><i class="fa-solid fa-rotate"></i> Refresh</button>
            </div>
        </mj-page-header>

        <mj-page-body [Flex]="true" [Padding]="false" Direction="row">
            <mj-left-nav [Sections]="NavSections" [ActiveId]="Page" MobileTitle="Contracts" (ItemClicked)="OnNav($event)"></mj-left-nav>

            <mj-left-nav-content>

            <!-- ============ 1. CONTRACTS ============ -->
            <div class="wrap" *ngIf="Page === 'contracts'">
                <div class="sechead">
                    <h2>All contracts</h2>
                    <p>Every agreement this organization has committed to — what was promised, for how long, and what it is
                       billing. Click a row to open it in the workspace.</p>
                </div>

                <div class="kpis">
                    <div class="kpi"><div class="l">Active contracted value</div><div class="v">{{ TotalCommitted | currency: 'USD' : 'symbol' : '1.0-0' }}</div><div class="f">across {{ ActiveCount }} active contracts</div></div>
                    <div class="kpi"><div class="l">Renewing next 90 days</div><div class="v">{{ RenewingCount }}</div><div class="f">terms reaching their end date</div></div>
                    <div class="kpi"><div class="l">Billing scheduled</div><div class="v warn">{{ Counts.Scheduled }}</div><div class="f">events awaiting generation</div></div>
                    <div class="kpi"><div class="l">Failed billing</div><div class="v err">{{ Counts.Failed }}</div><div class="f">never auto-retried</div></div>
                </div>

                <div class="card">
                    <div class="ch">Contracts <span class="r">{{ Contracts.length }} total</span></div>
                    <mj-explorer-entity-data-grid
                        [Params]="P.contracts" [Height]="420"
                        [ShowToolbar]="true" [ToolbarConfig]="Toolbar"
                        (AfterRowClick)="OpenWorkspace($event)"
                        (Navigate)="OnNavigate($event)"
                    ></mj-explorer-entity-data-grid>
                    <div class="note info">
                        <strong>New contract</strong> creates one; it appears here on save, and clicking it opens the
                        workspace. Double-click opens the full MJ record instead.
                    </div>
                </div>
            </div>

            <!-- ============ 2. WORKSPACE (editing) ============ -->
            <div class="wrap" *ngIf="Page === 'workspace'">
                <div class="sechead" *ngIf="!Current">
                    <h2>Contract workspace</h2>
                    <p>No contract open — pick one from the Contracts page.</p>
                </div>

                <div class="card" *ngIf="Open.Count" style="margin-bottom:0;border-bottom-left-radius:0;border-bottom-right-radius:0;">
                    <mj-workspace-tab-strip
                        [Tabs]="Open.Tabs" [ActiveId]="Open.ActiveId" [ShowNewTab]="false"
                        (TabSelected)="SwitchTab($event)" (TabClosed)="CloseTab($event)"
                    ></mj-workspace-tab-strip>
                </div>

                <ng-container *ngIf="Current as c">
                    <div class="card" [style.border-top-left-radius]="Open.Count ? '0' : null" [style.border-top-right-radius]="Open.Count ? '0' : null">
                        <div class="ident">
                            <span class="n">{{ c.ContractNumber }}</span>
                            <span class="badge" [ngClass]="Tone(c.Status)">{{ c.Status }}</span>
                            <span class="badge" *ngIf="c.AutoRenew">Auto-renew</span>
                            <span class="sp">
                                <button mjButton (click)="OpenRecord(c)"><i class="fa-solid fa-up-right-from-square"></i> Full record</button>
                                <button mjButton="primary" [disabled]="!Dirty || Saving" (click)="SaveEdits()">
                                    <i class="fa-solid fa-check"></i> {{ Saving ? 'Saving…' : 'Save changes' }}
                                </button>
                            </span>
                        </div>

                        <div class="tabs">
                            <button *ngFor="let t of Tabs" [class.on]="t.k === Tab" (click)="Tab = t.k">
                                {{ t.l }}<span class="n" *ngIf="t.n !== null">{{ t.n }}</span>
                            </button>
                        </div>

                        <div class="cb" *ngIf="Tab === 'overview'">
                            <fieldset class="pl">
                                <legend class="lg">The agreement</legend>
                                <div class="fg">
                                    <label class="fld"><span>Contract number</span><input class="in" [(ngModel)]="Edit.ContractNumber" (ngModelChange)="Touch()" /></label>
                                    <label class="fld"><span>Status</span>
                                        <select class="sel" [(ngModel)]="Edit.Status" (ngModelChange)="Touch()">
                                            <option *ngFor="let s of StatusOptions" [value]="s">{{ s }}</option>
                                        </select>
                                    </label>
                                    <label class="fld"><span>External reference</span><input class="in" [(ngModel)]="Edit.ExternalReferenceID" (ngModelChange)="Touch()" /></label>
                                    <label class="fld s3"><span>Description</span><textarea class="ta" rows="2" [(ngModel)]="Edit.Description" (ngModelChange)="Touch()"></textarea></label>
                                </div>
                            </fieldset>

                            <fieldset class="pl">
                                <legend class="lg">Dates &amp; pricing</legend>
                                <div class="fg">
                                    <label class="fld"><span>Priced as of</span><input class="in" type="date" [(ngModel)]="Edit.PricedAt" (ngModelChange)="Touch()" />
                                        <span class="hint">Prices resolve from the catalog as of this date and lock. Backdate for paper signed earlier.</span></label>
                                    <label class="fld"><span>Effective</span><input class="in" type="date" [(ngModel)]="Edit.EffectiveDate" (ngModelChange)="Touch()" /></label>
                                    <label class="fld"><span>Executed</span><input class="in" type="date" [(ngModel)]="Edit.ExecutedDate" (ngModelChange)="Touch()" />
                                        <span class="hint">May legitimately precede Effective — signing in December for a January term is ordinary.</span></label>
                                </div>
                            </fieldset>

                            <fieldset class="pl" style="margin-bottom:0;">
                                <legend class="lg">Renewal &amp; termination</legend>
                                <div class="fg">
                                    <label class="fld"><span>Auto-renew</span>
                                        <select class="sel" [(ngModel)]="Edit.AutoRenew" (ngModelChange)="Touch()">
                                            <option [ngValue]="true">Yes — renews without a deal</option>
                                            <option [ngValue]="false">No — renewal is a deal</option>
                                        </select>
                                    </label>
                                    <label class="fld"><span>Cancellation window (days)</span><input class="in" type="number" [(ngModel)]="Edit.CancellationWindowDays" (ngModelChange)="Touch()" /></label>
                                    <div class="fld"><span>Terms</span><div class="ro">{{ TermsOf(c.ID).length }} · {{ CommittedOf(c.ID) | currency: 'USD' : 'symbol' : '1.0-0' }} committed</div></div>
                                </div>
                            </fieldset>
                        </div>

                        <div *ngIf="Tab === 'terms'">
                            <div class="cb" *ngIf="TermsOf(c.ID).length">
                                <div class="tl-row" *ngFor="let t of TermsOf(c.ID)">
                                    <div class="tl-w">Term {{ t.TermNumber }}<br /><span style="color:var(--mj-text-muted,#64748b)">{{ t.StartDate | date: 'yyyy' }}</span></div>
                                    <div>
                                        <div class="tl-bar"><div class="tl-fill" [ngClass]="Fill(t)" style="width:100%">
                                            {{ t.StartDate | date: 'mediumDate' }} – {{ t.EndDate | date: 'mediumDate' }} · {{ t.Status }}
                                        </div></div>
                                        <div class="tl-m">
                                            <span>Committed <strong>{{ t.CommittedAmount | currency: 'USD' : 'symbol' : '1.0-0' }}</strong></span>
                                            <span>{{ t.BillingFrequency }}</span>
                                            <span *ngIf="t.EscalationPercent != null">+{{ t.EscalationPercent * 100 | number: '1.0-2' }}%<span *ngIf="t.MaxEscalationPercent != null"> (cap {{ t.MaxEscalationPercent * 100 | number: '1.0-2' }}%)</span></span>
                                            <span *ngIf="t.RenewalNoticeDays != null">{{ t.RenewalNoticeDays }}d notice</span>
                                            <span *ngIf="t.ExecutedDate">executed {{ t.ExecutedDate | date: 'mediumDate' }}</span>
                                        </div>
                                    </div>
                                </div>
                            </div>
                            <div class="empty" *ngIf="!TermsOf(c.ID).length">No terms on this contract yet.</div>
                            <mj-explorer-entity-data-grid [Params]="P.terms" [Height]="220" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                        </div>

                        <div *ngIf="Tab === 'coverage'">
                            <mj-explorer-entity-data-grid [Params]="P.lines" [Height]="400" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                            <div class="note ok">A contract discount <strong>overrides</strong> order-level discounting rather than stacking, so the value here is the operative one.</div>
                        </div>
                        <div *ngIf="Tab === 'billing'">
                            <div class="ch">Schedules</div>
                            <mj-explorer-entity-data-grid [Params]="P.schedules" [Height]="170" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                            <div class="ch">Billing events</div>
                            <mj-explorer-entity-data-grid [Params]="P.events" [Height]="260" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                        </div>
                        <div *ngIf="Tab === 'commitments'">
                            <mj-explorer-entity-data-grid [Params]="P.commitments" [Height]="400" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                        </div>
                        <div *ngIf="Tab === 'amendments'">
                            <mj-explorer-entity-data-grid [Params]="P.amendments" [Height]="400" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                            <div class="note gap">Amendments change a <strong>live</strong> term; renewals start a new one.</div>
                        </div>
                        <div *ngIf="Tab === 'documents'">
                            <div class="note gap" style="margin:16px;">
                                Documents attach through MJ's polymorphic <code>__mj.FileEntityRecordLink</code> — not a column
                                here. The record-scoped panel is mounted on the full record form, since MJ ships no such widget yet.
                            </div>
                        </div>
                        <div *ngIf="Tab === 'history'">
                            <mj-explorer-entity-data-grid [Params]="P.eventlog" [Height]="400" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                            <div class="note info">The immutable <strong>system</strong> record. Customer-visible events also write a <code>common.Activity</code> row.</div>
                        </div>

                        <div class="foot" *ngIf="Tab === 'overview'">
                            <span class="msg">{{ Message || 'Edits save straight to the record. Validation lives in the database for now.' }}</span>
                            <span class="sp">
                                <button mjButton (click)="ResetEdits()" [disabled]="!Dirty">Discard</button>
                                <button mjButton="primary" [disabled]="!Dirty || Saving" (click)="SaveEdits()">{{ Saving ? 'Saving…' : 'Save changes' }}</button>
                            </span>
                        </div>
                    </div>
                </ng-container>
            </div>

            <!-- ============ 3. CREATE ============ -->
            <div class="wrap" *ngIf="Page === 'create'">
                <div class="sechead">
                    <h2>New contract</h2>
                    <p>Record what was agreed. The order is produced later by the billing engine — nothing here creates one.</p>
                </div>

                <div class="card">
                    <div class="ident">
                        <span class="n">New contract</span>
                        <span class="badge">Draft</span>
                        <span class="badge info" *ngIf="D.PricedAt">Priced as of {{ D.PricedAt }}</span>
                        <span class="sp">
                            <span class="modes">
                                <button [class.on]="Mode === 'fast'" (click)="Mode = 'fast'"><i class="fa-solid fa-bolt"></i> Fast entry</button>
                                <button [class.on]="Mode === 'detail'" (click)="Mode = 'detail'"><i class="fa-solid fa-list-check"></i> Detailed</button>
                            </span>
                        </span>
                    </div>

                    <div class="cb">
                        <fieldset class="pl">
                            <legend class="lg">The agreement</legend>
                            <div class="fg">
                                <label class="fld"><span>Contract number</span><input class="in" [(ngModel)]="D.ContractNumber" placeholder="CTR-001900" /></label>
                                <label class="fld"><span>Contract type</span>
                                    <select class="sel" [(ngModel)]="D.ContractTypeID">
                                        <option value="">Pick a type…</option>
                                        <option *ngFor="let t of Types" [value]="t.ID">{{ t.Name }}</option>
                                    </select>
                                </label>
                                <label class="fld"><span>Selling company</span>
                                    <select class="sel" [(ngModel)]="D.CompanyID">
                                        <option value="">Pick a company…</option>
                                        <option *ngFor="let c of Companies" [value]="c.ID">{{ c.Name }}</option>
                                    </select>
                                </label>
                                <label class="fld s2"><span>Customer organization</span>
                                    <select class="sel" [(ngModel)]="D.CustomerOrganizationID">
                                        <option value="">Pick a customer…</option>
                                        <option *ngFor="let o of Orgs" [value]="o.ID">{{ o.Name }}</option>
                                    </select>
                                    <span class="hint">An organization or a person, never both — the database enforces it.</span>
                                </label>
                                <label class="fld"><span>Status</span>
                                    <select class="sel" [(ngModel)]="D.Status"><option *ngFor="let s of StatusOptions" [value]="s">{{ s }}</option></select>
                                </label>
                                <label class="fld s3"><span>Description</span><textarea class="ta" rows="2" [(ngModel)]="D.Description" placeholder="What this agreement covers"></textarea></label>
                            </div>
                            <div class="fg" style="margin-top:14px;" *ngIf="Mode === 'detail'">
                                <label class="fld"><span>Customer person <span class="hint">instead of an organization</span></span>
                                    <select class="sel" [(ngModel)]="D.CustomerPersonID">
                                        <option value="">— none —</option>
                                        <option *ngFor="let p of People" [value]="p.ID">{{ p.Name }}</option>
                                    </select>
                                </label>
                                <label class="fld"><span>Primary contact</span>
                                    <select class="sel" [(ngModel)]="D.PrimaryContactPersonID">
                                        <option value="">— none —</option>
                                        <option *ngFor="let p of People" [value]="p.ID">{{ p.Name }}</option>
                                    </select>
                                </label>
                                <label class="fld"><span>Owner</span>
                                    <select class="sel" [(ngModel)]="D.OwnerUserID">
                                        <option value="">— none —</option>
                                        <option *ngFor="let u of Users" [value]="u.ID">{{ u.Name }}</option>
                                    </select>
                                </label>
                                <label class="fld s2"><span>Parent contract <span class="hint">MSA → SOW nesting</span></span>
                                    <select class="sel" [(ngModel)]="D.ParentContractID">
                                        <option value="">— none —</option>
                                        <option *ngFor="let pc of Contracts" [value]="pc.ID">{{ pc.ContractNumber }}</option>
                                    </select>
                                </label>
                            </div>
                        </fieldset>

                        <fieldset class="pl">
                            <legend class="lg">Dates &amp; pricing</legend>
                            <div class="fg">
                                <label class="fld"><span>Priced as of</span><input class="in" type="date" [(ngModel)]="D.PricedAt" />
                                    <span class="hint">Locks catalog prices onto this agreement. Backdate when entering paper signed earlier.</span></label>
                                <label class="fld"><span>Effective</span><input class="in" type="date" [(ngModel)]="D.EffectiveDate" /></label>
                                <label class="fld"><span>Executed</span><input class="in" type="date" [(ngModel)]="D.ExecutedDate" /></label>
                            </div>
                        </fieldset>

                        <fieldset class="pl">
                            <legend class="lg">Renewal &amp; termination</legend>
                            <div class="fg">
                                <label class="fld"><span>Auto-renew</span>
                                    <select class="sel" [(ngModel)]="D.AutoRenew">
                                        <option [ngValue]="true">Yes — renews without a deal</option>
                                        <option [ngValue]="false">No — renewal is a deal</option>
                                    </select>
                                </label>
                                <label class="fld"><span>Cancellation window (days)</span><input class="in" type="number" [(ngModel)]="D.CancellationWindowDays" /></label>
                                <label class="fld"><span>External reference</span><input class="in" [(ngModel)]="D.ExternalReferenceID" placeholder="CDP or counterparty ref" /></label>
                                <label class="fld s3" *ngIf="Mode === 'detail'"><span>Termination policy</span>
                                    <textarea class="ta" rows="2" [(ngModel)]="D.TerminationPolicy" placeholder="The clause as written"></textarea></label>
                            </div>
                        </fieldset>

                        <fieldset class="pl" style="margin-bottom:0;">
                            <legend class="lg" style="text-transform:none;letter-spacing:0;font-size:12.5px;">
                                <label style="display:flex;align-items:center;gap:8px;cursor:pointer;">
                                    <input type="checkbox" [(ngModel)]="D.CreateTerm" />
                                    Also create the first term — the period that actually carries the money and the dates
                                </label>
                            </legend>
                            <div class="fg" *ngIf="D.CreateTerm">
                                <label class="fld"><span>Start date</span><input class="in" type="date" [(ngModel)]="D.TermStart" /></label>
                                <label class="fld"><span>End date</span><input class="in" type="date" [(ngModel)]="D.TermEnd" /></label>
                                <label class="fld"><span>Committed amount</span><input class="in" type="number" [(ngModel)]="D.CommittedAmount" /></label>

                                <label class="fld"><span>Billing frequency</span>
                                    <select class="sel" [(ngModel)]="D.BillingFrequency">
                                        <option *ngFor="let f of Frequencies" [value]="f">{{ f }}</option>
                                    </select>
                                </label>
                                <label class="fld"><span>Billing anchor <span class="hint">month / day</span></span>
                                    <span style="display:flex;gap:8px;">
                                        <input class="in" type="number" min="1" max="12" placeholder="month" [(ngModel)]="D.AnchorMonth" />
                                        <input class="in" type="number" min="1" max="31" placeholder="day" [(ngModel)]="D.AnchorDay" />
                                    </span>
                                </label>
                                <label class="fld"><span>Payment terms</span>
                                    <select class="sel" [(ngModel)]="D.PaymentTermsTypeID">
                                        <option value="">— none —</option>
                                        <option *ngFor="let pt of PayTerms" [value]="pt.ID">{{ pt.Name }}</option>
                                    </select>
                                    <span class="hint">Owned by orders — this list comes from there.</span>
                                </label>

                                <ng-container *ngIf="Mode === 'detail'">
                                    <label class="fld"><span>Escalation %</span><input class="in" type="number" step="0.01" placeholder="4.0" [(ngModel)]="D.EscalationPercent" /></label>
                                    <label class="fld"><span>Escalation basis</span>
                                        <select class="sel" [(ngModel)]="D.EscalationBasis">
                                            <option value="">— none —</option>
                                            <option value="PriorTerm">on prior term</option>
                                            <option value="ListPrice">to list price</option>
                                            <option value="Index">by index</option>
                                        </select>
                                    </label>
                                    <label class="fld"><span>Escalation cap %</span><input class="in" type="number" step="0.01" placeholder="5.0" [(ngModel)]="D.MaxEscalationPercent" />
                                        <span class="hint">Ceiling on any renewal increase — the clause customers dispute.</span></label>

                                    <label class="fld"><span>Renewal notice (days)</span><input class="in" type="number" [(ngModel)]="D.RenewalNoticeDays" />
                                        <span class="hint">Notice before a price change — a different clause from cancellation.</span></label>
                                    <label class="fld"><span>Currency</span>
                                        <select class="sel" [(ngModel)]="D.CurrencyID">
                                            <option value="">— none —</option>
                                            <option *ngFor="let cu of Currencies" [value]="cu.ID">{{ cu.Name }}</option>
                                        </select>
                                        <span class="hint">Recorded only — nothing converts.</span>
                                    </label>
                                    <label class="fld"><span>Renewal probability %</span><input class="in" type="number" min="0" max="100" [(ngModel)]="D.RenewalProbability" />
                                        <span class="hint">Read by the renewal forecast in sales.</span></label>

                                    <label class="fld"><span>Early termination date</span><input class="in" type="date" [(ngModel)]="D.EarlyTerminationDate" /></label>
                                    <label class="fld"><span>Term executed</span><input class="in" type="date" [(ngModel)]="D.TermExecutedDate" /></label>
                                    <label class="fld"><span>Notes</span><input class="in" [(ngModel)]="D.TermNotes" /></label>
                                </ng-container>
                            </div>
                        </fieldset>
                    </div>

                    <div class="note gap" *ngIf="Mode === 'fast'">
                        <strong>Fast entry</strong> carries everything an ordinary agreement needs — parties, dates, the
                        pricing lock, renewal basics, and optionally the first term. <strong>Detailed</strong> adds the rest:
                        customer-as-person, contact and owner, MSA nesting, the termination clause, and the full escalation
                        set (basis, cap, notice, currency, probability). Switching keeps everything you have typed.
                    </div>
                    <div class="note err" *ngIf="Error">{{ Error }}</div>

                    <div class="foot">
                        <span class="msg">Created <strong>Draft</strong> — it bills nothing until a term is activated and a schedule exists.</span>
                        <span class="sp">
                            <button mjButton (click)="Page = 'contracts'">Cancel</button>
                            <button mjButton="primary" [disabled]="!CanCreate || Saving" (click)="Create()">
                                <i class="fa-solid fa-check"></i> {{ Saving ? 'Creating…' : 'Create contract' }}
                            </button>
                        </span>
                    </div>
                </div>
            </div>

            <!-- ============ 4. BILLING WORKLIST ============ -->
            <div class="wrap" *ngIf="Page === 'billing'">
                <div class="sechead">
                    <h2>Billing worklist</h2>
                    <p>What the scheduled job is about to do, and what it could not do. A failed event is never retried
                       automatically — retrying into a duplicate bill is worse than a late one — so anything red here stays
                       red until a person clears it.</p>
                </div>

                <div class="kpis">
                    <div class="kpi"><div class="l">Scheduled</div><div class="v">{{ Counts.Scheduled }}</div><div class="f">awaiting generation</div></div>
                    <div class="kpi"><div class="l">Generated</div><div class="v">{{ Counts.Generated }}</div><div class="f">orders produced</div></div>
                    <div class="kpi"><div class="l">Failed</div><div class="v err">{{ Counts.Failed }}</div><div class="f">needs a human</div></div>
                    <div class="kpi"><div class="l">Skipped</div><div class="v warn">{{ Counts.Skipped }}</div><div class="f">deliberately not billed</div></div>
                </div>

                <div class="card" *ngIf="Failed.length">
                    <div class="ch"><i class="fa-solid fa-circle-exclamation" style="color:var(--mj-status-error,#ef4444)"></i> Failed <span class="r">{{ Failed.length }}</span></div>
                    <div class="note err" *ngFor="let e of Failed">
                        <div><strong>{{ e.ScheduledDate | date: 'mediumDate' }}</strong> — {{ e.FailureReason }}</div>
                    </div>
                </div>

                <div class="card">
                    <div class="ch">All billing events</div>
                    <mj-explorer-entity-data-grid [Params]="P.allEvents" [Height]="420" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                </div>
            </div>

            <!-- ============ SETUP ============ -->
            <div class="wrap" *ngIf="Page === 'types'">
                <div class="sechead">
                    <h2>Contract types</h2>
                    <p>Configuration-as-data: the columns <em>are</em> the rules. A type carries the default term, cadence,
                       escalation and its cap, notice and cancellation windows — the engine reads them rather than branching
                       on a type name.</p>
                </div>
                <div class="card">
                    <mj-explorer-entity-data-grid [Params]="P.types" [Height]="440" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                </div>
            </div>

            </mj-left-nav-content>
        </mj-page-body>
    </mj-page-layout>
    `,
})
export class MJCContractsSectionComponent extends BaseResourceComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);
    private readonly nav = inject(NavigationService);

    public Page = 'contracts';
    public Tab = 'overview';
    public Mode: 'fast' | 'detail' = 'fast';
    public Saving = false;
    public Message = '';
    public Error = '';

    public Contracts: ContractRow[] = [];
    public Terms: TermRow[] = [];
    public Events: EventRow[] = [];
    public Types: Lookup[] = [];
    public Companies: Lookup[] = [];
    public Orgs: Lookup[] = [];
    public People: Lookup[] = [];
    public Users: Lookup[] = [];
    public PayTerms: Lookup[] = [];
    public Currencies: Lookup[] = [];
    /** Open contracts — the workspace is the tabbed EDITING space, so each tab owns its own buffer. */
    public readonly Open = new WorkspaceTabStore<TabState>();
    public readonly Frequencies = ['Monthly', 'Quarterly', 'SemiAnnual', 'Annual', 'Milestone', 'Custom'];
    public Counts = { Scheduled: 0, Generated: 0, Failed: 0, Skipped: 0 };

    public CurrentID: string | null = null;
    public D: Draft = MJCContractsSectionComponent.blank();

    public readonly StatusOptions = ['Draft', 'PendingSignature', 'Active', 'Expired', 'Terminated', 'Superseded'];
    public readonly Toolbar = { showSearch: true, searchPlaceholder: 'Search…', showAdd: true, showRefresh: true, showExport: true };

    /** Every grid's params in one map, so scoping a page is a single reassignment. */
    public P: Record<string, RunViewParams> = {
        contracts: { EntityName: E_CONTRACTS, OrderBy: 'ContractNumber' },
        types: { EntityName: E_TYPES, OrderBy: 'Name' },
        allEvents: { EntityName: E_EVENTS, OrderBy: 'ScheduledDate' },
        terms: { EntityName: E_TERMS },
        lines: { EntityName: E_LINES },
        schedules: { EntityName: E_SCHEDULES },
        events: { EntityName: E_EVENTS },
        commitments: { EntityName: E_COMMITMENTS },
        amendments: { EntityName: E_AMENDMENTS },
        eventlog: { EntityName: E_EVENTLOG },
    };

    private termsBy = new Map<string, TermRow[]>();

    private static blank(): Draft {
        const today = new Date().toISOString().slice(0, 10);
        return {
            ContractNumber: '', ContractTypeID: '', CompanyID: '', CustomerOrganizationID: '',
            CustomerPersonID: '', PrimaryContactPersonID: '', OwnerUserID: '', ParentContractID: '',
            Status: 'Draft', Description: '', EffectiveDate: '', ExecutedDate: '', PricedAt: today,
            AutoRenew: true, CancellationWindowDays: null, TerminationPolicy: '', ExternalReferenceID: '',
            CreateTerm: false,
            TermStart: '', TermEnd: '', CommittedAmount: null, BillingFrequency: 'Annual',
            AnchorMonth: null, AnchorDay: null, PaymentTermsTypeID: '', CurrencyID: '',
            EscalationPercent: null, EscalationBasis: '', MaxEscalationPercent: null,
            RenewalNoticeDays: null, RenewalProbability: null,
            EarlyTerminationDate: '', TermExecutedDate: '', TermNotes: '',
        };
    }

    public async ngOnInit(): Promise<void> {
        await this.load();
    }

    public override async GetResourceDisplayName(_d: ResourceData): Promise<string> { return 'Contracts'; }
    public override async GetResourceIconClass(_d: ResourceData): Promise<string> { return 'fa-solid fa-file-signature'; }

    public get NavSections(): MJLeftNavSection[] {
        return [
            { items: [
                { id: 'contracts', icon: 'fa-solid fa-file-signature', label: 'Contracts', description: 'The agreement roster', badge: this.Contracts.length || undefined },
                { id: 'workspace', icon: 'fa-solid fa-layer-group', label: 'Workspace', description: this.Current ? this.Current.ContractNumber : 'Open a contract' },
                { id: 'create', icon: 'fa-solid fa-plus', label: 'New contract', description: 'Fast or detailed entry' },
                { id: 'billing', icon: 'fa-solid fa-conveyor-belt', label: 'Billing worklist', description: 'Due, generated and failed', badge: this.Counts.Failed || undefined },
            ] },
            { label: 'Setup', items: [{ id: 'types', icon: 'fa-solid fa-sliders', label: 'Contract types', description: 'Defaults and rules' }] },
        ];
    }

    public get Tabs(): { k: string; l: string; n: number | null }[] {
        const id = this.CurrentID;
        return [
            { k: 'overview', l: 'Overview', n: null },
            { k: 'terms', l: 'Terms', n: id ? this.TermsOf(id).length : null },
            { k: 'coverage', l: 'Coverage', n: null },
            { k: 'billing', l: 'Billing', n: null },
            { k: 'commitments', l: 'Commitments', n: null },
            { k: 'amendments', l: 'Amendments', n: null },
            { k: 'documents', l: 'Documents', n: null },
            { k: 'history', l: 'History', n: null },
        ];
    }

    public get Current(): ContractRow | null {
        return this.CurrentID ? (this.Contracts.find((c) => c.ID === this.CurrentID) ?? null) : null;
    }

    /** The active tab's edit buffer. Tabs never share one. */
    public get Edit(): Partial<Draft> {
        return this.Open.ActiveTab?.State?.Edit ?? {};
    }
    public get Dirty(): boolean {
        return !!this.Open.ActiveTab?.Dirty;
    }
    public get Failed(): EventRow[] { return this.Events.filter((e) => e.Status === 'Failed'); }
    public get ActiveCount(): number { return this.Contracts.filter((c) => c.Status === 'Active').length; }
    public get TotalCommitted(): number { return this.Terms.filter((t) => t.Status === 'Active').reduce((s, t) => s + (t.CommittedAmount ?? 0), 0); }
    public get RenewingCount(): number {
        const now = Date.now(), horizon = now + 90 * 864e5;
        return this.Terms.filter((t) => t.EndDate && new Date(t.EndDate).getTime() >= now && new Date(t.EndDate).getTime() <= horizon).length;
    }
    public get CanCreate(): boolean {
        return !!(this.D.ContractNumber?.trim() && this.D.ContractTypeID && this.D.CompanyID && this.D.CustomerOrganizationID);
    }

    public TermsOf(id: string): TermRow[] { return this.termsBy.get(id) ?? []; }
    public CommittedOf(id: string): number { return this.TermsOf(id).reduce((s, t) => s + (t.CommittedAmount ?? 0), 0); }

    public Tone(s: string | null): string {
        switch (s) {
            case 'Active': case 'Generated': case 'Completed': case 'Applied': return 'ok';
            case 'PendingSignature': case 'Pending': case 'Scheduled': case 'Open': return 'info';
            case 'Failed': case 'Terminated': case 'Rejected': return 'err';
            case 'Expired': case 'Superseded': case 'Skipped': return 'warn';
            default: return '';
        }
    }
    public Fill(t: TermRow): string {
        return t.Status === 'Active' ? 'now' : (t.Status === 'Completed' || t.Status === 'Terminated') ? 'done' : 'next';
    }

    public OnNav(item: MJLeftNavItem): void { this.Page = item.id; this.cdr.detectChanges(); }
    public GoCreate(): void { this.Page = 'create'; this.Error = ''; this.cdr.detectChanges(); }

    /** The grid emits a navigation INTENT; MJ's NavigationService is what actually opens a tab. */
    public OnNavigate(e: FormNavigationEvent): void {
        if (e.Kind === 'record' && e.PrimaryKey) this.nav.OpenEntityRecord(e.EntityName, e.PrimaryKey);
        else if (e.Kind === 'new-record') this.nav.OpenNewEntityRecord(e.EntityName);
    }
    public OpenRecord(c: ContractRow): void { this.nav.OpenEntityRecord(E_CONTRACTS, CompositeKey.FromID(c.ID)); }

    /**
     * Roster row → the workspace, as a SESSION TAB. Several contracts stay open at once, which is how
     * they are actually read — a renewal beside its predecessor — and each tab carries its own edit
     * buffer so switching never leaks one contract's unsaved changes into another.
     */
    public OpenWorkspace(args: AfterRowClickEventArgs): void {
        const id = (args?.row as Record<string, unknown> | undefined)?.['ID'];
        if (typeof id !== 'string') return;
        const row = this.Contracts.find((c) => c.ID === id);
        if (!row) return;

        if (this.Open.Tabs.some((t) => t.Id === id)) {
            this.Open.Activate(id);
        } else {
            this.Open.Open({ Id: id, Label: row.ContractNumber, Icon: 'fa-solid fa-file-signature', Status: 'complete', State: { Row: row, Edit: this.bufferFor(row) } });
        }
        this.CurrentID = id;
        this.Tab = 'overview';
        this.Message = '';
        this.scope(id);
        this.Page = 'workspace';
        this.cdr.detectChanges();
    }

    public SwitchTab(id: string): void {
        this.Open.Activate(id);
        this.CurrentID = id;
        this.Tab = 'overview';
        this.Message = '';
        this.scope(id);
        this.cdr.detectChanges();
    }

    /** Closing a tab with unsaved edits confirms first — the one real hazard of session tabs. */
    public CloseTab(id: string): void {
        const tab = this.Open.Tabs.find((t) => t.Id === id);
        if (tab?.Dirty && !confirm('This contract has unsaved changes. Close it and discard them?')) return;
        this.Open.Close(id);
        this.CurrentID = this.Open.ActiveId;
        if (this.CurrentID) this.scope(this.CurrentID);
        this.cdr.detectChanges();
    }

    public Touch(): void {
        const t = this.Open.ActiveTab;
        if (t) this.Open.UpdateState(t.Id, t.State, true);
        this.Message = '';
    }

    public ResetEdits(): void {
        const t = this.Open.ActiveTab;
        const row = this.Current;
        if (t && row) {
            this.Open.UpdateState(t.Id, { Row: row, Edit: this.bufferFor(row) }, false);
            this.Open.MarkClean(t.Id);
        }
        this.cdr.detectChanges();
    }

    /** Writes through `BaseEntity` — the sanctioned write path, so entity rules and audit apply. */
    public async SaveEdits(): Promise<void> {
        if (!this.CurrentID) return;
        this.Saving = true; this.Message = '';
        try {
            const md = new Metadata();
            const rec = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACTS);
            if (!(await rec.Load(this.CurrentID))) { this.Message = 'Could not load that contract.'; return; }

            rec.ContractNumber = this.Edit.ContractNumber ?? rec.ContractNumber;
            rec.Status = (this.Edit.Status ?? rec.Status) as typeof rec.Status;
            rec.Description = this.Edit.Description || null;
            rec.ExternalReferenceID = this.Edit.ExternalReferenceID || null;
            rec.EffectiveDate = this.toDate(this.Edit.EffectiveDate);
            rec.ExecutedDate = this.toDate(this.Edit.ExecutedDate);
            rec.PricedAt = this.toDate(this.Edit.PricedAt);
            rec.AutoRenew = !!this.Edit.AutoRenew;
            rec.CancellationWindowDays = this.Edit.CancellationWindowDays ?? null;

            // Save returns false on failure — it does not throw.
            const ok = await rec.Save();
            this.Message = ok ? 'Saved.' : `Save failed: ${rec.LatestResult?.CompleteMessage ?? 'unknown error'}`;
            if (ok) {
                const t = this.Open.ActiveTab;
                if (t) this.Open.MarkClean(t.Id);
                await this.load();
            }
        } finally {
            this.Saving = false;
            this.cdr.detectChanges();
        }
    }

    /** Create → the record lands in the roster, then opens in the workspace. The golden path. */
    public async Create(): Promise<void> {
        this.Saving = true; this.Error = '';
        try {
            const md = new Metadata();
            const rec = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACTS);
            rec.NewRecord();
            rec.ContractNumber = this.D.ContractNumber.trim();
            rec.ContractTypeID = this.D.ContractTypeID;
            rec.CompanyID = this.D.CompanyID;
            rec.CustomerOrganizationID = this.D.CustomerOrganizationID || null;
            rec.CustomerPersonID = this.D.CustomerPersonID || null;
            rec.PrimaryContactPersonID = this.D.PrimaryContactPersonID || null;
            rec.OwnerUserID = this.D.OwnerUserID || null;
            rec.ParentContractID = this.D.ParentContractID || null;
            rec.TerminationPolicy = this.D.TerminationPolicy || null;
            rec.Status = this.D.Status as typeof rec.Status;
            rec.Description = this.D.Description || null;
            rec.ExternalReferenceID = this.D.ExternalReferenceID || null;
            rec.EffectiveDate = this.toDate(this.D.EffectiveDate);
            rec.ExecutedDate = this.toDate(this.D.ExecutedDate);
            rec.PricedAt = this.toDate(this.D.PricedAt);
            rec.AutoRenew = !!this.D.AutoRenew;
            rec.CancellationWindowDays = this.D.CancellationWindowDays ?? null;

            const ok = await rec.Save();
            if (!ok) { this.Error = `Could not create: ${rec.LatestResult?.CompleteMessage ?? 'unknown error'}`; return; }

            const newID = rec.ID;
            if (this.D.CreateTerm) await this.createFirstTerm(newID);

            await this.load();
            const row = this.Contracts.find((c) => c.ID === newID);
            if (row) this.Open.Open({ Id: newID, Label: row.ContractNumber, Icon: 'fa-solid fa-file-signature', Status: 'complete', State: { Row: row, Edit: this.bufferFor(row) } });
            this.CurrentID = newID;
            this.scope(newID);
            this.D = MJCContractsSectionComponent.blank();
            this.Tab = 'overview';
            this.Page = 'workspace';
        } finally {
            this.Saving = false;
            this.cdr.detectChanges();
        }
    }

    /**
     * The optional first term, written in the same action. Percent inputs are entered as PERCENT and
     * stored as a FRACTION (4.0 -> 0.04) because that is the schema's convention — the same shape
     * orders uses for OrderLine.DiscountPct.
     */
    private async createFirstTerm(contractID: string): Promise<void> {
        const md = new Metadata();
        const t = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERMS);
        t.NewRecord();
        t.ContractID = contractID;
        t.TermNumber = 1;
        t.Status = 'Pending';
        t.StartDate = this.toDate(this.D.TermStart) ?? new Date();
        t.EndDate = this.toDate(this.D.TermEnd) ?? new Date();
        t.BillingFrequency = this.D.BillingFrequency as typeof t.BillingFrequency;
        t.CommittedAmount = this.D.CommittedAmount ?? null;
        t.BillingAnchorMonth = this.D.AnchorMonth ?? null;
        t.BillingAnchorDay = this.D.AnchorDay ?? null;
        t.PaymentTermsTypeID = this.D.PaymentTermsTypeID || null;
        t.CurrencyID = this.D.CurrencyID || null;
        t.EscalationPercent = this.pct(this.D.EscalationPercent);
        t.EscalationBasis = (this.D.EscalationBasis || null) as typeof t.EscalationBasis;
        t.MaxEscalationPercent = this.pct(this.D.MaxEscalationPercent);
        t.RenewalNoticeDays = this.D.RenewalNoticeDays ?? null;
        t.RenewalProbability = this.pct(this.D.RenewalProbability);
        t.EarlyTerminationDate = this.toDate(this.D.EarlyTerminationDate);
        t.ExecutedDate = this.toDate(this.D.TermExecutedDate);
        t.Notes = this.D.TermNotes || null;

        if (!(await t.Save())) {
            this.Error = `Contract created, but the first term failed: ${t.LatestResult?.CompleteMessage ?? 'unknown error'}`;
        }
    }

    /** Percent in the UI, fraction in the database. */
    private pct(v: number | null): number | null {
        return v == null ? null : v / 100;
    }

    public async Refresh(): Promise<void> {
        await this.load();
        this.P = { ...this.P, contracts: { ...this.P['contracts'] } };
        this.cdr.detectChanges();
    }

    // ------------------------------------------------------------------ internals

    private toDate(v: string | undefined): Date | null {
        return v ? new Date(v + 'T00:00:00') : null;
    }

    private bufferFor(c: ContractRow): Partial<Draft> {
        return {
            ContractNumber: c.ContractNumber, Status: c.Status, Description: c.Description ?? '',
            ExternalReferenceID: c.ExternalReferenceID ?? '',
            EffectiveDate: (c.EffectiveDate ?? '').slice(0, 10), ExecutedDate: (c.ExecutedDate ?? '').slice(0, 10),
            PricedAt: (c.PricedAt ?? '').slice(0, 10), AutoRenew: c.AutoRenew,
            CancellationWindowDays: c.CancellationWindowDays,
        };
    }

    /** Params are REASSIGNED, never mutated — an in-place edit does not trip change detection. */
    private scope(contractID: string): void {
        const ids = this.TermsOf(contractID).map((t) => `'${t.ID}'`);
        const scope = ids.length ? `ContractTermID IN (${ids.join(',')})` : '1=0';
        this.P = {
            ...this.P,
            terms: { EntityName: E_TERMS, ExtraFilter: `ContractID='${contractID}'`, OrderBy: 'TermNumber' },
            lines: { EntityName: E_LINES, ExtraFilter: scope, OrderBy: 'DisplayOrder' },
            schedules: { EntityName: E_SCHEDULES, ExtraFilter: scope },
            events: { EntityName: E_EVENTS, ExtraFilter: scope, OrderBy: 'ScheduledDate' },
            commitments: { EntityName: E_COMMITMENTS, ExtraFilter: scope },
            amendments: { EntityName: E_AMENDMENTS, ExtraFilter: scope, OrderBy: 'AmendmentNumber' },
            eventlog: { EntityName: E_EVENTLOG, ExtraFilter: `ContractID='${contractID}'`, OrderBy: 'EventDate DESC' },
        };
    }

    /** One batch — six reads always needed together should not be six round trips. */
    private async load(): Promise<void> {
        const rv = new RunView();
        const [contracts, terms, events, types, companies, orgs, people, users, payterms, currencies] = await rv.RunViews([
            { EntityName: E_CONTRACTS, Fields: ['ID', 'ContractNumber', 'Status', 'Description', 'EffectiveDate', 'ExecutedDate', 'PricedAt', 'AutoRenew', 'CancellationWindowDays', 'ExternalReferenceID'], OrderBy: 'ContractNumber', ResultType: 'simple' },
            { EntityName: E_TERMS, Fields: ['ID', 'ContractID', 'TermNumber', 'Status', 'StartDate', 'EndDate', 'CommittedAmount', 'EscalationPercent', 'MaxEscalationPercent', 'RenewalNoticeDays', 'BillingFrequency', 'ExecutedDate'], OrderBy: 'TermNumber', ResultType: 'simple' },
            { EntityName: E_EVENTS, Fields: ['ID', 'ContractTermID', 'ScheduledDate', 'Status', 'ComputedAmount', 'FailureReason'], OrderBy: 'ScheduledDate', ResultType: 'simple' },
            { EntityName: E_TYPES, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_COMPANIES, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_ORGS, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_PEOPLE, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_USERS, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_PAYTERMS, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_CURRENCIES, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
        ]);

        // RunView reports failure via Success — it never throws — so each result is checked.
        this.Contracts = contracts?.Success ? (contracts.Results as ContractRow[]) : [];
        this.Terms = terms?.Success ? (terms.Results as TermRow[]) : [];
        this.Events = events?.Success ? (events.Results as EventRow[]) : [];
        this.Types = types?.Success ? (types.Results as Lookup[]) : [];
        this.Companies = companies?.Success ? (companies.Results as Lookup[]) : [];
        this.Orgs = orgs?.Success ? (orgs.Results as Lookup[]) : [];
        this.People = people?.Success ? (people.Results as Lookup[]) : [];
        this.Users = users?.Success ? (users.Results as Lookup[]) : [];
        this.PayTerms = payterms?.Success ? (payterms.Results as Lookup[]) : [];
        this.Currencies = currencies?.Success ? (currencies.Results as Lookup[]) : [];

        this.Counts = {
            Scheduled: this.Events.filter((e) => e.Status === 'Scheduled').length,
            Generated: this.Events.filter((e) => e.Status === 'Generated').length,
            Failed: this.Events.filter((e) => e.Status === 'Failed').length,
            Skipped: this.Events.filter((e) => e.Status === 'Skipped').length,
        };

        this.termsBy = new Map();
        for (const t of this.Terms) {
            const list = this.termsBy.get(t.ContractID) ?? [];
            list.push(t);
            this.termsBy.set(t.ContractID, list);
        }
        this.cdr.detectChanges();
    }
}
