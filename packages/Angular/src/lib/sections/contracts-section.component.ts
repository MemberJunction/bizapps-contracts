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
import { BaseFormsModule, MJFormPresenterService } from '@memberjunction/ng-base-forms';
import type { FormNavigationEvent } from '@memberjunction/ng-base-forms';
import {
    MJLeftNavComponent, MJLeftNavContentComponent, MJPageLayoutComponent, MJPageHeaderComponent,
    MJPageBodyComponent, MJButtonDirective,
    type MJLeftNavSection, type MJLeftNavItem,
} from '@memberjunction/ng-ui-components';
import { RunView, Metadata, CompositeKey, type RunViewParams } from '@memberjunction/core';
import type { ResourceData } from '@memberjunction/core-entities';
// The app's OWN typed Remote Operation clients — generated from metadata/remote-operations/ into the
// browser-safe Entities package. The UI calls these; it does not reimplement what they decide.
import {
    ContractsActivateTermOperation,
    ContractsRenewTermOperation,
    ContractsTerminateContractOperation,
    type RenewTermOutput,
    type TerminateContractOutput,
} from '@mj-biz-apps/contracts-entities';
import type { AfterRowClickEventArgs } from '@memberjunction/ng-entity-viewer';
import type {
    mjBizAppsContractsContractEntity,
    mjBizAppsContractsContractTermEntity,
    mjBizAppsContractsContractLineEntity,
} from '@mj-biz-apps/contracts-entities';
// Accounting's session-tab framework — marked TRANSFER-BACKLOG (destined for MJ base); Marcelo
// authorised using it now rather than waiting for the move.
import { WorkspaceCardComponent, WorkspaceTabStore } from '@mj-biz-apps/accounting-ng';

const E_CONTRACTS = 'MJ_BizApps_Contracts: Contracts';
const E_TYPES = 'MJ_BizApps_Contracts: Contract Types';
const E_TERMS = 'MJ_BizApps_Contracts: Contract Terms';
const E_LINES = 'MJ_BizApps_Contracts: Contract Lines';
// Products belong to ORDERS. Contracts reads the catalog it commits to; it does not own one —
// FKs point upstream, and a second product list here would be a second thing to disagree with.
const E_PRODUCTS = 'MJ_BizApps_Orders: Products';
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

/** One entry in a contract's audit trail. The vocabulary is closed and the rows cannot be edited. */
interface LogRow {
    ID: string; ContractID: string; ContractTermID: string | null;
    EventType: string; EventDate: Date; Payload: string | null; PerformedByUser: string | null;
}

/**
 * One row of coverage on the first term — what the contract actually entitles the customer to.
 *
 * This exists because a term with no lines is not activatable: `Contracts.ActivateTerm` refuses it,
 * on the grounds that an Active term covering nothing bills nothing. Without a way to enter coverage
 * at creation, everything a person creates in the app is a dead end — it can never be activated and
 * therefore never renewed. `ContractedUnitPrice` is nullable on purpose: null means "resolve from the
 * catalog", which is a different statement from zero.
 */
interface LineDraft {
    ProductID: string;
    LineType: string;
    Quantity: number | null;
    ContractedUnitPrice: number | null;
    DiscountPercent: number | null;
    Description: string;
}

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
    // --- Coverage on that first term. Without at least one, the term cannot be activated.
    Lines: LineDraft[];
}


@RegisterClass(BaseResourceComponent, 'ContractsSectionResource')
@Component({
    selector: 'mjc-contracts-section',
    standalone: true,
    imports: [
        CommonModule, FormsModule, BaseFormsModule, MJButtonDirective,
        MJPageLayoutComponent, MJPageHeaderComponent, MJPageBodyComponent,
        MJLeftNavComponent, MJLeftNavContentComponent, WorkspaceCardComponent,
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

        /* The third column is the lifecycle action slot. Sized auto rather than fixed so a row with
           no available action collapses it instead of leaving a hole in the timeline. */
        .tl-row { display: grid; grid-template-columns: 104px 1fr auto; gap: 14px; padding: 11px 0; border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9); }
        .tl-act { display: flex; align-items: center; gap: 8px; }

        /* Preview surfaces — deliberately not modals. A renewal is something you read next to the
           timeline it changes, and a dialog would hide exactly the context that makes the numbers
           mean something. */
        .pv { margin: 14px 16px; border: 1px solid var(--mj-border-default, #e2e8f0); border-radius: var(--mj-radius-md, 6px); background: var(--mj-bg-elevated, #fff); overflow: hidden; }
        .pv-h { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 14px; background: var(--mj-color-neutral-50, #f8fafc); border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9); }
        .pv-s { margin-top: 2px; font-size: 12px; color: var(--mj-text-secondary, #475569); }
        .pv-t { width: 100%; border-collapse: collapse; font-size: 12.5px; }
        .pv-t th, .pv-t td { padding: 8px 14px; border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9); text-align: left; }
        .pv-t th { font-weight: 600; color: var(--mj-text-secondary, #475569); }
        .pv-t .r { text-align: right; font-variant-numeric: tabular-nums; }
        .pv-l { margin: 0; padding: 12px 14px 12px 32px; font-size: 12.5px; line-height: 1.7; color: var(--mj-text-secondary, #475569); }
        .pv-f { display: flex; justify-content: flex-end; gap: 8px; padding: 12px 14px; background: var(--mj-color-neutral-50, #f8fafc); border-top: 1px solid var(--mj-border-subtle, #f1f5f9); }
        .tm { display: flex; align-items: flex-end; gap: 12px; padding: 12px 0 0; margin-top: 12px; border-top: 1px solid var(--mj-border-subtle, #f1f5f9); }

        .ev { display: grid; grid-template-columns: 110px 1fr; gap: 14px; padding: 11px 0; border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9); font-size: 12.5px; }
        .ev:last-child { border-bottom: none; }
        .ev-d { color: var(--mj-text-secondary, #475569); }
        .ev-b { min-width: 0; }
        .ev-x { margin-top: 5px; display: flex; flex-wrap: wrap; gap: 12px; color: var(--mj-text-secondary, #475569); }
        .ev-x span::before { content: '· '; }
        .ev-x span:first-child::before { content: ''; }

        .cov { margin-top: 18px; padding-top: 16px; border-top: 1px solid var(--mj-border-subtle, #f1f5f9); }
        .cov-h { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
        .cov-t { width: 100%; border-collapse: collapse; font-size: 12.5px; }
        .cov-t th { text-align: left; font-weight: 600; font-size: 11px; letter-spacing: .04em; text-transform: uppercase; color: var(--mj-text-muted, #64748b); padding: 0 8px 6px; }
        .cov-t td { padding: 4px 8px; vertical-align: middle; }
        .cov-t .r { text-align: right; }
        .cov-t tfoot td { padding-top: 10px; border-top: 1px solid var(--mj-border-subtle, #f1f5f9); color: var(--mj-text-secondary, #475569); }
        /* Numeric inputs are narrow and right-aligned with tabular figures so a column of money reads
           as a column rather than as ragged text. */
        .cov-t .nm { width: 92px; text-align: right; font-variant-numeric: tabular-nums; }
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
        /* The card's body scrolls; its tab strip, identity band and footer stay put — long forms are
           the reason the workspace card has a fixed footer at all. */
        .scroller { max-height: calc(100vh - 340px); min-height: 320px; overflow-y: auto; padding: var(--mj-space-4, 16px); }
        .searchbar { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: var(--mj-space-4, 16px); }
        .searchbox { position: relative; flex: 1; min-width: 320px; }
        .searchbox i { position: absolute; left: 12px; top: 50%; transform: translateY(-50%); color: var(--mj-text-muted, #64748b); font-size: 13px; }
        .searchbox input { height: 40px; padding-left: 36px; font-size: 14px; }
        .chip { display: inline-flex; align-items: center; gap: 6px; height: 26px; padding: 0 10px; border-radius: 999px;
                font-size: 12px; font-weight: 600; background: var(--mj-brand-primary-tint, #e6f1f9); color: var(--mj-brand-primary, #0076b6); }
        .chip i { cursor: pointer; font-size: 10px; }
        .picker { display: flex; flex-direction: column; }
        .pick { display: flex; align-items: center; gap: 12px; padding: 10px 16px; border: none; background: transparent;
                border-bottom: 1px solid var(--mj-border-subtle, #f1f5f9); font-family: inherit; font-size: 13px;
                cursor: pointer; text-align: left; color: var(--mj-text-primary, #1e293b); }
        .pick:last-child { border-bottom: none; }
        .pick:hover { background: var(--mj-bg-surface-hover, #f1f5f9); }
        .pick.on { background: var(--mj-brand-primary-tint, #e6f1f9); }
        .pick .pn { font-weight: 700; min-width: 128px; }
        .pick .pd { color: var(--mj-text-secondary, #475569); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
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
                <div class="searchbar">
                    <span class="searchbox">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input class="in" placeholder="Find a contract — number, description or external reference…"
                               [(ngModel)]="Query" (ngModelChange)="cdrTick()" />
                    </span>
                    <select class="sel" style="width:170px" [(ngModel)]="StatusFilter" (ngModelChange)="cdrTick()">
                        <option value="">All statuses</option>
                        <option *ngFor="let s of StatusOptions" [value]="s">{{ s }}</option>
                    </select>
                    <button mjButton (click)="ClearSearch()" *ngIf="Query || StatusFilter">Clear</button>
                </div>

                <div class="card" *ngIf="Query || StatusFilter">
                    <div class="ch">Matches <span class="r">{{ Matches.length }}</span></div>
                    <div class="picker" *ngIf="Matches.length">
                        <button class="pick" *ngFor="let m of Matches" [class.on]="m.ID === CurrentID" (click)="Load(m)">
                            <span class="pn">{{ m.ContractNumber }}</span>
                            <span class="badge" [ngClass]="Tone(m.Status)">{{ m.Status }}</span>
                            <span class="pd">{{ m.Description || '—' }}</span>
                        </button>
                    </div>
                    <div class="empty" *ngIf="!Matches.length">Nothing matches that search.</div>
                </div>

                <div class="sechead" *ngIf="!Current">
                    <h2>Contract workspace</h2>
                    <p>Search above to open a contract, or pick one from the Contracts page. Opening the
                       <strong>Full record</strong> uses MJ's record viewer and its tab system.</p>
                </div>

                <ng-container *ngIf="Current as c">
                    <div class="card">
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

                                <!-- Ending an agreement is not a status dropdown. It stops future billing,
                                     which is the part that actually matters, so it gets a deliberate control
                                     with a required reason and a preview of exactly what will be cancelled. -->
                                <div class="tm" *ngIf="CanTerminate(c)">
                                    <label class="fld"><span>Termination reason</span>
                                        <input class="in" [(ngModel)]="Op.Reason" placeholder="Why is this ending?" />
                                    </label>
                                    <label class="fld"><span>Effective date</span>
                                        <input class="in" type="date" [(ngModel)]="Op.EffectiveDate" />
                                    </label>
                                    <button mjButton="danger" [disabled]="Op.Busy || !Op.Reason.trim()"
                                            (click)="PreviewTermination(c)">
                                        <i class="fa-solid fa-ban"></i> Terminate…
                                    </button>
                                </div>

                                <div class="pv" *ngIf="Op.Termination as t">
                                    <div class="pv-h">
                                        <strong>Terminating {{ c.ContractNumber }}</strong>
                                        <span class="badge warn">effective {{ t.EffectiveDate | date: 'mediumDate' }}</span>
                                    </div>
                                    <ul class="pv-l">
                                        <li><strong>{{ t.TermsTerminated }}</strong> live term(s) will be terminated.</li>
                                        <li><strong>{{ t.BillingEventsCancelled }}</strong> future billing event(s) will be cancelled.</li>
                                        <li *ngIf="t.BillingEventsRetained">
                                            <strong>{{ t.BillingEventsRetained }}</strong> event(s) on or before that date
                                            <em>stay</em> — those periods were covered and are still owed.
                                        </li>
                                    </ul>
                                    <div class="pv-f">
                                        <button mjButton [disabled]="Op.Busy" (click)="CancelPreview()">Cancel</button>
                                        <button mjButton="danger" [disabled]="Op.Busy" (click)="ConfirmTermination(c)">
                                            {{ Op.Busy ? 'Terminating…' : 'Terminate this contract' }}
                                        </button>
                                    </div>
                                </div>
                            </fieldset>
                        </div>

                        <div *ngIf="Tab === 'terms'">
                            <div class="cov-h" style="padding:12px 16px 0;">
                                <div class="pv-s">Each term is a period with its own dates, money and cadence.</div>
                                <button mjButton (click)="AddTerm(c)"><i class="fa-solid fa-plus"></i> Add term</button>
                            </div>
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
                                    <div class="tl-act">
                                        <button mjButton (click)="EditTerm(t)" title="Edit this term in its own form">
                                            <i class="fa-solid fa-pen"></i>
                                        </button>
                                        <button mjButton (click)="AddCoverage(t)" title="Add a coverage line to this term">
                                            <i class="fa-solid fa-layer-group"></i>
                                        </button>
                                        <button mjButton *ngIf="CanActivate(t)" [disabled]="Op.Busy"
                                                (click)="Activate(t)" title="Move the term to Active and create its billing schedule">
                                            <i class="fa-solid fa-play"></i> Activate
                                        </button>
                                        <button mjButton *ngIf="CanRenew(t)" [disabled]="Op.Busy"
                                                (click)="PreviewRenewal(t)" title="See the escalated numbers before committing">
                                            <i class="fa-solid fa-rotate"></i> Renew…
                                        </button>
                                    </div>
                                </div>
                            </div>

                            <!-- Renewal preview. The numbers here come from the SAME operation that will
                                 create the term — the confirm button re-runs it without PreviewOnly, so
                                 what a person approves is what gets written. -->
                            <div class="pv" *ngIf="Op.Renewal as r">
                                <div class="pv-h">
                                    <div>
                                        <strong>Renewal preview — term {{ r.NewTermNumber }}</strong>
                                        <div class="pv-s">{{ r.StartDate | date: 'mediumDate' }} – {{ r.EndDate | date: 'mediumDate' }}</div>
                                    </div>
                                    <span class="badge" [class.warn]="r.EscalationWasClamped">
                                        +{{ (r.AppliedEscalationPercent || 0) * 100 | number: '1.0-2' }}%
                                        <ng-container *ngIf="r.EscalationWasClamped"> — capped</ng-container>
                                    </span>
                                </div>
                                <div class="note gap" *ngIf="r.EscalationWasClamped">
                                    The requested increase exceeded this term's negotiated ceiling, so the
                                    <strong>ceiling</strong> was applied — not the request, and not a refusal.
                                </div>
                                <table class="pv-t">
                                    <thead><tr><th>Line</th><th class="r">Current</th><th class="r">Renewed</th></tr></thead>
                                    <tbody>
                                        <tr *ngFor="let l of r.Lines">
                                            <td>{{ l.Description }}</td>
                                            <td class="r">{{ l.PreviousUnitPrice == null ? '—' : (l.PreviousUnitPrice | currency: 'USD') }}</td>
                                            <td class="r"><strong>{{ l.NewUnitPrice == null ? '—' : (l.NewUnitPrice | currency: 'USD') }}</strong></td>
                                        </tr>
                                    </tbody>
                                </table>
                                <div class="pv-f">
                                    <button mjButton [disabled]="Op.Busy" (click)="CancelPreview()">Cancel</button>
                                    <button mjButton="primary" [disabled]="Op.Busy" (click)="ConfirmRenewal()">
                                        {{ Op.Busy ? 'Renewing…' : 'Create this term' }}
                                    </button>
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
                            <div class="cb" *ngIf="LogOf(c.ID).length">
                                <div class="ev" *ngFor="let e of LogOf(c.ID)">
                                    <div class="ev-d">
                                        {{ e.EventDate | date: 'mediumDate' }}<br />
                                        <span class="pv-s">{{ e.EventDate | date: 'shortTime' }}</span>
                                    </div>
                                    <div class="ev-b">
                                        <div>
                                            <span class="badge" [ngClass]="EventTone(e.EventType)">{{ EventLabel(e.EventType) }}</span>
                                            <span class="pv-s" *ngIf="e.PerformedByUser"> by {{ e.PerformedByUser }}</span>
                                        </div>
                                        <div class="ev-x" *ngIf="EventDetail(e.Payload).length">
                                            <span *ngFor="let d of EventDetail(e.Payload)">{{ d }}</span>
                                        </div>
                                    </div>
                                </div>
                            </div>
                            <div class="empty" *ngIf="!LogOf(c.ID).length">Nothing has happened to this contract yet.</div>
                            <div class="note ok">
                                This log is <strong>append-only and enforced</strong> — an event cannot be edited or
                                deleted, and <code>EventType</code> is a closed vocabulary. An audit trail whose
                                immutability is only a comment is not an audit trail.
                            </div>
                            <mj-explorer-entity-data-grid [Params]="P.eventlog" [Height]="260" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
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

            <!-- ============ 3. CREATE — accounting's workspace structure ============ -->
            <div class="wrap" *ngIf="Page === 'create'">
                <div class="sechead">
                    <h2>New contract</h2>
                    <p>Record what was agreed. The order is produced later by the billing engine — nothing here creates one.
                       Several drafts can be open at once; each tab keeps its own.</p>
                </div>

                <mj-workspace-card
                    AriaLabel="Contract entry workspace"
                    [Tabs]="Drafts.Tabs"
                    [ActiveId]="Drafts.ActiveId"
                    NewTabLabel="New contract"
                    [ShowFooter]="true"
                    ConfirmLabel="Create contract"
                    ConfirmIcon="fa-solid fa-check"
                    [ConfirmDisabled]="!CanCreate"
                    [ConfirmBusy]="Saving"
                    ConfirmBusyLabel="Creating…"
                    DraftLabel="Keep as draft tab"
                    [ShowDraft]="true"
                    (TabSelected)="SwitchDraft($event)"
                    (TabClosed)="CloseDraft($event)"
                    (NewTabRequested)="NewDraft()"
                    (Confirm)="Create()"
                    (SaveDraft)="KeepDraft()"
                    (Discard)="DiscardDraft()">

                    <span workspaceFooterNote>
                        Created <strong>Draft</strong> — it bills nothing until a term is activated and a schedule exists.
                        <ng-container *ngIf="Error"> · <span style="color:var(--mj-status-error-text,#b91c1c)">{{ Error }}</span></ng-container>
                    </span>

                    <ng-container workspaceHeader>
                        <span class="n">{{ D.ContractNumber || 'New contract' }}</span>
                        <span class="badge">Draft</span>
                        <span class="badge info" *ngIf="D.PricedAt">Priced as of {{ D.PricedAt }}</span>
                        <span class="modes" style="margin-left:auto;">
                            <button [class.on]="Mode === 'fast'" (click)="Mode = 'fast'"><i class="fa-solid fa-bolt"></i> Fast entry</button>
                            <button [class.on]="Mode === 'detail'" (click)="Mode = 'detail'"><i class="fa-solid fa-list-check"></i> Detailed</button>
                        </span>
                    </ng-container>

                    <div class="scroller">
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
                                        <option *ngFor="let co of Companies" [value]="co.ID">{{ co.Name }}</option>
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
                                    <select class="sel" [(ngModel)]="D.Status"><option *ngFor="let st of StatusOptions" [value]="st">{{ st }}</option></select>
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
                                <label class="fld"><span>Executed</span><input class="in" type="date" [(ngModel)]="D.ExecutedDate" />
                                    <span class="hint">May precede Effective — signing in December for a January term is ordinary.</span></label>
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
                                    Also create the first term — the period that carries the money and the dates
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
                                    <label class="fld"><span>Renewal probability %</span><input class="in" type="number" min="0" max="100" [(ngModel)]="D.RenewalProbability" /></label>
                                    <label class="fld"><span>Early termination date</span><input class="in" type="date" [(ngModel)]="D.EarlyTerminationDate" /></label>
                                    <label class="fld"><span>Term executed</span><input class="in" type="date" [(ngModel)]="D.TermExecutedDate" /></label>
                                    <label class="fld"><span>Notes</span><input class="in" [(ngModel)]="D.TermNotes" /></label>
                                </ng-container>
                            </div>

                            <!-- COVERAGE. Not optional decoration: a term with no lines cannot be
                                 activated, so a contract created without coverage is a dead end that
                                 can never be activated and therefore never renewed. -->
                            <div class="cov" *ngIf="D.CreateTerm">
                                <div class="cov-h">
                                    <div>
                                        <strong>Coverage</strong>
                                        <div class="pv-s">What this term entitles the customer to</div>
                                    </div>
                                    <button mjButton (click)="AddLine()"><i class="fa-solid fa-plus"></i> Add line</button>
                                </div>

                                <div class="note gap" *ngIf="!TermIsCovered" style="margin:0 0 12px;">
                                    A term with no coverage <strong>cannot be activated</strong> — add at least one
                                    line, or the contract will be created but stuck in Draft.
                                </div>

                                <table class="cov-t" *ngIf="D.Lines.length">
                                    <thead>
                                        <tr>
                                            <th>Product</th><th>Type</th><th class="r">Qty</th>
                                            <th class="r">Unit price</th><th class="r">Disc %</th><th>Description</th><th></th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <tr *ngFor="let l of D.Lines; let i = index">
                                            <td>
                                                <select class="sel" [(ngModel)]="l.ProductID" [ngModelOptions]="{standalone:true}">
                                                    <option value="">Choose a product…</option>
                                                    <option *ngFor="let p of Products" [value]="p.ID">{{ p.Name }}</option>
                                                </select>
                                            </td>
                                            <td>
                                                <select class="sel" [(ngModel)]="l.LineType" [ngModelOptions]="{standalone:true}">
                                                    <option *ngFor="let t of LineTypes" [value]="t">{{ t }}</option>
                                                </select>
                                            </td>
                                            <td class="r"><input class="in nm" type="number" min="0" [(ngModel)]="l.Quantity" [ngModelOptions]="{standalone:true}" /></td>
                                            <td class="r"><input class="in nm" type="number" min="0" step="0.01" placeholder="catalog" [(ngModel)]="l.ContractedUnitPrice" [ngModelOptions]="{standalone:true}" /></td>
                                            <td class="r"><input class="in nm" type="number" min="0" max="100" [(ngModel)]="l.DiscountPercent" [ngModelOptions]="{standalone:true}" /></td>
                                            <td><input class="in" [(ngModel)]="l.Description" [ngModelOptions]="{standalone:true}" placeholder="What this covers" /></td>
                                            <td><button mjButton (click)="RemoveLine(i)" title="Remove this line"><i class="fa-solid fa-xmark"></i></button></td>
                                        </tr>
                                    </tbody>
                                    <tfoot>
                                        <tr>
                                            <td colspan="6" class="r">
                                                Priced coverage <strong>{{ LinesSubtotal | currency: 'USD' }}</strong>
                                                <span class="pv-s" *ngIf="CatalogPricedCount">
                                                    · {{ CatalogPricedCount }} line(s) priced from the catalog, so not counted here
                                                </span>
                                            </td>
                                            <td></td>
                                        </tr>
                                    </tfoot>
                                </table>

                                <div class="note gap" style="margin:12px 0 0;" *ngIf="CatalogPricedCount">
                                    Leaving a unit price empty means <strong>resolve from the catalog</strong> — which is a
                                    different statement from a price of zero, and is why the field is not defaulted.
                                </div>
                            </div>
                        </fieldset>

                        <div class="note gap" style="margin:16px 0 0;" *ngIf="Mode === 'fast'">
                            <strong>Fast entry</strong> carries everything an ordinary agreement needs. <strong>Detailed</strong>
                            adds customer-as-person, contact and owner, MSA nesting, the termination clause and the full
                            escalation set. Switching keeps what you have typed.
                        </div>
                    </div>
                </mj-workspace-card>
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
    // MJ's 4-layer form architecture. Editing a term or a line opens ITS OWN registered form as a
    // slide-in rather than another hand-built field set here — one definition of what a term looks
    // like, reused everywhere, with the generated validation attached to it.
    private readonly forms = inject(MJFormPresenterService);

    public Page = 'contracts';
    public Tab = 'overview';
    public Mode: 'fast' | 'detail' = 'fast';
    public Saving = false;
    public Message = '';
    public Error = '';

    public Contracts: ContractRow[] = [];
    public Terms: TermRow[] = [];
    public Events: EventRow[] = [];
    public Log: LogRow[] = [];
    public Types: Lookup[] = [];
    public Companies: Lookup[] = [];
    public Orgs: Lookup[] = [];
    public People: Lookup[] = [];
    public Users: Lookup[] = [];
    public PayTerms: Lookup[] = [];
    public Currencies: Lookup[] = [];
    public Products: Lookup[] = [];
    /** Mirrors CK_ContractLine_LineType exactly — the CHECK is the source of truth for this list. */
    public readonly LineTypes = ['Subscription', 'OneTime', 'Milestone', 'Usage', 'Minimum'];
    public readonly Frequencies = ['Monthly', 'Quarterly', 'SemiAnnual', 'Annual', 'Milestone', 'Custom'];
    /** Open drafts on the create page — accounting's card owns the strip; this owns the state. */
    public readonly Drafts = new WorkspaceTabStore<Draft>();
    public Query = '';
    public StatusFilter = '';
    public Counts = { Scheduled: 0, Generated: 0, Failed: 0, Skipped: 0 };

    public CurrentID: string | null = null;
    private fallbackDraft: Draft = MJCContractsSectionComponent.blank();
    /** The active draft's data. Each create tab keeps its own, so drafts never bleed together. */
    public get D(): Draft { return this.Drafts.ActiveTab?.State ?? this.fallbackDraft; }

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
            Lines: [],
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

    /** The workspace edits one contract at a time — MJ's record viewer is where several are held open. */
    public Buffer: Partial<Draft> = {};
    public BufferDirty = false;
    public get Edit(): Partial<Draft> { return this.Buffer; }
    public get Dirty(): boolean { return this.BufferDirty; }
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

    public OnNav(item: MJLeftNavItem): void {
        this.Page = item.id;
        if (item.id === 'create' && !this.Drafts.Count) this.NewDraft();
        this.cdr.detectChanges();
    }

    /**
     * The workspace's contract picker. This one filters IN MEMORY on purpose, unlike a grid search:
     * the roster is already loaded for the health strip, the result set is small, and typing should
     * narrow instantly rather than round-trip. The roster grid keeps its own server-side toolbar
     * search for the paged, full-table case.
     */
    public get Matches(): ContractRow[] {
        const q = this.Query.trim().toLowerCase();
        if (!q && !this.StatusFilter) return [];
        return this.Contracts.filter((c) => {
            const okStatus = !this.StatusFilter || c.Status === this.StatusFilter;
            const okText = !q
                || c.ContractNumber.toLowerCase().includes(q)
                || (c.Description ?? '').toLowerCase().includes(q)
                || (c.ExternalReferenceID ?? '').toLowerCase().includes(q);
            return okStatus && okText;
        }).slice(0, 25);
    }

    /** Open a searched contract straight into the workspace. */
    public Load(c: ContractRow): void {
        this.CurrentID = c.ID;
        this.Tab = 'overview';
        this.Message = '';
        this.Buffer = this.bufferFor(c);
        this.BufferDirty = false;
        this.scope(c.ID);
        this.cdr.detectChanges();
    }

    public ClearSearch(): void { this.Query = ''; this.StatusFilter = ''; this.cdr.detectChanges(); }
    public cdrTick(): void { this.cdr.detectChanges(); }

    // ---- create-page draft tabs (accounting's workspace card) ----

    public NewDraft(): void {
        const d = MJCContractsSectionComponent.blank();
        const id = `draft-${Date.now()}`;
        this.Drafts.Open({ Id: id, Label: 'New contract', Icon: 'fa-solid fa-file-circle-plus', Status: 'draft', State: d });
        this.Error = '';
        this.cdr.detectChanges();
    }

    public SwitchDraft(id: string): void { this.Drafts.Activate(id); this.Error = ''; this.cdr.detectChanges(); }

    public CloseDraft(id: string): void {
        const t = this.Drafts.Tabs.find((x) => x.Id === id);
        if (t?.Dirty && !confirm('This draft has unsaved entry. Close it?')) return;
        this.Drafts.Close(id);
        this.cdr.detectChanges();
    }

    /** Keep the draft as a tab — the card's secondary action; nothing is written. */
    public KeepDraft(): void {
        const t = this.Drafts.ActiveTab;
        if (t) this.Drafts.UpdateState(t.Id, t.State, false);
        this.Error = '';
        this.cdr.detectChanges();
    }

    public DiscardDraft(): void {
        const t = this.Drafts.ActiveTab;
        if (t) this.Drafts.Close(t.Id);
        if (!this.Drafts.Count) this.NewDraft();
        this.cdr.detectChanges();
    }
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
        this.Load(row);
        this.Page = 'workspace';
        this.cdr.detectChanges();
    }

    // ---- lifecycle operations ---------------------------------------------------------------------
    //
    // Every one of these drives the app's OWN typed client (`Contracts*Operation` from the browser-safe
    // Entities package), which is the same contract the server implements. The UI holds no copy of the
    // rules: the escalation ceiling, the date arithmetic and the cancelled/retained split all come back
    // from the operation. A preview here is the real computation with the write suppressed, so the
    // numbers a person approves are the numbers that get written — not a second implementation that
    // agrees today and drifts later.

    public Op: {
        Busy: boolean;
        TermID: string | null;
        Reason: string;
        EffectiveDate: string;
        Renewal: RenewTermOutput | null;
        Termination: TerminateContractOutput | null;
    } = { Busy: false, TermID: null, Reason: '', EffectiveDate: '', Renewal: null, Termination: null };

    /** Only a term that has not started can be activated. */
    public CanActivate(t: TermRow): boolean {
        return t.Status === 'Pending' || t.Status === 'PendingSignature';
    }

    /** Only a running term can be renewed — and only once, which the operation itself enforces. */
    public CanRenew(t: TermRow): boolean {
        return t.Status === 'Active';
    }

    public CanTerminate(c: ContractRow): boolean {
        return c.Status !== 'Terminated' && c.Status !== 'Superseded';
    }

    public CancelPreview(): void {
        this.Op.Renewal = null;
        this.Op.Termination = null;
        this.Op.TermID = null;
        this.cdr.detectChanges();
    }

    public async Activate(t: TermRow): Promise<void> {
        await this.run(async () => {
            const res = await new ContractsActivateTermOperation().Execute({ ContractTermID: t.ID });
            const out = res.Output;
            if (!res.Success || !out?.Success) {
                this.Error = out?.Message ?? res.ErrorMessage ?? 'Activation failed.';
                return;
            }
            this.Message = out.Message ?? 'Term activated.';
            await this.Refresh();
        });
    }

    public async PreviewRenewal(t: TermRow): Promise<void> {
        await this.run(async () => {
            const res = await new ContractsRenewTermOperation().Execute({ ContractTermID: t.ID, PreviewOnly: true });
            const out = res.Output;
            if (!res.Success || !out?.Success) {
                this.Error = out?.Message ?? res.ErrorMessage ?? 'Could not compute the renewal.';
                return;
            }
            this.Op.TermID = t.ID;
            this.Op.Renewal = out;
        });
    }

    public async ConfirmRenewal(): Promise<void> {
        const termID = this.Op.TermID;
        if (!termID) return;
        await this.run(async () => {
            const res = await new ContractsRenewTermOperation().Execute({ ContractTermID: termID });
            const out = res.Output;
            if (!res.Success || !out?.Success) {
                this.Error = out?.Message ?? res.ErrorMessage ?? 'Renewal failed.';
                return;
            }
            this.Message = out.Message ?? 'Renewed.';
            this.CancelPreview();
            await this.Refresh();
        });
    }

    public async PreviewTermination(c: ContractRow): Promise<void> {
        await this.run(async () => {
            const res = await new ContractsTerminateContractOperation().Execute({
                ContractID: c.ID,
                Reason: this.Op.Reason.trim(),
                EffectiveDate: this.Op.EffectiveDate || undefined,
                PreviewOnly: true,
            });
            const out = res.Output;
            if (!res.Success || !out?.Success) {
                this.Error = out?.Message ?? res.ErrorMessage ?? 'Could not compute the termination.';
                return;
            }
            this.Op.Termination = out;
        });
    }

    public async ConfirmTermination(c: ContractRow): Promise<void> {
        await this.run(async () => {
            const res = await new ContractsTerminateContractOperation().Execute({
                ContractID: c.ID,
                Reason: this.Op.Reason.trim(),
                EffectiveDate: this.Op.EffectiveDate || undefined,
            });
            const out = res.Output;
            if (!res.Success || !out?.Success) {
                this.Error = out?.Message ?? res.ErrorMessage ?? 'Termination failed.';
                return;
            }
            this.Message = out.Message ?? 'Contract terminated.';
            this.Op.Reason = '';
            this.CancelPreview();
            await this.Refresh();
        });
    }

    /**
     * One busy/error envelope for all of them. A thrown error is reported rather than swallowed —
     * an operation that fails silently in the UI is the same bug class as one that fails silently
     * on the server.
     */
    private async run(work: () => Promise<void>): Promise<void> {
        this.Op.Busy = true;
        this.Error = '';
        this.Message = '';
        this.cdr.detectChanges();
        try {
            await work();
        } catch (e) {
            this.Error = e instanceof Error ? e.message : String(e);
        } finally {
            this.Op.Busy = false;
            this.cdr.detectChanges();
        }
    }

    // ---- editing through MJ's form architecture ---------------------------------------------------
    //
    // These open the entity's OWN registered form (the priority-2 custom one where we have written it,
    // the generated one otherwise) as a slide-in. The alternative — another bespoke field set in this
    // component — would be a second definition of what a term is, and the two would drift.

    /** Edit an existing term in a slide-in, then refresh if anything was saved. */
    public async EditTerm(t: TermRow): Promise<void> {
        await this.presentForm({ EntityName: E_TERMS, RecordId: t.ID, Title: `Term ${t.TermNumber}` });
    }

    /** Add a term to the open contract, with the parent already filled in. */
    public async AddTerm(c: ContractRow): Promise<void> {
        await this.presentForm({
            EntityName: E_TERMS,
            NewRecordValues: { ContractID: c.ID, Status: 'Pending' },
            Title: `New term on ${c.ContractNumber}`,
        });
    }

    /** Add coverage to a term, with the parent already filled in. */
    public async AddCoverage(t: TermRow): Promise<void> {
        await this.presentForm({
            EntityName: E_LINES,
            NewRecordValues: { ContractTermID: t.ID, LineType: 'Subscription', Quantity: 1 },
            Title: `New line on term ${t.TermNumber}`,
        });
    }

    /**
     * One place that opens a form and reacts to the outcome. `AfterSaved()` resolves with the record
     * when something was written and null when the person cancelled — so a cancel must NOT refresh
     * (it would look like the cancel did something) and a save MUST (or the timeline shows stale data
     * next to a form that just changed it).
     */
    private async presentForm(options: { EntityName: string; RecordId?: string; NewRecordValues?: Record<string, unknown>; Title: string }): Promise<void> {
        const ref = this.forms.Open({
            EntityName: options.EntityName,
            RecordId: options.RecordId,
            NewRecordValues: options.NewRecordValues,
            Presentation: 'slide-in',
            EditMode: true,
            Title: options.Title,
        });
        const saved = await ref.AfterSaved();
        if (saved) {
            this.Message = `${options.Title} saved.`;
            await this.Refresh();
        }
    }

    // ---- coverage rows on the create page ---------------------------------------------------------

    public AddLine(): void {
        this.D.Lines.push({ ProductID: '', LineType: 'Subscription', Quantity: 1, ContractedUnitPrice: null, DiscountPercent: null, Description: '' });
        this.cdr.detectChanges();
    }

    public RemoveLine(i: number): void {
        this.D.Lines.splice(i, 1);
        this.cdr.detectChanges();
    }

    /**
     * True once the draft would produce an ACTIVATABLE term — i.e. a term with at least one line that
     * names a product. Surfaced in the UI so the dead end is visible while it can still be fixed,
     * rather than discovered later as a refusal from ActivateTerm.
     */
    public get TermIsCovered(): boolean {
        return this.D.Lines.some((l) => !!l.ProductID);
    }

    /** What the coverage adds up to, for the lines that state a price. */
    public get LinesSubtotal(): number {
        return this.D.Lines.reduce((sum, l) => {
            if (l.ContractedUnitPrice == null) return sum;
            const gross = l.ContractedUnitPrice * (l.Quantity ?? 1);
            return sum + gross * (1 - (l.DiscountPercent ?? 0) / 100);
        }, 0);
    }

    /** Lines priced from the catalog rather than the contract — they cannot be totalled here. */
    public get CatalogPricedCount(): number {
        return this.D.Lines.filter((l) => l.ProductID && l.ContractedUnitPrice == null).length;
    }

    // ---- the audit trail --------------------------------------------------------------------------

    public LogOf(contractID: string): LogRow[] {
        return this.Log.filter((l) => l.ContractID === contractID);
    }

    /** A human sentence for an event type. The vocabulary is closed, so this map is exhaustive. */
    public EventLabel(t: string): string {
        const map: Record<string, string> = {
            ContractCreated: 'Contract created',
            ContractExecuted: 'Contract executed',
            ContractTerminated: 'Contract terminated',
            ContractSuperseded: 'Superseded by a replacement',
            ContractExpired: 'Contract expired',
            SentForSignature: 'Sent for signature',
            SignatureRejected: 'Signature rejected',
            TermActivated: 'Term activated',
            TermRenewed: 'Term renewed',
            TermCompleted: 'Term completed',
            TermTerminated: 'Term terminated',
            AmendmentApplied: 'Amendment applied',
            BillingEventGenerated: 'Billing event generated',
            BillingEventFailed: 'Billing event failed',
        };
        return map[t] ?? t;
    }

    public EventTone(t: string): string {
        if (t.includes('Failed') || t.includes('Rejected') || t.includes('Terminated')) return 'err';
        if (t.includes('Activated') || t.includes('Executed') || t.includes('Renewed')) return 'ok';
        if (t.includes('Expired') || t.includes('Superseded')) return 'warn';
        return 'info';
    }

    /**
     * The parts of a payload worth reading, as short phrases. Deliberately a whitelist rather than a
     * dump of every key: an audit trail people actually read beats one that is technically complete.
     */
    public EventDetail(payload: string | null): string[] {
        if (!payload) return [];
        try {
            const p = JSON.parse(payload) as Record<string, unknown>;
            const out: string[] = [];
            if (typeof p.reason === 'string') out.push(p.reason);
            if (typeof p.termNumber === 'number') out.push(`term ${p.termNumber}`);
            if (typeof p.renewalOfTermNumber === 'number') out.push(`renewed from term ${p.renewalOfTermNumber}`);
            if (typeof p.appliedEscalationPercent === 'number') out.push(`+${(p.appliedEscalationPercent * 100).toFixed(2)}% applied`);
            if (p.escalationWasClamped === true) out.push('capped at the negotiated ceiling');
            if (typeof p.occurrences === 'number') out.push(`${p.occurrences} billing event(s) scheduled`);
            if (typeof p.lineCount === 'number') out.push(`${p.lineCount} line(s) carried forward`);
            if (typeof p.billingEventsCancelled === 'number') out.push(`${p.billingEventsCancelled} future billing event(s) cancelled`);
            if (typeof p.billingEventsRetained === 'number' && p.billingEventsRetained) out.push(`${p.billingEventsRetained} retained`);
            if (typeof p.effectiveDate === 'string') out.push(`effective ${p.effectiveDate}`);
            return out;
        } catch {
            return [];
        }
    }

    public Touch(): void { this.BufferDirty = true; this.Message = ''; }

    public ResetEdits(): void {
        const row = this.Current;
        if (row) { this.Buffer = this.bufferFor(row); this.BufferDirty = false; }
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
            if (ok) { this.BufferDirty = false; await this.load(); }
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
            if (row) this.Load(row);
            const done = this.Drafts.ActiveTab;
            if (done) this.Drafts.Close(done.Id);
            this.fallbackDraft = MJCContractsSectionComponent.blank();
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
            return;
        }

        await this.createLines(t.ID, md);
    }

    /**
     * The coverage rows. Reported individually rather than as one lump: if line 3 of 5 fails, the
     * person needs to know WHICH one, because the other four are already saved and re-entering all
     * five would duplicate them.
     */
    private async createLines(termID: string, md: Metadata): Promise<void> {
        const failures: string[] = [];
        let order = 1;

        for (const l of this.D.Lines) {
            if (!l.ProductID) continue; // a blank row the person added and left empty is not an error
            const line = await md.GetEntityObject<mjBizAppsContractsContractLineEntity>(E_LINES);
            line.NewRecord();
            line.ContractTermID = termID;
            line.ProductID = l.ProductID;
            line.LineType = (l.LineType || 'Subscription') as typeof line.LineType;
            line.Quantity = l.Quantity ?? 1;
            line.ContractedUnitPrice = l.ContractedUnitPrice;
            line.DiscountPct = this.pct(l.DiscountPercent);
            line.Description = l.Description || null;
            line.DisplayOrder = order;
            if (!(await line.Save())) {
                failures.push(`line ${order} (${l.Description || 'unnamed'}): ${line.LatestResult?.CompleteMessage ?? 'unknown error'}`);
            }
            order++;
        }

        if (failures.length) {
            this.Error = `Contract and term created, but coverage failed — ${failures.join('; ')}`;
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
        const [contracts, terms, events, types, companies, orgs, people, users, payterms, currencies, products, log] = await rv.RunViews([
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
            { EntityName: E_PRODUCTS, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_EVENTLOG, Fields: ['ID', 'ContractID', 'ContractTermID', 'EventType', 'EventDate', 'Payload', 'PerformedByUser'], OrderBy: 'EventDate DESC', ResultType: 'simple' },
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
        this.Products = products?.Success ? (products.Results as Lookup[]) : [];
        this.Log = log?.Success ? (log.Results as LogRow[]) : [];

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
