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

import { ChangeDetectorRef, Component, Input, OnInit, ViewChild, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClass } from '@memberjunction/global';
import { BaseResourceComponent, NavigationService } from '@memberjunction/ng-shared';
import { BaseFormsModule, MJFormPresenterService } from '@memberjunction/ng-base-forms';
import type { FormNavigationEvent } from '@memberjunction/ng-base-forms';
import {
    MJLeftNavComponent, MJLeftNavContentComponent, MJPageLayoutComponent, MJPageHeaderComponent,
    MJPageBodyComponent, MJPageBodyInteriorComponent, MJButtonDirective,
    type MJLeftNavSection, type MJLeftNavItem,
} from '@memberjunction/ng-ui-components';
// The IA as data, and the one surface that views, edits and creates a contract.
import { BuildLeftNavSections, DefaultPageFor, SubPagesFor } from '../nav/contracts-nav.model';
import { MJCContractWorkspaceComponent, type WorkspaceLookups } from '../workspace/contract-workspace.component';
import { ContractDraft, type ContractDraftPayload } from '@mj-biz-apps/contracts-entities';
// The family's shared workspace chrome. A THIN slotted frame owning only the invariant parts — the
// card surface, the open-documents strip, an identity band and one scrolling body — plus the
// standardised action bar, so no workshop hand-rolls its own footer. Contracts used it for the old
// create page; it went with that page and belongs back here.
import { WorkspaceCardComponent, WorkspaceTabStore } from '@mj-biz-apps/accounting-ng';
import { RunView, Metadata, CompositeKey, type RunViewParams } from '@memberjunction/core';
import type { ResourceData } from '@memberjunction/core-entities';
import { UserInfoEngine } from '@memberjunction/core-entities';
// The pure presentation helpers. They live in their own module because they are ordinary functions
// of their arguments — and having one implementation means a change to how a status reads happens
// once, not once here and once wherever else it was copied.
import {
    statusTone,
    eventTone,
    eventLabel,
    eventDetail,
    percentToFraction,
    termFill,
    coverageSubtotal,
} from '../contract-format';
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

const E_CONTRACTS = 'MJ_BizApps_Contracts: Contracts';
const E_TYPES = 'MJ_BizApps_Contracts: Contract Types';
const E_TERMS = 'MJ_BizApps_Contracts: Contract Terms';
const E_LINES = 'MJ_BizApps_Contracts: Contract Lines';
// Products belong to ORDERS. Contracts reads the catalog it commits to; it does not own one —
// FKs point upstream, and a second product list here would be a second thing to disagree with.
const E_PRODUCTS = 'MJ_BizApps_Orders: Products';
const E_SUBTYPES = 'MJ_BizApps_Orders: Subscription Types';
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
    AutoRenew: boolean; CancellationWindowDays: number | null; RenewalNoticeDays: number | null;
    ExternalReferenceID: string | null;
}
/* The cross-contract worklist rows. Deliberately flat and read-only: these views exist to FIND a
   contract, and every one of them opens the real workspace on click. */
interface ScheduleRow { ID: string; ContractTermID: string; ScheduleType: string; Frequency: string | null; AnchorDate: string | null; IsActive: boolean }
interface CommitmentRow { ID: string; ContractTermID: string; CommitmentType: string; CommittedAmount: number; ConsumedAmount: number; PeriodStart: string | null; PeriodEnd: string | null; TrueUpPolicy: string; Status: string }
interface AmendmentRow { ID: string; ContractTermID: string; AmendmentNumber: number; EffectiveDate: string; AmendmentType: string; Description: string | null; Status: string }

interface TermRow {
    ID: string; ContractID: string; TermNumber: number; Status: string;
    StartDate: string | null; EndDate: string | null; CommittedAmount: number | null;
    EscalationPercent: number | null; BillingFrequency: string | null;
}
interface EventRow {
    ID: string; ContractTermID: string; ScheduledDate: string | null; Status: string;
    ComputedAmount: number | null; FailureReason: string | null;
}
interface Lookup { ID: string; Name: string }
/** A contract type, plus the escalation ceiling every term of that type is judged against. */
interface TypeRow extends Lookup { DefaultMaxEscalationPercent: number | null }

/** One entry in a contract's audit trail. The vocabulary is closed and the rows cannot be edited. */
interface LogRow {
    ID: string; ContractID: string; ContractTermID: string | null;
    EventType: string; EventDate: Date; Payload: string | null; PerformedByUser: string | null;
}




// NOT registered as a resource itself — it is the shared IMPLEMENTATION the three registered
// classes at the bottom of this file mount, each pinning its own section. Registering it here as
// well would mean two classes claiming 'ContractsSectionResource', and the class factory returns
// one of them.
@Component({
    selector: 'mjc-contracts-section',
    standalone: true,
    imports: [
        CommonModule, FormsModule, BaseFormsModule, MJButtonDirective,
        MJPageLayoutComponent, MJPageHeaderComponent, MJPageBodyComponent, MJPageBodyInteriorComponent,
        MJLeftNavComponent, MJLeftNavContentComponent,
        MJCContractWorkspaceComponent, WorkspaceCardComponent,
    ],
    styles: [
        `
        .wrap { padding: var(--mj-space-5, 20px) var(--mj-space-6, 24px) var(--mj-space-10, 40px); }

        /* THE WORKSPACE PAGE FILLS THE PANE; EVERY OTHER PAGE IS ORDINARY DOCUMENT FLOW.
           A list or a dashboard is a column of cards that should size to their content and let the
           interior scroll. The workspace is the opposite: it is one card that should reach the
           bottom of the window, because it holds a tab strip and a pane that scrolls INSIDE it.

           This used to happen by accident. mj-left-nav-content forces its direct children to
           display:flex + height:100%, so while the page divs sat directly inside it the card
           inherited a height for free — and every other page inherited clipping it did not want.
           Now the interior owns the scrolling and this ONE page opts into filling, which is the
           right way round: the exception is declared, not imposed on everything.

           min-height rather than height so the card can still grow past the fold (a contract with
           many terms) and let the interior scroll, instead of being trapped at exactly one screen. */
        .wrap.fill { min-height: 100%; display: flex; flex-direction: column; }
        .wrap.fill > mj-workspace-card { flex: 1 1 auto; min-height: 0; }
        /* The cross-contract worklists. App-authored rather than a raw entity grid, because the
           point of these screens is to resolve a foreign key into something a person recognises —
           and every row opens the real workspace. */
        .wl { width: 100%; border-collapse: collapse; }
        .wl th { text-align: left; font-size: 11.5px; font-weight: 600; text-transform: uppercase;
                 letter-spacing: 0.03em; color: var(--mj-text-secondary); padding: 8px 12px;
                 border-bottom: 1px solid var(--mj-border-default); white-space: nowrap; }
        .wl td { padding: 10px 12px; font-size: 13px; color: var(--mj-text-primary);
                 border-bottom: 1px solid var(--mj-border-subtle, var(--mj-border-default)); }
        .wl tbody tr { cursor: pointer; }
        .wl tbody tr:hover { background: color-mix(in srgb, var(--mj-brand-primary) 6%, transparent); }
        .wl .where { font-weight: 600; white-space: nowrap; }
        .wl .muted { color: var(--mj-text-secondary); }
        .wl .num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
        .wl-empty { padding: 28px; text-align: center; color: var(--mj-text-secondary); font-size: 13px; }
        .bar { position: relative; height: 6px; border-radius: 3px; background: var(--mj-border-default); min-width: 90px; }
        .bar > span { position: absolute; inset: 0 auto 0 0; border-radius: 3px; background: var(--mj-brand-primary); }
        .bar.over > span { background: var(--mj-color-danger, #d33); }
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
        .tl-fill { display: flex; align-items: center; padding: 0 9px; font-size: 12px; font-weight: 600; color: var(--mj-text-inverse, #fff); }
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
                <!-- NO SECTION SWITCHER HERE. An earlier version drew one with mj-tab-nav inside this
                     header, which LOOKED like a top nav bar and was not one: MJ's top nav comes from
                     the Application's DefaultNavItems, each pointing at a registered resource class.
                     The three real nav items are registered at the bottom of this file.

                     THE SHAPE IS ORDERS': an icon-only OUTLINE refresh, then a PRIMARY action whose
                     label changes with the page — because "New contract" on the Commitments page is
                     an answer to a question nobody asked. Orders varies its primary per SECTION;
                     nine pages across three sections need it per PAGE. -->
                <button
                    type="button"
                    mjButton variant="outline"
                    (click)="Refresh()"
                    aria-label="Refresh this page">
                    <i class="fa-solid fa-arrow-rotate-right" aria-hidden="true"></i>
                </button>
                <button
                    type="button"
                    *ngIf="PrimaryAction as action"
                    mjButton variant="primary"
                    (click)="StartPrimary()">
                    <i [class]="action.Icon" aria-hidden="true"></i> {{ action.Label }}
                </button>
            </div>
        </mj-page-header>

        <mj-page-body [Flex]="true" [Padding]="false" Direction="row">
            <mj-left-nav [Sections]="NavSections" [ActiveId]="Page" MobileTitle="Contracts" (ItemClicked)="OnNav($event)"></mj-left-nav>

            <mj-left-nav-content>
            <!-- THE SCROLLER, AND WHY IT IS NOT OPTIONAL.
                 mj-left-nav-content forces EVERY direct child to
                 display:flex + flex-direction:column + height:100% + overflow:hidden through an
                 ::ng-deep rule, so page content dropped straight into it stops being block flow and
                 becomes a fixed-height flex column that CLIPS instead of scrolling — and its layout
                 becomes a function of the window height, which is how a tall card ends up somewhere
                 nobody put it.

                 mj-page-body-interior is the sanctioned container and is named in that rule's
                 :not() list precisely so it keeps its own behaviour: display:block, flex:1 1 auto,
                 overflow-y:auto. It fills to the bottom of the pane and scrolls what does not fit,
                 so the layout no longer depends on the viewport at all. ONE of them wraps all nine
                 pages, so every page in all three sections flows and scrolls identically. This is
                 MJ's own chrome pattern (left-nav-content, then page-body-interior, then content) —
                 see testing-explorer.component.ts.

                 Padding off: .wrap already declares the page gutter. -->
            <mj-page-body-interior [Padding]="false">

            <!-- ============ 1. CONTRACTS ============ -->
            <div class="wrap" *ngIf="Page === 'list'">
                <div class="sechead">
                    <h2>All contracts</h2>
                </div>

                <div class="kpis">
                    <div class="kpi"><div class="l">Active contracted value</div><div class="v">{{ TotalCommitted | currency: 'USD' : 'symbol' : '1.0-0' }}</div><div class="f">across {{ ActiveCount }} active contracts</div></div>
                    <div class="kpi"><div class="l">Renewing next 90 days</div><div class="v">{{ RenewingCount }}</div><div class="f">terms reaching their end date</div></div>
                    <div class="kpi"><div class="l">Billing scheduled</div><div class="v warn">{{ Counts.Scheduled }}</div><div class="f">events awaiting generation</div></div>
                    <div class="kpi"><div class="l">Failed billing</div><div class="v err">{{ Counts.Failed }}</div><div class="f">never auto-retried</div></div>
                </div>

                <div class="card">
                    <div class="ch">Contracts <span class="r">{{ Contracts.length }} total</span></div>
                    <div class="wl-empty" *ngIf="!Contracts.length">No contracts yet.</div>
                    <table class="wl" *ngIf="Contracts.length">
                        <thead><tr>
                            <th>Contract</th><th>Description</th><th>Status</th><th class="num">Terms</th>
                            <th class="num">Committed</th><th>Effective</th>
                        </tr></thead>
                        <tbody>
                            <tr *ngFor="let c of Contracts" (click)="OpenContract(c)" [title]="'Open ' + c.ContractNumber + ' in the workspace'">
                                <td class="where">{{ c.ContractNumber }}</td>
                                <td class="muted">{{ c.Description || '—' }}</td>
                                <td><span class="pill" [class]="Tone(c.Status)">{{ c.Status }}</span></td>
                                <td class="num">{{ TermsOf(c.ID).length }}</td>
                                <td class="num">{{ CommittedOf(c.ID) | currency: 'USD' : 'symbol' : '1.0-0' }}</td>
                                <td class="muted">{{ c.EffectiveDate ? (c.EffectiveDate | date: 'mediumDate') : '—' }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- ============ 2. WORKSPACE (editing) ============ -->
            <!-- ============ 2. WORKSPACE — viewing, editing AND creating, one surface ============
                 Consolidated 2026-08-05. A contract is never finished being created: a draft gains a
                 term next week, coverage after review, a schedule when the cadence is agreed. Two
                 surfaces forced somebody to decide when the thing stopped being created, and every
                 entity appearing after that became an argument about which surface owned it.

                 The OUTER strip is open documents — several contracts side by side, a new one being
                 simply a card with no id. The INNER tabs are panes of one contract, each carrying one
                 of three states so the strip teaches the sequence as well as showing it. -->
            <div class="wrap fill" *ngIf="Page === 'workspace'">
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
                    <!-- NO "New contract" HERE. The page header carries the primary action for every
                         page in the app, and this one duplicated it a few hundred pixels away — two
                         buttons, same label, same effect, and the reader has to work out whether they
                         differ. One creation control per page, and it lives in the same place on all
                         nine of them. -->
                </div>

                <!-- SEARCH IS THE ACCESS POINT. There is deliberately no standing roster here.
                     A full list of every contract is what "All contracts" is for, and repeating it
                     inside the workspace made the workspace a second, worse browser: the same rows,
                     capped at 25, with no columns to sort or scan by. Two lists of the same thing
                     drift, and the reader has to learn which one is authoritative.

                     So: type to find, click to open. Results appear only when there IS a search, and
                     they appear whether or not something is already open — finding a second
                     agreement while reading the first is the normal case, and a hit opens in its own
                     document tab beside it. -->
                <div class="card" *ngIf="Query || StatusFilter">
                    <div class="ch">
                        {{ Drafts.Count ? 'Open another contract' : 'Open a contract' }}
                        <span class="r">{{ Matches.length }} of {{ Contracts.length }}</span>
                    </div>
                    <div class="note info" *ngIf="!Matches.length">
                        No contract matches that search. Clear it, or start a new contract.
                    </div>
                    <div class="picks">
                        <button class="pick" *ngFor="let c of Matches" (click)="OpenContract(c)">
                            <span class="pn">{{ c.ContractNumber }}</span>
                            <span class="pd">{{ c.Description || '—' }}</span>
                        </button>
                    </div>
                </div>

                <!-- THE EMPTY STATE. A search box on a blank page is a dead end for anyone who does
                     not already know what to type, so the nothing-open-nothing-typed state offers the
                     handful of contracts this person actually touched. Recents, not a roster: short,
                     personal, and it does not pretend to be the browse surface. -->
                <div class="card" *ngIf="!Drafts.Count && !Query && !StatusFilter">
                    <div class="ch">Recently opened <span class="r">{{ Recents.length }}</span></div>
                    <div class="note info" *ngIf="!Recents.length">
                        Search above to open a contract — by number, description or external reference.
                        Or start a new one from the button in the header.
                    </div>
                    <div class="picks" *ngIf="Recents.length">
                        <button class="pick" *ngFor="let c of Recents" (click)="OpenContract(c)">
                            <span class="pn">{{ c.ContractNumber }}</span>
                            <span class="pd">{{ c.Description || '—' }}</span>
                        </button>
                    </div>
                </div>

                <!-- A FAILED OPEN HAS TO SAY SO. It used to set this.Error and return, and nothing in
                     the template rendered this.Error — so clicking a contract that could not be
                     loaded did NOTHING AT ALL, which is indistinguishable from a dead control. The
                     commonest cause is a stale list (the row was deleted by someone else since this
                     page loaded), so the message says that and the list refreshes itself. -->
                <div class="note err" *ngIf="OpenError">
                    <div>{{ OpenError }}</div>
                </div>

                <!-- THE STANDARD WORKSPACE CARD. Several agreements stay open at once, which is how
                     they are actually read — a renewal beside its predecessor — and the strip that
                     models open documents already exists in the family. An earlier version drew its
                     own row of buttons here: it worked, and looked like nothing else in the suite.

                     ShowDraft is off. The card's "keep as draft" means keep the TAB without writing,
                     and a contract's Draft is a real persisted STATUS. Two meanings of one word on
                     one screen is how a person mis-clicks. -->
                <mj-workspace-card *ngIf="Drafts.Count"
                    AriaLabel="Contract workspace"
                    NewTabLabel="New contract"
                    [Tabs]="Drafts.Tabs"
                    [ActiveId]="Drafts.ActiveId"
                    [ShowFooter]="true"
                    [ShowDraft]="false"
                    [ConfirmLabel]="ConfirmLabel"
                    ConfirmIcon="fa-solid fa-floppy-disk"
                    [ConfirmDisabled]="!CanSaveActive"
                    [ConfirmTitle]="ConfirmTitle"
                    [ConfirmBusy]="IsSaving"
                    ConfirmBusyLabel="Saving…"
                    DiscardLabel="Close"
                    (TabSelected)="ActivateDoc($event)"
                    (TabClosed)="CloseDoc($event)"
                    (NewTabRequested)="NewContract()"
                    (Confirm)="SaveActive()"
                    (Discard)="CloseActive()">

                    <div workspaceHeader class="ws-id">
                        <span class="ws-num">{{ ActiveDraft?.ContractNumber || 'New contract' }}</span>
                        <span class="ws-sub">
                            {{ ActiveDraft?.IsSaved ? 'Saved' : 'Not yet saved' }}
                            <ng-container *ngIf="ActiveDraft?.Description"> · {{ ActiveDraft?.Description }}</ng-container>
                        </span>
                    </div>

                    <mjc-contract-workspace *ngIf="ActiveDraft as draft"
                        [Draft]="draft"
                        [Lookups]="WorkspaceLookups"
                        (Saved)="OnContractSaved($event)"
                        (ReloadRequested)="OnReloadRequested($event)">
                    </mjc-contract-workspace>

                    <span workspaceFooterNote>
                        <ng-container *ngIf="WorkspaceMessage">{{ WorkspaceMessage }}</ng-container>
                        <button mjButton variant="flat" *ngIf="!WorkspaceMessage && CanTerminateActive" (click)="TerminateActive()">
                            <i class="fa-solid fa-ban"></i> Terminate…
                        </button>
                    </span>
                </mj-workspace-card>
            </div>


            <div class="wrap" *ngIf="Page === 'worklist'">
                <div class="sechead">
                    <h2>Billing worklist</h2>
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
                    <div class="ch">All billing events <span class="r">{{ Events.length }}</span></div>
                    <div class="wl-empty" *ngIf="!Events.length">No billing events yet — activating a term creates them.</div>
                    <table class="wl" *ngIf="Events.length">
                        <thead><tr><th>Contract</th><th>Scheduled</th><th>Status</th><th class="num">Amount</th><th>Reason</th></tr></thead>
                        <tbody>
                            <tr *ngFor="let e of Events" (click)="OpenByChild(e.ContractTermID)"
                                [title]="'Open ' + WhereOf(e.ContractTermID) + ' in the workspace'">
                                <td class="where">{{ WhereOf(e.ContractTermID) }}</td>
                                <td>{{ e.ScheduledDate | date: 'mediumDate' }}</td>
                                <td><span class="pill" [class]="Tone(e.Status)">{{ e.Status }}</span></td>
                                <td class="num">{{ e.ComputedAmount != null ? (e.ComputedAmount | currency: 'USD') : '—' }}</td>
                                <td class="muted">{{ e.FailureReason || '—' }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- ============ SETUP ============ -->
            <div class="wrap" *ngIf="Page === 'types'">
                <div class="sechead">
                    <h2>Contract types</h2>
                </div>
                <div class="card">
                    <mj-explorer-entity-data-grid [Params]="P.types" [Height]="440" [ShowToolbar]="true" [ToolbarConfig]="Toolbar" (Navigate)="OnNavigate($event)"></mj-explorer-entity-data-grid>
                </div>
            </div>


            <!-- ============ DASHBOARD — is anything about to lapse? ============ -->
            <div class="wrap" *ngIf="Page === 'dashboard'">
                <div class="sechead">
                    <h2>Dashboard</h2>
                </div>
                <div class="kpis">
                    <div class="kpi"><div class="l">Active contracted value</div><div class="v">{{ TotalCommitted | currency: 'USD' : 'symbol' : '1.0-0' }}</div><div class="f">across {{ ActiveCount }} active contracts</div></div>
                    <div class="kpi"><div class="l">Renewing next 90 days</div><div class="v">{{ RenewingCount }}</div><div class="f">terms reaching their end date</div></div>
                    <div class="kpi"><div class="l">Billing scheduled</div><div class="v warn">{{ Counts.Scheduled }}</div><div class="f">events awaiting generation</div></div>
                    <div class="kpi"><div class="l">Failed billing</div><div class="v err">{{ Counts.Failed }}</div><div class="f">never auto-retried — a person decides</div></div>
                </div>
                <div class="card">
                    <div class="ch">Terms reaching their end date <span class="r">{{ Renewing.length }}</span></div>
                    <div class="empty" *ngIf="!Renewing.length" style="padding:24px; text-align:center; color:var(--mj-text-secondary);">
                        Nothing lapses in the next 90 days.
                    </div>
                    <div class="picks" *ngIf="Renewing.length">
                        <button class="pick" *ngFor="let t of Renewing" (click)="OpenByTerm(t)">
                            <span class="pn">{{ ContractNumberOf(t.ContractID) }} · term {{ t.TermNumber }}</span>
                            <span class="pd">ends {{ t.EndDate | date: 'mediumDate' }} · {{ t.Status }}</span>
                        </button>
                    </div>
                </div>
            </div>

            <!-- ============ RENEWALS DUE ============ -->
            <div class="wrap" *ngIf="Page === 'renewals'">
                <div class="sechead">
                    <h2>Renewals due</h2>
                </div>
                <div class="card">
                    <div class="ch">Coming up <span class="r">{{ Renewing.length }}</span></div>
                    <div class="empty" *ngIf="!Renewing.length" style="padding:24px; text-align:center; color:var(--mj-text-secondary);">
                        Nothing to renew in the next 90 days.
                    </div>
                    <div class="picks" *ngIf="Renewing.length">
                        <button class="pick" *ngFor="let t of Renewing" (click)="OpenByTerm(t)">
                            <span class="pn">{{ ContractNumberOf(t.ContractID) }} · term {{ t.TermNumber }}</span>
                            <span class="pd">ends {{ t.EndDate | date: 'mediumDate' }} · open it to preview the renewal</span>
                        </button>
                    </div>
                </div>
            </div>

            <!-- ============ AMENDMENTS (cross-contract) ============ -->
            <div class="wrap" *ngIf="Page === 'amendments'">
                <div class="sechead">
                    <h2>Amendments</h2>
                </div>
                <div class="card">
                    <div class="ch">Amendments <span class="r">{{ Amendments.length }}</span></div>
                    <div class="wl-empty" *ngIf="!Amendments.length">No amendments raised. Add a product mid-term from a running term to create one.</div>
                    <table class="wl" *ngIf="Amendments.length">
                        <thead><tr><th>Contract</th><th>#</th><th>Effective</th><th>Type</th><th>Description</th><th>Status</th></tr></thead>
                        <tbody>
                            <tr *ngFor="let am of Amendments" (click)="OpenByChild(am.ContractTermID)"
                                [title]="'Open ' + WhereOf(am.ContractTermID) + ' in the workspace'">
                                <td class="where">{{ WhereOf(am.ContractTermID) }}</td>
                                <td class="num">{{ am.AmendmentNumber }}</td>
                                <td>{{ am.EffectiveDate | date: 'mediumDate' }}</td>
                                <td>{{ am.AmendmentType }}</td>
                                <td class="muted">{{ am.Description || '—' }}</td>
                                <td><span class="pill" [class]="Tone(am.Status)">{{ am.Status }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- ============ BILLING · SCHEDULES (cross-contract) ============ -->
            <div class="wrap" *ngIf="Page === 'schedules'">
                <div class="sechead">
                    <h2>Billing schedules</h2>
                </div>
                <div class="card">
                    <div class="ch">Billing schedules <span class="r">{{ Schedules.length }}</span></div>
                    <div class="wl-empty" *ngIf="!Schedules.length">No schedules yet — activating a term creates one from its cadence.</div>
                    <table class="wl" *ngIf="Schedules.length">
                        <thead><tr><th>Contract</th><th>Type</th><th>Frequency</th><th>Anchor</th><th>Active</th></tr></thead>
                        <tbody>
                            <tr *ngFor="let sc of Schedules" (click)="OpenByChild(sc.ContractTermID)"
                                [title]="'Open ' + WhereOf(sc.ContractTermID) + ' in the workspace'">
                                <td class="where">{{ WhereOf(sc.ContractTermID) }}</td>
                                <td>{{ sc.ScheduleType }}</td>
                                <td class="muted">{{ sc.Frequency || '—' }}</td>
                                <td class="muted">{{ sc.AnchorDate ? (sc.AnchorDate | date: 'mediumDate') : '—' }}</td>
                                <td class="muted">{{ sc.IsActive ? 'Yes' : 'No' }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- ============ BILLING · COMMITMENTS (cross-contract) ============ -->
            <div class="wrap" *ngIf="Page === 'commitments'">
                <div class="sechead">
                    <h2>Commitments</h2>
                </div>
                <div class="card">
                    <div class="ch">Commitments <span class="r">{{ Commitments.length }}</span></div>
                    <div class="wl-empty" *ngIf="!Commitments.length">No commitments recorded.</div>
                    <table class="wl" *ngIf="Commitments.length">
                        <thead><tr><th>Contract</th><th>Type</th><th class="num">Committed</th><th class="num">Consumed</th><th>Used</th><th>True-up</th><th>Status</th></tr></thead>
                        <tbody>
                            <tr *ngFor="let cm of Commitments" (click)="OpenByChild(cm.ContractTermID)"
                                [title]="'Open ' + WhereOf(cm.ContractTermID) + ' in the workspace'">
                                <td class="where">{{ WhereOf(cm.ContractTermID) }}</td>
                                <td>{{ cm.CommitmentType }}</td>
                                <td class="num">{{ cm.CommittedAmount | currency: 'USD' : 'symbol' : '1.0-0' }}</td>
                                <td class="num">{{ cm.ConsumedAmount | currency: 'USD' : 'symbol' : '1.0-0' }}</td>
                                <td><span class="bar" [class.over]="cm.ConsumedAmount > cm.CommittedAmount"><span [style.width.%]="ConsumedPct(cm)"></span></span></td>
                                <td class="muted">{{ cm.TrueUpPolicy }}</td>
                                <td><span class="pill" [class]="Tone(cm.Status)">{{ cm.Status }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            </mj-page-body-interior>
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

    /**
     * Which top-level section this instance IS.
     *
     * An @Input rather than internal state because each section is a SEPARATE MJ nav item backed by
     * its own registered resource class (see the three classes at the bottom of this file). Explorer
     * mounts one of them per tab; the tab bar is MJ's, not ours to draw.
     */
    private _section = 'contracts';
    @Input()
    public set Section(value: string) {
        this._section = value;
        this.Page = DefaultPageFor(value);
    }
    public get Section(): string {
        return this._section;
    }

    public Page = 'contracts';

    /**
     * The open contracts, each with its own draft — the OUTER tabbing system.
     *
     * `WorkspaceTabStore` rather than an array of our own: it is the same session-scoped store the
     * rest of the family's workspaces use, and it already handles activation, closing, reordering
     * and dirty-tracking. Its `State` is deliberately opaque to the framework, so the draft stays
     * ours while the tab mechanics stay shared.
     *
     * A contract being CREATED is simply a tab whose draft has no id. There is no separate create
     * surface, which is the whole point of the consolidation.
     */
    public readonly Drafts = new WorkspaceTabStore<ContractDraft>();
    private docSeed = 0;

    /** The workspace pane, so the card's footer can drive the verbs the pane owns. */
    @ViewChild(MJCContractWorkspaceComponent) public Workspace?: MJCContractWorkspaceComponent;
    public Tab = 'overview';
    public Mode: 'fast' | 'detail' = 'fast';
    public Saving = false;
    public Message = '';
    public Error = '';

    /**
     * Why the last attempt to open a contract failed, shown on the workspace page.
     *
     * Separate from `Error`, which nothing renders and which would blank the whole pane if it did.
     * A row that will not open is a local problem with one row, not a broken page.
     */
    public OpenError = '';

    /**
     * The contracts this person opened most recently, newest first.
     *
     * PERSISTED THROUGH UserInfoEngine, NOT localStorage — per-user and server-side, so the list
     * follows them to another machine. localStorage would tie it to one browser profile and quietly
     * lose it on a cache clear.
     *
     * Stored as IDs and resolved against the loaded roster on read, so a renamed or renumbered
     * contract shows its current identity and a DELETED one simply drops out instead of offering a
     * row that cannot open.
     */
    private recentIDs: string[] = [];
    private static readonly RECENTS_KEY = 'mj.contracts.recentContracts.v1';
    private static readonly RECENTS_MAX = 8;

    public get Recents(): ContractRow[] {
        return this.recentIDs
            .map((id) => this.Contracts.find((c) => c.ID === id))
            .filter((c): c is ContractRow => !!c)
            .slice(0, MJCContractsSectionComponent.RECENTS_MAX);
    }

    private loadRecents(): void {
        const raw = UserInfoEngine.Instance.GetSetting(MJCContractsSectionComponent.RECENTS_KEY);
        if (!raw) return;
        try {
            const parsed: unknown = JSON.parse(raw);
            // A stored setting is data from outside this code path, so it is validated rather than
            // trusted: a malformed value must degrade to "no recents", never throw on page load.
            this.recentIDs = Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === 'string') : [];
        } catch {
            this.recentIDs = [];
        }
    }

    private rememberRecent(contractID: string): void {
        this.recentIDs = [contractID, ...this.recentIDs.filter((id) => id !== contractID)]
            .slice(0, MJCContractsSectionComponent.RECENTS_MAX);
        // Debounced and fire-and-forget: opening a contract must not wait on a preference write.
        UserInfoEngine.Instance.SetSettingDebounced(
            MJCContractsSectionComponent.RECENTS_KEY,
            JSON.stringify(this.recentIDs),
        );
    }

    public Contracts: ContractRow[] = [];
    public Schedules: ScheduleRow[] = [];
    public Commitments: CommitmentRow[] = [];
    public Amendments: AmendmentRow[] = [];
    public Terms: TermRow[] = [];
    public Events: EventRow[] = [];
    public Log: LogRow[] = [];
    public Types: TypeRow[] = [];
    public Companies: Lookup[] = [];
    public Orgs: Lookup[] = [];
    public People: Lookup[] = [];
    public Users: Lookup[] = [];
    public PayTerms: Lookup[] = [];
    public Currencies: Lookup[] = [];
    public Products: Lookup[] = [];
    public SubscriptionTypes: Lookup[] = [];
    /** Mirrors CK_ContractLine_LineType exactly — the CHECK is the source of truth for this list. */
    public readonly LineTypes = ['Subscription', 'OneTime', 'Milestone', 'Usage', 'Minimum'];
    public readonly Frequencies = ['Monthly', 'Quarterly', 'SemiAnnual', 'Annual', 'Milestone', 'Custom'];
    /** Open drafts on the create page — accounting's card owns the strip; this owns the state. */
    public Query = '';
    public StatusFilter = '';
    public Counts = { Scheduled: 0, Generated: 0, Failed: 0, Skipped: 0 };

    public CurrentID: string | null = null;

    public readonly StatusOptions = ['Draft', 'PendingSignature', 'Active', 'Expired', 'Terminated', 'Superseded'];

    /**
     * The legal next states from a given one — the same map `ContractEntityServer` enforces.
     *
     * Offering all six and letting the save be refused is a worse design than offering the three that
     * will work, even now that the refusal explains itself: the best error message is the one nobody
     * has to read. The duplication with the server is deliberate and small; the server remains the
     * authority, and this list existing does not make it optional.
     */
    private readonly LEGAL_STATUS_MOVES: Readonly<Record<string, readonly string[]>> = {
        Draft: ['Draft', 'PendingSignature', 'Active', 'Terminated'],
        PendingSignature: ['PendingSignature', 'Draft', 'Active', 'Terminated'],
        Active: ['Active', 'Expired', 'Terminated', 'Superseded'],
        Expired: ['Expired', 'Superseded', 'Terminated'],
        Terminated: ['Terminated'],
        Superseded: ['Superseded'],
    };

    public LegalStatusesFrom(current: string | null): readonly string[] {
        if (!current) return this.StatusOptions;
        return this.LEGAL_STATUS_MOVES[current] ?? [current];
    }

    public IsTerminalStatus(current: string | null): boolean {
        return !!current && this.LegalStatusesFrom(current).length === 1;
    }
    public readonly Toolbar = { showSearch: true, searchPlaceholder: 'Search…', showAdd: true, showRefresh: true, showExport: true };

    /** Every grid's params in one map, so scoping a page is a single reassignment. */
    public P: Record<string, RunViewParams> = {
        contracts: { EntityName: E_CONTRACTS, OrderBy: 'ContractNumber' },
        types: { EntityName: E_TYPES, OrderBy: 'Name' },
        allEvents: { EntityName: E_EVENTS, OrderBy: 'ScheduledDate' },
        // CROSS-CONTRACT views. "What will bill next month" and "who is behind on what they
        // committed to" are not answered by opening one agreement at a time, which is why Billing is
        // its own section rather than a pane inside the workspace.
        allSchedules: { EntityName: E_SCHEDULES, OrderBy: '__mj_CreatedAt DESC' },
        allCommitments: { EntityName: E_COMMITMENTS, OrderBy: '__mj_CreatedAt DESC' },
        allAmendments: { EntityName: E_AMENDMENTS, OrderBy: 'EffectiveDate DESC' },
        terms: { EntityName: E_TERMS },
        lines: { EntityName: E_LINES },
        schedules: { EntityName: E_SCHEDULES },
        events: { EntityName: E_EVENTS },
        commitments: { EntityName: E_COMMITMENTS },
        amendments: { EntityName: E_AMENDMENTS },
        eventlog: { EntityName: E_EVENTLOG },
    };

    private termsBy = new Map<string, TermRow[]>();


    public async ngOnInit(): Promise<void> {
        // Recents come from a synchronous cache the user bootstrap already populated, so this costs
        // nothing and does not need to be awaited alongside the roster.
        this.loadRecents();
        await this.load();
    }

    public override async GetResourceDisplayName(_d: ResourceData): Promise<string> { return 'Contracts'; }
    public override async GetResourceIconClass(_d: ResourceData): Promise<string> { return 'fa-solid fa-file-signature'; }

    /**
     * The primary action for the page currently showing.
     *
     * EVERY PAGE HAS ONE, and the two worklists were the interesting cases.
     *
     * Billing worklist gets **New schedule**, NOT "New billing event". Events are created by the
     * engine when a term activates; a button offering to hand-write one invites a bill the schedule
     * never asked for, and duplicate billing is the kind of defect a customer finds before we do.
     * The schedule is the thing a person legitimately creates to make events exist, so that is the
     * creation verb for a page about events. ("Run due billing" would be the page's true *action*
     * rather than a creation, and it is deliberately not here: it produces real orders, and the
     * orders bridge is still the unavailable default, so the button would fail every time.)
     *
     * Renewals due gets **New contract** — the create verb of the section it belongs to, matching
     * Dashboard, All contracts and Workspace. Renewing is per-row and stays on the rows, because a
     * renewal needs the term it continues; a global "New term" would have nothing to attach to.
     *
     * The three that need a parent term (schedule, commitment, amendment) open MJ's own new-record
     * form rather than a bespoke dialog: the form carries the term picker and the generated
     * validation, and the entity rules refuse an amendment against a term that is not running
     * whichever way the record is created.
     */
    public get PrimaryAction(): { Label: string; Icon: string; Kind: string } | null {
        switch (this.Page) {
            case 'dashboard':
            case 'list':
            case 'workspace':
                return { Label: 'New contract', Icon: 'fa-solid fa-plus', Kind: 'contract' };
            case 'amendments':
                return { Label: 'New amendment', Icon: 'fa-solid fa-file-pen', Kind: 'amendment' };
            case 'schedules':
                return { Label: 'New schedule', Icon: 'fa-solid fa-calendar-plus', Kind: 'schedule' };
            case 'commitments':
                return { Label: 'New commitment', Icon: 'fa-solid fa-plus', Kind: 'commitment' };
            case 'types':
                return { Label: 'New contract type', Icon: 'fa-solid fa-plus', Kind: 'type' };
            case 'worklist':
                // A schedule, not an event — see the note above.
                return { Label: 'New schedule', Icon: 'fa-solid fa-calendar-plus', Kind: 'schedule' };
            case 'renewals':
                return { Label: 'New contract', Icon: 'fa-solid fa-plus', Kind: 'contract' };
            default:
                return null;
        }
    }

    public StartPrimary(): void {
        const action = this.PrimaryAction;
        if (!action) return;
        switch (action.Kind) {
            case 'contract':
                this.NewContract();
                return;
            case 'amendment':
                this.nav.OpenNewEntityRecord(E_AMENDMENTS);
                return;
            case 'schedule':
                this.nav.OpenNewEntityRecord(E_SCHEDULES);
                return;
            case 'commitment':
                this.nav.OpenNewEntityRecord(E_COMMITMENTS);
                return;
            case 'type':
                this.nav.OpenNewEntityRecord(E_TYPES);
                return;
        }
    }

    /** The rail for this section — declared once, in the nav model. */
    public get NavSections(): MJLeftNavSection[] {
        return BuildLeftNavSections(SubPagesFor(this.Section), {
            BillingFailed: this.Counts.Failed || undefined,
            RenewalsDue: this.RenewingCount || undefined,
        });
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

    public get Failed(): EventRow[] { return this.Events.filter((e) => e.Status === 'Failed'); }
    public get ActiveCount(): number { return this.Contracts.filter((c) => c.Status === 'Active').length; }
    public get TotalCommitted(): number { return this.Terms.filter((t) => t.Status === 'Active').reduce((s, t) => s + (t.CommittedAmount ?? 0), 0); }
    /** Terms whose end date falls inside the next 90 days — what Dashboard and Renewals both list. */
    public get Renewing(): TermRow[] {
        const now = Date.now(), horizon = now + 90 * 864e5;
        return this.Terms
            .filter((t) => t.EndDate && new Date(t.EndDate).getTime() >= now && new Date(t.EndDate).getTime() <= horizon)
            .sort((a, b) => new Date(a.EndDate!).getTime() - new Date(b.EndDate!).getTime());
    }

    /* ── Resolving a foreign key to something a person recognises ──────────────────────────────
     *
     * Every cross-contract worklist used to be a raw entity grid, which renders
     * `66666666-0000-4000-…` for `ContractBillingScheduleID` and expects the reader to know what
     * that is. A UUID on screen is a failure to answer the question the screen exists to answer.
     *
     * MJ's grid ignores `RunViewParams.Fields`, so narrowing the query was never the fix; and the
     * denormalised name a view would carry does not exist for a TERM, which has no name — only a
     * number, and only in the context of its contract. So these worklists resolve through the
     * contracts and terms already in memory, and render "CTR-001842 · term 3".
     * ────────────────────────────────────────────────────────────────────────────────────────── */

    /** The term behind any child row. */
    public TermOf(termID: string): TermRow | null {
        return this.Terms.find((t) => t.ID === termID) ?? null;
    }

    /** "CTR-001842 · term 3" — what a person calls this row out loud. */
    public WhereOf(termID: string): string {
        const term = this.TermOf(termID);
        if (!term) return '—';
        return `${this.ContractNumberOf(term.ContractID)} · term ${term.TermNumber}`;
    }

    /** Open the contract a CHILD row belongs to, as a workspace tab. */
    public async OpenByChild(termID: string): Promise<void> {
        const term = this.TermOf(termID);
        if (!term) return;
        const row = this.Contracts.find((c) => c.ID === term.ContractID);
        if (row) await this.OpenContract(row);
    }

    /** How much of a commitment is used, for the consumed-versus-committed bar. */
    public ConsumedPct(c: CommitmentRow): number {
        if (!c.CommittedAmount) return 0;
        return Math.min(100, Math.round((c.ConsumedAmount / c.CommittedAmount) * 100));
    }

    public ContractNumberOf(contractID: string): string {
        return this.Contracts.find((c) => c.ID === contractID)?.ContractNumber ?? '—';
    }

    /** Open the contract a term belongs to, from a worklist row. */
    public async OpenByTerm(term: TermRow): Promise<void> {
        const row = this.Contracts.find((c) => c.ID === term.ContractID);
        if (row) await this.OpenContract(row);
    }

    public get RenewingCount(): number {
        const now = Date.now(), horizon = now + 90 * 864e5;
        return this.Terms.filter((t) => t.EndDate && new Date(t.EndDate).getTime() >= now && new Date(t.EndDate).getTime() <= horizon).length;
    }

    public TermsOf(id: string): TermRow[] { return this.termsBy.get(id) ?? []; }
    public CommittedOf(id: string): number { return this.TermsOf(id).reduce((s, t) => s + (t.CommittedAmount ?? 0), 0); }

    public Tone(s: string | null): string { return statusTone(s); }
    public Fill(t: TermRow): string { return termFill(t.Status); }

    // ── The open-documents strip ────────────────────────────────────────────────────────────────

    public get ActiveDraft(): ContractDraft | null {
        return this.Drafts.ActiveTab?.State ?? null;
    }

    /** The primary verb's label — the ONE thing the card lets a workshop change. */
    public get ConfirmLabel(): string {
        return this.ActiveDraft?.IsSaved ? 'Save changes' : 'Create contract';
    }

    /**
     * The blocked-reason on the confirm button.
     *
     * A disabled primary action with no explanation is the commonest complaint about a form: the
     * person can see they cannot proceed and not why. The count comes from the draft's own
     * validation, which is the same source the tab badges read.
     */
    public get ConfirmTitle(): string {
        const issues = this.ActiveDraft?.Validate().Issues.filter((i) => i.Severity === 'error') ?? [];
        if (!issues.length) return this.ConfirmLabel;
        return `${issues.length} thing${issues.length === 1 ? '' : 's'} to fix first — ${issues[0].Message}`;
    }

    public get CanSaveActive(): boolean {
        return !!this.ActiveDraft && this.ActiveDraft.Validate().IsValid;
    }

    public get IsSaving(): boolean {
        return this.Workspace?.Saving() === true;
    }

    public get WorkspaceMessage(): string {
        return this.Workspace?.Message ?? '';
    }

    public get CanTerminateActive(): boolean {
        return this.Workspace?.CanTerminate === true;
    }

    /** The card's footer drives the verbs; the pane owns them. */
    public async SaveActive(): Promise<void> {
        await this.Workspace?.Save();
        const tab = this.Drafts.ActiveTab;
        if (tab && this.ActiveDraft) this.Drafts.UpdateState(tab.Id, this.ActiveDraft, false);
        this.cdr.detectChanges();
    }

    public async TerminateActive(): Promise<void> {
        await this.Workspace?.PreviewTermination();
        this.cdr.detectChanges();
    }

    public CloseActive(): void {
        const tab = this.Drafts.ActiveTab;
        if (tab) this.CloseDoc(tab.Id);
    }

    /** Everything the workspace's pickers need, resolved once here so the pane never queries. */
    public get WorkspaceLookups(): WorkspaceLookups {
        return {
            Types: this.Types,
            Companies: this.Companies,
            Organizations: this.Orgs,
            People: this.People,
            Users: this.Users,
            Products: this.Products,
            SubscriptionTypes: this.SubscriptionTypes,
            PaymentTerms: this.PayTerms,
            Currencies: this.Currencies,
        };
    }

    /**
     * Open a NEW contract — which is simply a document whose draft has no id.
     *
     * Note what does NOT happen here: no navigation to a different page, no separate create mode,
     * no different component. That is the consolidation working.
     */
    /**
     * Give a draft the escalation ceiling its contract type prescribes.
     *
     * ADVISORY ONLY — the entity layer reads the ceiling from the type itself and refuses a term
     * that exceeds it, and that is the copy that counts. This one exists so an over-cap escalation
     * turns red as it is typed rather than on submit. Re-called whenever the TYPE changes, because a
     * hint left over from the previous type would judge the number against the wrong ceiling.
     */
    public ApplyTypeCeiling(draft: ContractDraft | null | undefined): void {
        if (!draft) return;
        draft.TypeCeilingPercent = this.Types.find((t) => t.ID === draft.ContractTypeID)?.DefaultMaxEscalationPercent ?? null;
    }

    public NewContract(): void {
        const draft = new ContractDraft();
        draft.Status = 'Draft';
        // A NEW CONTRACT STARTS WITH A TERM.
        //
        // Coverage, billing and commitments all hang off a term, so a contract with none had six of
        // its eight panes greyed out on creation — technically correct and useless, because those
        // are exactly the things a person sets WHILE creating a contract. Nobody records an
        // agreement and then decides separately whether it has a period.
        //
        // Seeding one takes the greyed count from six to three, and the three that remain
        // (Amendments, Documents, History) genuinely cannot exist before the record does: an
        // amendment changes a term that already exists, a file attaches through
        // FileEntityRecordLink to a saved RecordID, and there is no history until something has
        // happened. Those are facts about the data, not choices about the form.
        const term = draft.AddTerm();
        const today = new Date();
        const start = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
        const end = new Date(start);
        end.setUTCFullYear(end.getUTCFullYear() + 1);
        end.setUTCDate(end.getUTCDate() - 1);
        term.StartDate = start.toISOString().slice(0, 10);
        term.EndDate = end.toISOString().slice(0, 10);
        // Seed the single-company case so the commonest contract needs one fewer choice. A
        // multi-company tenant sees a picker with a value already selected, which is still correct.
        if (this.Companies.length === 1) draft.CompanyID = this.Companies[0].ID;
        this.ApplyTypeCeiling(draft);
        this.docSeed += 1;
        this.Drafts.Open({
            Id: `new-${this.docSeed}`,
            Label: 'New contract',
            Icon: 'fa-solid fa-file-circle-plus',
            Status: 'draft',
            State: draft,
        });
        // No Section assignment: only the Contracts resource reaches this code, and writing to it
        // is what made the Billing tab render the Contracts rail under a "Billing" highlight.
        this.Page = 'workspace';
        this.cdr.detectChanges();
    }

    /**
     * Open an existing contract.
     *
     * IN THE CONTRACTS SECTION this opens the workspace in place, which is the main path.
     *
     * FROM BILLING OR SETUP it opens MJ's own record tab instead. An earlier version switched
     * `this.Section` to 'contracts' and showed the workspace inside the Billing tab — so the top
     * nav highlighted Billing while the rail and the content were the Contracts workspace. The
     * screen said two different things about where you were.
     *
     * Sections are separate registered resources with separate tab stores, so carrying "open THIS
     * contract" across to the Contracts tab needs a handoff that does not exist yet; `OpenNavItemByName`
     * would land the user on the Contracts section without the contract, which is worse than a
     * record tab that actually shows it. Tracked rather than bodged.
     */
    public async OpenContract(row: ContractRow): Promise<void> {
        if (this.Section !== 'contracts') {
            this.nav.OpenEntityRecord(E_CONTRACTS, CompositeKey.FromID(row.ID));
            return;
        }
        await this.openInWorkspace(row);
    }

    private async openInWorkspace(row: ContractRow): Promise<void> {
        const existing = this.Drafts.Tabs.find((t) => t.State.ID === row.ID);
        if (existing) {
            this.Drafts.Activate(existing.Id);
            this.Page = 'workspace';
            this.cdr.detectChanges();
            return;
        }

        const draft = await this.loadDraft(row.ID);
        if (!draft) {
            // SAY SOMETHING. This used to be a bare `return`, so a row that could not load did
            // nothing at all when clicked — indistinguishable from a dead control, and the most
            // likely cause is the least obvious one: the contract was deleted by someone else since
            // this page loaded. So name that cause, and re-read the roster so the stale row goes
            // away instead of sitting there inviting a second click.
            this.OpenError =
                `${row.ContractNumber} could not be opened. It may have been deleted since this page ` +
                `loaded — the list has been refreshed.`;
            await this.load();
            this.cdr.detectChanges();
            return;
        }
        this.OpenError = '';
        this.rememberRecent(row.ID);
        this.ApplyTypeCeiling(draft);
        this.docSeed += 1;
        this.Drafts.Open({
            Id: `open-${this.docSeed}`,
            // The NUMBER is the tab's name — it is what a person calls the contract out loud, and a
            // strip of descriptions all truncated at the same width identifies nothing.
            Label: row.ContractNumber,
            Icon: 'fa-solid fa-file-signature',
            Status: 'complete',
            State: draft,
        });
        // No Section assignment: only the Contracts resource reaches this code, and writing to it
        // is what made the Billing tab render the Contracts rail under a "Billing" highlight.
        this.Page = 'workspace';
        this.cdr.detectChanges();
    }

    public ActivateDoc(key: string): void {
        this.Drafts.Activate(key);
        this.cdr.detectChanges();
    }

    /** Closing an UNSAVED contract discards it, so say so — the store tracks the dirty flag for us. */
    public CloseDoc(key: string): void {
        const tab = this.Drafts.Tabs.find((t) => t.Id === key);
        if (tab && !tab.State.IsSaved && !confirm('This contract has not been saved. Close it and lose the entry?')) return;
        this.Drafts.Close(key);
        this.cdr.detectChanges();
    }

    /**
     * After a save: refresh the roster, and re-point the open document at the SAVED draft.
     *
     * The re-point is not cosmetic. The workspace rebuilds its draft from what the server wrote (so
     * it shows the allocated number and the derived term numbers), which REPLACES its own reference
     * — leaving the shell still holding the pre-save object. The visible symptom was a document tab
     * still reading "New contract" beside a header reading CTR-000079; the invisible one is worse,
     * because closing and reopening that tab would resurrect a draft with no id and create a second
     * contract on the next save.
     */
    /**
     * A lifecycle operation changed the contract on the server, so the open draft is stale — the
     * term's status moved, a renewal added a term, activation created a schedule and its events.
     * Re-read rather than patch: a UI that guesses what an operation did is a UI that drifts.
     */
    public async OnReloadRequested(contractID: string): Promise<void> {
        if (!contractID) return;
        const tab = this.Drafts.ActiveTab;
        const fresh = await this.loadDraft(contractID);
        if (tab && fresh) this.Drafts.UpdateState(tab.Id, fresh, false);
        await this.load();
        this.cdr.detectChanges();
    }

    public async OnContractSaved(payload: ContractDraftPayload): Promise<void> {
        const tab = this.Drafts.ActiveTab;
        if (tab) {
            this.Drafts.UpdateState(tab.Id, ContractDraft.FromPayload(payload), false);
            // The tab's caption is the contract NUMBER, which the server only just allocated.
            tab.Label = payload.ContractNumber ?? tab.Label;
            tab.Icon = 'fa-solid fa-file-signature';
            tab.Status = 'complete';
        }
        await this.load();
        this.cdr.detectChanges();
    }

    /**
     * Read a contract's whole tree into a draft.
     *
     * FOUR READS, not one per term: the lines, schedules and commitments come back in one query
     * each filtered on every term at once, then are distributed in memory. A RunView per term would
     * be the anti-pattern the data-access rules name explicitly.
     */
    private async loadDraft(contractID: string): Promise<ContractDraft | null> {
        const rv = new RunView();
        const [contracts, terms] = await rv.RunViews([
            { EntityName: E_CONTRACTS, ExtraFilter: `ID='${contractID}'`, ResultType: 'simple' },
            { EntityName: E_TERMS, ExtraFilter: `ContractID='${contractID}'`, OrderBy: 'TermNumber ASC', ResultType: 'simple' },
        ]);
        if (!contracts?.Success || !contracts.Results?.length) {
            this.Error = `Could not load contract ${contractID}.`;
            return null;
        }

        const termRows = (terms?.Results ?? []) as Record<string, unknown>[];
        const termIDs = termRows.map((t) => String(t['ID']));
        const inList = termIDs.length ? termIDs.map((id) => `'${id}'`).join(',') : `'00000000-0000-0000-0000-000000000000'`;
        const [lines, schedules, commitments] = await rv.RunViews([
            { EntityName: E_LINES, ExtraFilter: `ContractTermID IN (${inList})`, OrderBy: 'DisplayOrder ASC', ResultType: 'simple' },
            { EntityName: E_SCHEDULES, ExtraFilter: `ContractTermID IN (${inList})`, ResultType: 'simple' },
            { EntityName: E_COMMITMENTS, ExtraFilter: `ContractTermID IN (${inList})`, ResultType: 'simple' },
        ]);

        const header = contracts.Results[0] as Record<string, unknown>;
        const iso = (v: unknown): string | null => {
            if (!v) return null;
            const d = new Date(String(v));
            return Number.isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
        };
        const byTerm = <T extends Record<string, unknown>>(rows: T[] | undefined, termID: string): T[] =>
            (rows ?? []).filter((r) => String(r['ContractTermID']).toLowerCase() === termID.toLowerCase());

        return ContractDraft.FromPayload({
            ID: String(header['ID']),
            ContractNumber: (header['ContractNumber'] as string) ?? null,
            ContractTypeID: String(header['ContractTypeID'] ?? ''),
            CompanyID: String(header['CompanyID'] ?? ''),
            CustomerOrganizationID: (header['CustomerOrganizationID'] as string) ?? null,
            CustomerPersonID: (header['CustomerPersonID'] as string) ?? null,
            PrimaryContactPersonID: (header['PrimaryContactPersonID'] as string) ?? null,
            OwnerUserID: (header['OwnerUserID'] as string) ?? null,
            ParentContractID: (header['ParentContractID'] as string) ?? null,
            Status: String(header['Status'] ?? 'Draft'),
            Description: (header['Description'] as string) ?? null,
            EffectiveDate: iso(header['EffectiveDate']),
            ExecutedDate: iso(header['ExecutedDate']),
            PricedAt: iso(header['PricedAt']),
            AutoRenew: !!header['AutoRenew'],
            CancellationWindowDays: (header['CancellationWindowDays'] as number) ?? null,
            RenewalNoticeDays: (header['RenewalNoticeDays'] as number) ?? null,
            TerminationPolicy: (header['TerminationPolicy'] as string) ?? null,
            ExternalReferenceID: (header['ExternalReferenceID'] as string) ?? null,
            Terms: termRows.map((t) => {
                const termID = String(t['ID']);
                return {
                    ID: termID,
                    StartDate: iso(t['StartDate']) ?? '',
                    EndDate: iso(t['EndDate']) ?? '',
                    Status: String(t['Status'] ?? 'Pending'),
                    BillingFrequency: String(t['BillingFrequency'] ?? 'Annual'),
                    CommittedAmount: (t['CommittedAmount'] as number) ?? null,
                    EscalationPercent: (t['EscalationPercent'] as number) ?? null,
                    EscalationBasis: (t['EscalationBasis'] as string) ?? null,
                    RenewalProbability: (t['RenewalProbability'] as number) ?? null,
                    PaymentTermsTypeID: (t['PaymentTermsTypeID'] as string) ?? null,
                    CurrencyID: (t['CurrencyID'] as string) ?? null,
                    EarlyTerminationDate: iso(t['EarlyTerminationDate']),
                    Notes: (t['Notes'] as string) ?? null,
                    Lines: byTerm(lines?.Results as Record<string, unknown>[] | undefined, termID).map((l) => ({
                        ID: String(l['ID']),
                        ProductID: String(l['ProductID'] ?? ''),
                        LineType: String(l['LineType'] ?? 'OneTime'),
                        Quantity: Number(l['Quantity'] ?? 1),
                        ContractedUnitPrice: (l['ContractedUnitPrice'] as number) ?? null,
                        DiscountPct: (l['DiscountPct'] as number) ?? null,
                        StartDate: iso(l['StartDate']),
                        EndDate: iso(l['EndDate']),
                        SubscriptionTypeID: (l['SubscriptionTypeID'] as string) ?? null,
                        Description: (l['Description'] as string) ?? null,
                    })),
                    Schedules: byTerm(schedules?.Results as Record<string, unknown>[] | undefined, termID).map((sc) => ({
                        ID: String(sc['ID']),
                        ScheduleType: String(sc['ScheduleType'] ?? 'Cadence'),
                        Frequency: (sc['Frequency'] as string) ?? null,
                        AnchorDate: iso(sc['AnchorDate']),
                        IsActive: sc['IsActive'] !== false,
                        Notes: (sc['Notes'] as string) ?? null,
                    })),
                    Commitments: byTerm(commitments?.Results as Record<string, unknown>[] | undefined, termID).map((cm) => ({
                        ID: String(cm['ID']),
                        CommitmentType: String(cm['CommitmentType'] ?? 'Minimum'),
                        CommittedAmount: Number(cm['CommittedAmount'] ?? 0),
                        ConsumedAmount: Number(cm['ConsumedAmount'] ?? 0),
                        PeriodStart: iso(cm['PeriodStart']),
                        PeriodEnd: iso(cm['PeriodEnd']),
                        TrueUpPolicy: String(cm['TrueUpPolicy'] ?? 'BillShortfall'),
                        Status: String(cm['Status'] ?? 'Open'),
                    })),
                };
            }),
            RemovedTermIDs: [],
            RemovedLineIDs: [],
            RemovedScheduleIDs: [],
            RemovedCommitmentIDs: [],
        });
    }

    public OnNav(item: MJLeftNavItem): void {
        this.Page = item.id;
        // DELIBERATELY does NOT seed a new contract. An earlier version did — reasoning that an
        // empty workspace is a dead end — and that made opening an EXISTING contract impossible:
        // the picker only shows when nothing is open, so auto-creating a draft hid it every time.
        // The empty state offers both the picker and a New contract button, which is the choice the
        // person actually has.
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
        // NO FILTER MEANS BROWSE, not "nothing". This used to return [] until somebody typed, which
        // was right when it sat beside a populated workspace and wrong now that it IS the empty
        // state: "Open a contract" showing nothing until you guess a search term is a dead end.
        if (!q && !this.StatusFilter) return this.Contracts.slice(0, 25);
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
        this.scope(c.ID);
        this.cdr.detectChanges();
    }

    public ClearSearch(): void { this.Query = ''; this.StatusFilter = ''; this.cdr.detectChanges(); }
    public cdrTick(): void { this.cdr.detectChanges(); }

    // ---- create-page draft tabs (accounting's workspace card) ----






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
    /**
     * The term coverage should be added to: the live one, or the latest if none is live.
     *
     * A contract usually has several terms and only one of them is current, so "add a line" from the
     * Coverage tab has to pick — and picking the Active term is what a person means. Returns null
     * when there are no terms at all, which is what disables the control rather than producing an
     * orphaned line.
     */
    public LiveTermOf(contractID: string): TermRow | null {
        const terms = this.TermsOf(contractID);
        return terms.find((t) => t.Status === 'Active') ?? terms[terms.length - 1] ?? null;
    }

    public async AddCoverageToLiveTerm(c: ContractRow): Promise<void> {
        const term = this.LiveTermOf(c.ID);
        if (!term) return;
        await this.AddCoverage(term);
    }

    /** Open a coverage line in its own custom form, from a click on the grid row. */
    public async OpenLine(args: AfterRowClickEventArgs): Promise<void> {
        const id = (args?.row as Record<string, unknown> | undefined)?.['ID'];
        if (typeof id !== 'string') return;
        await this.presentForm({ EntityName: E_LINES, RecordId: id, Title: 'Coverage line' });
    }

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







    // ---- the audit trail --------------------------------------------------------------------------

    public LogOf(contractID: string): LogRow[] {
        return this.Log.filter((l) => l.ContractID === contractID);
    }

    /** A human sentence for an event type. The vocabulary is closed, so this map is exhaustive. */
    public EventLabel(t: string): string { return eventLabel(t); }

    public EventTone(t: string): string { return eventTone(t); }

    public EventDetail(payload: string | null): string[] { return eventDetail(payload); }







    /** Percent in the UI, fraction in the database. */
    private pct(v: number | null): number | null { return percentToFraction(v); }

    public async Refresh(): Promise<void> {
        await this.load();
        this.P = { ...this.P, contracts: { ...this.P['contracts'] } };
        this.cdr.detectChanges();
    }

    // ------------------------------------------------------------------ internals

    private toDate(v: string | undefined): Date | null {
        return v ? new Date(v + 'T00:00:00') : null;
    }


    /** Params are REASSIGNED, never mutated — an in-place edit does not trip change detection. */
    private scope(contractID: string): void {
        const ids = this.TermsOf(contractID).map((t) => `'${t.ID}'`);
        const scope = ids.length ? `ContractTermID IN (${ids.join(',')})` : '1=0';
        this.P = {
            ...this.P,
            terms: { EntityName: E_TERMS, ExtraFilter: `ContractID='${contractID}'`, OrderBy: 'TermNumber' },
            // FIELDS ARE NAMED DELIBERATELY. Left to its defaults the grid renders the entity's raw
            // columns, so coverage displayed ProductID as a bare UUID and no description at all —
            // technically the right rows, and unreadable. `Product` and `SubscriptionType` are the
            // view's denormalized name columns, which is what a person is actually looking for.
            lines: {
                EntityName: E_LINES,
                ExtraFilter: scope,
                OrderBy: 'DisplayOrder',
                Fields: ['DisplayOrder', 'Description', 'Product', 'LineType', 'SubscriptionType', 'Quantity', 'ContractedUnitPrice', 'DiscountPct', 'StartDate', 'EndDate'],
            },
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
        const [contracts, terms, events, types, companies, orgs, people, users, payterms, currencies, products, subtypes, log,
               schedules, commitments, amendments] = await rv.RunViews([
            { EntityName: E_CONTRACTS, Fields: ['ID', 'ContractNumber', 'Status', 'Description', 'EffectiveDate', 'ExecutedDate', 'PricedAt', 'AutoRenew', 'CancellationWindowDays', 'RenewalNoticeDays', 'ExternalReferenceID'], OrderBy: 'ContractNumber', ResultType: 'simple' },
            { EntityName: E_TERMS, Fields: ['ID', 'ContractID', 'TermNumber', 'Status', 'StartDate', 'EndDate', 'CommittedAmount', 'EscalationPercent', 'BillingFrequency'], OrderBy: 'TermNumber', ResultType: 'simple' },
            { EntityName: E_EVENTS, Fields: ['ID', 'ContractTermID', 'ScheduledDate', 'Status', 'ComputedAmount', 'FailureReason'], OrderBy: 'ScheduledDate', ResultType: 'simple' },
            { EntityName: E_TYPES, Fields: ['ID', 'Name', 'DefaultMaxEscalationPercent'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_COMPANIES, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_ORGS, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_PEOPLE, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_USERS, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_PAYTERMS, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_CURRENCIES, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_PRODUCTS, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_SUBTYPES, Fields: ['ID', 'Name'], OrderBy: 'Name', ResultType: 'simple' },
            { EntityName: E_EVENTLOG, Fields: ['ID', 'ContractID', 'ContractTermID', 'EventType', 'EventDate', 'Payload', 'PerformedByUser'], OrderBy: 'EventDate DESC', ResultType: 'simple' },
            // The cross-contract sets. Loaded here rather than by a grid so the worklists can show
            // the CONTRACT NUMBER and TERM NUMBER a person recognises instead of the raw foreign
            // keys — resolving those needs the contracts and terms, which this method already has.
            { EntityName: E_SCHEDULES, Fields: ['ID', 'ContractTermID', 'ScheduleType', 'Frequency', 'AnchorDate', 'IsActive'], ResultType: 'simple' },
            { EntityName: E_COMMITMENTS, Fields: ['ID', 'ContractTermID', 'CommitmentType', 'CommittedAmount', 'ConsumedAmount', 'PeriodStart', 'PeriodEnd', 'TrueUpPolicy', 'Status'], ResultType: 'simple' },
            { EntityName: E_AMENDMENTS, Fields: ['ID', 'ContractTermID', 'AmendmentNumber', 'EffectiveDate', 'AmendmentType', 'Description', 'Status'], OrderBy: 'EffectiveDate DESC', ResultType: 'simple' },
        ]);

        // RunView reports failure via Success — it never throws — so each result is checked.
        this.Contracts = contracts?.Success ? (contracts.Results as ContractRow[]) : [];
        this.Terms = terms?.Success ? (terms.Results as TermRow[]) : [];
        this.Events = events?.Success ? (events.Results as EventRow[]) : [];
        this.Types = types?.Success ? (types.Results as TypeRow[]) : [];
        this.Companies = companies?.Success ? (companies.Results as Lookup[]) : [];
        this.Orgs = orgs?.Success ? (orgs.Results as Lookup[]) : [];
        this.People = people?.Success ? (people.Results as Lookup[]) : [];
        this.Users = users?.Success ? (users.Results as Lookup[]) : [];
        this.PayTerms = payterms?.Success ? (payterms.Results as Lookup[]) : [];
        this.Currencies = currencies?.Success ? (currencies.Results as Lookup[]) : [];
        this.Products = products?.Success ? (products.Results as Lookup[]) : [];
        this.SubscriptionTypes = subtypes?.Success ? (subtypes.Results as Lookup[]) : [];
        this.Log = log?.Success ? (log.Results as LogRow[]) : [];
        this.Schedules = schedules?.Success ? (schedules.Results as ScheduleRow[]) : [];
        this.Commitments = commitments?.Success ? (commitments.Results as CommitmentRow[]) : [];
        this.Amendments = amendments?.Success ? (amendments.Results as AmendmentRow[]) : [];

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

/* ────────────────────────────────────────────────────────────────────────────────────────────────
 * THE THREE NAV ITEMS
 *
 * Each is registered under the driver class the Application's `DefaultNavItems` reference
 * (`metadata/applications/.contracts-application.json`), which is what makes them plug into MJ
 * Explorer with no host-side wiring: Explorer reads the nav metadata, asks the class factory for the
 * driver class, and mounts it as a top-level tab. BOTH HALVES ARE REQUIRED — metadata without a
 * registered class renders a dead tab, and a registered class without metadata never appears.
 *
 * This is what MJ's "top nav ACROSS sections, left nav WITHIN one" actually means in code. An
 * earlier version of this file drew a tab strip in the page header instead, which looked like a top
 * nav bar and behaved like nothing: no deep links, no resource state, no place in the app switcher,
 * and one entry in Explorer's own navigation however many tabs the picture showed.
 *
 * They are deliberately thin. Each pins its section and delegates everything else to the shared
 * component above, so a change to a rail or a page lands once rather than three times.
 * ──────────────────────────────────────────────────────────────────────────────────────────────── */

/** Contracts — the agreement: find one, open one, write one, amend one. */
@RegisterClass(BaseResourceComponent, 'ContractsSectionResource')
@Component({
    selector: 'mjc-contracts-resource',
    standalone: true,
    imports: [MJCContractsSectionComponent],
    template: `<mjc-contracts-section Section="contracts"></mjc-contracts-section>`,
})
export class ContractsSectionResource extends BaseResourceComponent {
    public override async GetResourceDisplayName(_d: ResourceData): Promise<string> { return 'Contracts'; }
    public override async GetResourceIconClass(_d: ResourceData): Promise<string> { return 'fa-solid fa-file-signature'; }
}

/**
 * Billing — the money the agreement produces.
 *
 * A PEER of Contracts rather than a page beneath it, because "what failed and why" is a different
 * job, done by different people at different times, from "what did we agree". Filing one under the
 * other makes the smaller one invisible — which is exactly what orders decided when it split
 * Receivables out of Orders.
 */
@RegisterClass(BaseResourceComponent, 'ContractsBillingSectionResource')
@Component({
    selector: 'mjc-billing-resource',
    standalone: true,
    imports: [MJCContractsSectionComponent],
    template: `<mjc-contracts-section Section="billing"></mjc-contracts-section>`,
})
export class ContractsBillingSectionResource extends BaseResourceComponent {
    public override async GetResourceDisplayName(_d: ResourceData): Promise<string> { return 'Billing'; }
    public override async GetResourceIconClass(_d: ResourceData): Promise<string> { return 'fa-solid fa-conveyor-belt'; }
}

/** Setup — the configuration every contract inherits. */
@RegisterClass(BaseResourceComponent, 'ContractsSetupSectionResource')
@Component({
    selector: 'mjc-setup-resource',
    standalone: true,
    imports: [MJCContractsSectionComponent],
    template: `<mjc-contracts-section Section="setup"></mjc-contracts-section>`,
})
export class ContractsSetupSectionResource extends BaseResourceComponent {
    public override async GetResourceDisplayName(_d: ResourceData): Promise<string> { return 'Setup'; }
    public override async GetResourceIconClass(_d: ResourceData): Promise<string> { return 'fa-solid fa-sliders'; }
}
