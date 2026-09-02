/**
 * @fileoverview The Contracts dashboard — four numbers and the book of agreements.
 *
 * WHO OPENS THIS. Finance, to see what needs processing: the Draft contracts a Closed-Won deal
 * created, the agreements still missing signed paper, the notice deadlines coming up. Leadership and
 * sales, to answer one question before a client call — *does this client have special terms?*
 *
 * DELIBERATELY SMALL. Four tiles and one grid. Renewals, awaiting-documents, modifications and tasks
 * each keep their own worklist a click away; this page does not reproduce them. It also shows COUNTS
 * ONLY and never money — pricing and billing are Orders' domain (plan §1).
 *
 * A COUNT THAT FAILS IS "—", NEVER "0". Every tile is a query that can fail, and a zero is a specific
 * claim: "nothing to do here". Telling finance their queue is empty when it is merely unreadable is
 * the one failure this page must not have. Tiles read the layered view's DERIVED columns
 * (`IsAwaitingDocument`, `RenewalNoticeDeadline`, `HasModifications`, `State`), so they cannot
 * disagree with the worklists they link to.
 *
 * WHY IT EXTENDS BaseDashboard. This page is mounted by {@link MJCSectionBaseComponent} into a
 * left-nav shell, which is the exact shape MJ's own Admin container uses — a `BaseResourceComponent`
 * container hosting `BaseDashboard` sub-pages (see `Explorer/dashboards/CLAUDE.md`, "Exception:
 * dynamically-loaded sub-pages of a left-nav shell", and `explorer-settings`' UserManagement /
 * RoleManagement / EntityPermissions). What that buys: `initDashboard()` / `loadData()`, a real
 * `Refresh()`, an `Error` output the section renders, and a guarded load that GUARANTEES
 * `NotifyLoadComplete()` — which this page previously never called at all, relying on the section's
 * 15-second fail-open watchdog.
 *
 * ⚠ `BaseDashboard` does NOT run change detection. The section creates this page and calls
 * `detectChanges()` once, synchronously, long before the counts resolve; `loadData()` must end with
 * `detectChanges()` itself or the page renders its pre-fetch state forever — a dashboard of em
 * dashes against a database full of rows, which reads as a quiet day rather than a bug.
 *
 * CHROME: no `mj-page-layout` / `mj-page-header` here. A sub-page of a left-nav shell must not carry
 * page identity — the shell owns it — so the toolbar is `mj-page-header-interior` instead, with the
 * company filter behind one `mj-filter-popover` per the §3 concise filter model.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, EventEmitter, Output, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CompositeKey, type RunViewParams } from '@memberjunction/core';
import { BaseDashboard, NavigationService } from '@memberjunction/ng-shared';
import type { ResourceData } from '@memberjunction/core-entities';
import { EntityViewerModule, type AfterRowClickEventArgs, type GridColumnConfig } from '@memberjunction/ng-entity-viewer';
import {
    MJFilterPanelComponent,
    MJFilterPopoverComponent,
    MJPageHeaderInteriorComponent,
    type FilterFieldConfig,
} from '@memberjunction/ng-ui-components';
import { StatRowComponent, StatTileComponent, type StatTileTone } from '@mj-biz-apps/common-ng';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';
import { BuildOpenTaskFilters } from '../data/task-filters';

/**
 * Where a tile click goes. `Preset` names a filter pill on the destination page, because a tile that
 * lands on an unfiltered list has not answered the question it was just asked.
 */
export interface MJCDashboardNavigation {
    PageId: string;
    Preset?: string;
}

/** One tile: its identity, what it shows, and where it goes. */
interface DashboardTile {
    Id: string;
    Label: string;
    Icon: string;
    /** `null` means "could not be read" and renders an em dash. Never coerce a failure to 0. */
    Count: number | null;
    Detail: string | null;
    Tone: StatTileTone;
    /** `null` for a tile with nowhere to land — see the note on `special-terms`. */
    GoTo: MJCDashboardNavigation | null;
}

/**
 * The grid's ten columns, in the order the issue specifies.
 *
 * ⚠ THIS IS WHY THE PAGE USES `mj-entity-data-grid` DIRECTLY rather than the
 * `mj-explorer-entity-data-grid` wrapper the three list pages use. The wrapper has no `[Columns]`
 * input and passes none through, so its columns come from each field's `DefaultInView` flag and are
 * then re-sorted by a hardcoded importance heuristic (name fields, then status/type, then
 * descriptions, then dates, then foreign keys). That heuristic cannot express "contract number,
 * description, customer, company, type, state, dates, auto-renew, modified" — and on this page the
 * order IS the design: it is a book of agreements read left to right, newest first.
 *
 * The cost of going direct is that row navigation is wired by hand below rather than inherited.
 * Filed upstream: the wrapper should pass `[Columns]` through.
 */
const GRID_COLUMNS: GridColumnConfig[] = [
    { field: 'ContractNumber', title: 'Contract #', width: 140 },
    { field: 'Description', title: 'Description', width: 260 },
    { field: 'CustomerOrganization', title: 'Customer', width: 200 },
    { field: 'Company', title: 'Company', width: 160 },
    { field: 'ContractType', title: 'Type', width: 150 },
    { field: 'State', title: 'State', width: 110 },
    { field: 'EffectiveDate', title: 'Effective', width: 120 },
    { field: 'EndDate', title: 'Term ends', width: 120 },
    { field: 'AutoRenew', title: 'Auto-renew', width: 110 },
    { field: 'HasModifications', title: 'Modified', width: 100 },
];

/** Rows in force or about to be. Executed-with-a-future-date sorts to the top: it is the newest news. */
const GRID_SCOPE = `State IN ('Active','Executed')`;
const GRID_ORDER = 'EffectiveDate DESC, ContractNumber DESC';

@Component({
    selector: 'mjc-contracts-dashboard-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [
        CommonModule,
        EntityViewerModule,
        StatTileComponent,
        StatRowComponent,
        MJPageHeaderInteriorComponent,
        MJFilterPopoverComponent,
        MJFilterPanelComponent,
    ],
    template: `
        <div class="mjc-page mjc-page--grid">
            <mj-page-header-interior AriaLabel="Filter the contracts dashboard">
                <div toolbar>
                    <mj-filter-popover
                        Label="Company"
                        Icon="fa-solid fa-building"
                        [ActiveCount]="SelectedCompanyIDs.length"
                        [ShowClearAll]="SelectedCompanyIDs.length > 0"
                        (ClearAllRequested)="ClearCompanies()">
                        <mj-filter-panel
                            [Fields]="FilterFields"
                            [Values]="FilterValues"
                            [ShowReset]="false"
                            (ValuesChange)="OnFilterChanged($event)" />
                    </mj-filter-popover>
                </div>
            </mj-page-header-interior>

            <bizapps-stat-row [Error]="CountError">
                @for (tile of Tiles; track tile.Id) {
                    <bizapps-stat-tile
                        [Label]="tile.Label"
                        [Icon]="tile.Icon"
                        [Value]="tile.Count"
                        [Detail]="tile.Detail"
                        [Tone]="tile.Tone"
                        (Clicked)="tile.GoTo ? Open(tile) : null" />
                }
            </bizapps-stat-row>

            <h3 class="mjc-card__title">Active and executed contracts</h3>

            <div class="mjc-grid-fill">
                <mj-entity-data-grid
                    [Params]="GridParams"
                    [Columns]="GridColumns"
                    [ShowToolbar]="false"
                    [NavigateOnDoubleClick]="false"
                    (AfterRowClick)="OnRowClick($event)" />
            </div>
        </div>
    `,
})
export class MJCContractsDashboardPageComponent extends BaseDashboard {
    private readonly cdr = inject(ChangeDetectorRef);
    private readonly navigation = inject(NavigationService);

    /**
     * Asks the host section to switch rails, carrying which pill to select on arrival. The dashboard
     * does not route itself — Explorer resources are not routed components, so page switching inside
     * a section is the section's local state.
     */
    @Output() NavigateToPage = new EventEmitter<MJCDashboardNavigation>();

    public readonly GridColumns = GRID_COLUMNS;
    public GridParams: RunViewParams | null = null;

    /** One sentence under the tile row when a count could not be read. Null when everything read. */
    public CountError: string | null = null;

    /** Companies to restrict to. Empty means All — session-only, deliberately not persisted. */
    public SelectedCompanyIDs: string[] = [];
    public FilterFields: FilterFieldConfig[] = [];
    public FilterValues: Record<string, unknown> = { company: [] };

    public Tiles: DashboardTile[] = [
        {
            Id: 'to-process',
            Label: 'To process',
            Icon: 'fa-solid fa-inbox',
            Count: null,
            Detail: null,
            Tone: 'none',
            GoTo: { PageId: 'list', Preset: 'has-open-task' },
        },
        {
            Id: 'awaiting-document',
            Label: 'Awaiting executed document',
            Icon: 'fa-solid fa-file-circle-question',
            Count: null,
            Detail: null,
            Tone: 'none',
            GoTo: { PageId: 'awaiting' },
        },
        {
            Id: 'notice-deadlines',
            Label: 'Notice deadlines — next 60 days',
            Icon: 'fa-solid fa-hourglass-half',
            Count: null,
            Detail: null,
            Tone: 'none',
            GoTo: { PageId: 'renewals', Preset: 'notice-open' },
        },
        {
            /**
             * ⚠ INTENTIONALLY NOT CLICKABLE, pending a decision — and the tile handles that by
             * itself: with no `GoTo` nothing subscribes usefully, and the shared tile is only
             * focusable and announced as a button when a click does something.
             *
             * The issue asks this to open the Modifications worklist "sorted by customer, add a
             * customer column if absent". The modification entity exposes no customer and has no
             * wrapper view over it (only Contracts and Contract Templates are layered), so that ask
             * requires a new view plus virtual field registrations — a migration, which the same
             * issue rules out under "Schema / migration impact: None". Landing on All Contracts with
             * a modifications pill would need no migration and arguably reads better, since the tile
             * counts CLIENTS. Left inert rather than silently choosing.
             */
            Id: 'special-terms',
            Label: 'Clients with special terms',
            Icon: 'fa-solid fa-pen-ruler',
            Count: null,
            Detail: null,
            Tone: 'none',
            GoTo: null,
        },
    ];

    /* ── lifecycle ────────────────────────────────────────────────────────── */

    /** Runs once, before the first load. Cheap, synchronous setup only. */
    protected initDashboard(): void {
        this.rebuildGrid();
    }

    /**
     * Called by `BaseDashboard` on mount and on every `Refresh()`, inside a guard that emits `Error`
     * and signals load-complete whatever happens here.
     */
    protected async loadData(): Promise<void> {
        await Promise.all([this.loadCompanies(), this.refreshCounts()]);
        this.rebuildGrid();
        // See the file header: the base class does not do this, and without it the page renders its
        // pre-fetch state forever.
        this.cdr.detectChanges();
    }

    /* ── filter ───────────────────────────────────────────────────────────── */

    public OnFilterChanged(values: Record<string, unknown>): void {
        this.FilterValues = values;
        const raw = Array.isArray(values['company']) ? (values['company'] as unknown[]) : [];
        // Validated as UUIDs before they can reach SQL text — these are interpolated into an
        // ExtraFilter, and "it came from our own dropdown" is not a guarantee, it is an assumption.
        this.SelectedCompanyIDs = raw.map(String).filter(isUUID);
        void this.Refresh();
    }

    public ClearCompanies(): void {
        this.FilterValues = { company: [] };
        this.SelectedCompanyIDs = [];
        void this.Refresh();
    }

    /* ── navigation ───────────────────────────────────────────────────────── */

    public Open(tile: DashboardTile): void {
        if (tile.GoTo) this.NavigateToPage.emit(tile.GoTo);
    }

    /**
     * Single click opens the contract, which is what the issue asks for.
     *
     * ⚠ The three list pages open on DOUBLE click (`NavigateOnDoubleClick` + `Navigate`), so this
     * page behaves differently from every other grid in the app. That is a deliberate, flagged
     * deviation rather than an oversight — the dashboard grid is a reading surface with no
     * selection, multi-select or toolbar to compete with a single click.
     */
    public OnRowClick(event: AfterRowClickEventArgs): void {
        const id = (event?.row?.['ID'] ?? event?.rowKey) as string | undefined;
        if (id) this.navigation.OpenEntityRecord(MJC_ENTITIES.Contract, CompositeKey.FromID(id));
    }

    /* ── reads ────────────────────────────────────────────────────────────── */

    /** Company scope, ANDed into every read. Empty selection means All and contributes nothing. */
    private get companyFilter(): string {
        if (!this.SelectedCompanyIDs.length) return '';
        return `CompanyID IN (${this.SelectedCompanyIDs.map((id) => `'${id}'`).join(',')})`;
    }

    private scoped(filter: string): string {
        const company = this.companyFilter;
        return company ? `(${filter}) AND (${company})` : filter;
    }

    private rebuildGrid(): void {
        this.GridParams = {
            EntityName: MJC_ENTITIES.Contract,
            ExtraFilter: this.scoped(GRID_SCOPE),
            OrderBy: GRID_ORDER,
        };
    }

    /**
     * Every selling company, for the chip group.
     *
     * A failure here leaves the chips empty rather than raising: with no chips the page shows All,
     * which is the correct default anyway — losing the ability to narrow is a smaller loss than a
     * dashboard that will not render.
     */
    private async loadCompanies(): Promise<void> {
        try {
            const result = await ScopedRunView(this.ProviderToUse).RunView<{ ID: string; Name: string }>({
                EntityName: MJC_FOREIGN_ENTITIES.Company,
                ResultType: 'simple',
                Fields: ['ID', 'Name'],
                OrderBy: 'Name ASC',
            });
            const rows = result?.Success ? (result.Results ?? []) : [];
            this.FilterFields = [
                {
                    key: 'company',
                    type: 'chips',
                    label: 'Company',
                    multi: true,
                    chipOptions: rows.map((r) => ({ text: r.Name, value: r.ID })),
                },
            ];
        } catch {
            this.FilterFields = [];
        }
    }

    /**
     * Count everything concurrently, then compose one error sentence for whatever failed.
     *
     * Each tile owns its own try/catch so one unreadable count cannot blank the other three, and a
     * failure sets `null` rather than `0`. `MaxRows: 1` with `TotalRowCount` means no rows cross the
     * wire for a count.
     */
    private async refreshCounts(): Promise<void> {
        const rv = ScopedRunView(this.ProviderToUse);
        const failures: string[] = [];

        const count = async (label: string, filter: string): Promise<number | null> => {
            try {
                const r = await rv.RunView({
                    EntityName: MJC_ENTITIES.Contract,
                    ExtraFilter: this.scoped(filter),
                    MaxRows: 1,
                });
                return r?.TotalRowCount ?? 0;
            } catch {
                failures.push(label);
                return null;
            }
        };

        await Promise.all([
            this.countToProcess(count, failures),
            this.countAwaiting(count),
            this.countNoticeDeadlines(count),
            this.countSpecialTerms(rv, failures),
        ]);

        this.CountError = failures.length
            ? `${failures.join(', ')} could not be read — a “—” means unknown, not zero.`
            : null;
    }

    /**
     * Draft contracts with an open Contract Processing task.
     *
     * The filter comes from `task-filters.ts` and is the SAME fragment the All Contracts "Has open
     * task" pill uses, which is what keeps this tile from promising work the list then fails to show.
     * A `null` fragment means bizapps-tasks is not installed (or its type row is missing) — the tile
     * reports unknown rather than claiming zero, because zero would be a lie about a queue.
     */
    private async countToProcess(
        count: (label: string, filter: string) => Promise<number | null>,
        failures: string[],
    ): Promise<void> {
        const tile = this.tile('to-process');
        const filters = await BuildOpenTaskFilters(this.ProviderToUse);
        if (!filters) {
            tile.Count = null;
            tile.Detail = null;
            failures.push('Open tasks');
            return;
        }

        const [open, overdue] = await Promise.all([
            count('To process', `State = 'Draft' AND ${filters.HasOpenTask}`),
            count('Overdue tasks', `State = 'Draft' AND ${filters.HasOverdueTask}`),
        ]);
        tile.Count = open;
        tile.Detail = overdue ? `${overdue} overdue` : null;
        tile.Tone = overdue ? 'warn' : 'none';
    }

    private async countAwaiting(
        count: (label: string, filter: string) => Promise<number | null>,
    ): Promise<void> {
        const tile = this.tile('awaiting-document');
        const [awaiting, inForce] = await Promise.all([
            count('Awaiting documents', `IsAwaitingDocument = 1 AND State IN ('Draft','Executed','Active')`),
            count('In force without paper', `IsAwaitingDocument = 1 AND State = 'Active'`),
        ]);
        tile.Count = awaiting;
        tile.Detail = inForce ? `${inForce} already in force` : null;
        // Error, not warn: operating under an agreement whose signed copy we cannot produce is the
        // combination that hurts in a dispute.
        tile.Tone = inForce ? 'error' : 'none';
    }

    private async countNoticeDeadlines(
        count: (label: string, filter: string) => Promise<number | null>,
    ): Promise<void> {
        const tile = this.tile('notice-deadlines');
        const live = `State IN ('Active','Executed')`;
        const [upcoming, missed] = await Promise.all([
            count(
                'Notice deadlines',
                `${live} AND RenewalNoticeDeadline BETWEEN CAST(GETUTCDATE() AS date) ` +
                    `AND DATEADD(day, 60, CAST(GETUTCDATE() AS date))`,
            ),
            count(
                'Missed deadlines',
                `State = 'Active' AND RenewalNoticeDeadline < CAST(GETUTCDATE() AS date)`,
            ),
        ]);
        tile.Count = upcoming;
        tile.Detail = missed ? `${missed} missed` : null;
        tile.Tone = missed ? 'warn' : 'none';
    }

    /**
     * Distinct customers carrying at least one modified agreement.
     *
     * ONE READ, NOT A STORED QUERY. The issue calls for a query file because `RunView` "has no shape
     * for COUNT(DISTINCT …)" — it does: `Aggregates` run as a parallel query over the same WHERE
     * (filters and RLS included), unaffected by paging, and are plumbed client-to-server. That
     * replaces a query category, a sync manifest, a query JSON and a `.sql` file with six lines, and
     * keeps the company filter working without parameterising SQL by hand.
     */
    private async countSpecialTerms(
        rv: ReturnType<typeof ScopedRunView>,
        failures: string[],
    ): Promise<void> {
        const tile = this.tile('special-terms');
        try {
            const result = await rv.RunView({
                EntityName: MJC_ENTITIES.Contract,
                ExtraFilter: this.scoped(`HasModifications = 1 AND State IN ('Active','Executed')`),
                MaxRows: 1,
                Aggregates: [
                    { expression: 'COUNT(DISTINCT CustomerOrganizationID)', alias: 'CustomerCount' },
                    { expression: 'COUNT(*)', alias: 'ContractCount' },
                ],
            });
            const agg = (result?.AggregateResults ?? []) as { alias?: string; value?: unknown }[];
            const customers = numberFrom(agg, 'CustomerCount');
            const contracts = numberFrom(agg, 'ContractCount');
            if (customers === null) {
                failures.push('Clients with special terms');
                tile.Count = null;
                tile.Detail = null;
                return;
            }
            tile.Count = customers;
            tile.Detail = contracts === null ? null : `across ${contracts} contracts`;
        } catch {
            failures.push('Clients with special terms');
            tile.Count = null;
            tile.Detail = null;
        }
    }

    private tile(id: string): DashboardTile {
        const found = this.Tiles.find((t) => t.Id === id);
        if (!found) throw new Error(`Dashboard tile "${id}" is not defined.`);
        return found;
    }

    /* ── resource identity ────────────────────────────────────────────────── */

    public async GetResourceDisplayName(_data: ResourceData): Promise<string> {
        return 'Dashboard';
    }

    public override async GetResourceIconClass(_data: ResourceData): Promise<string> {
        return 'fa-solid fa-gauge-high';
    }
}

/**
 * Aggregate results come back as an ordered list of `{ alias, value }`, and the value's runtime type
 * depends on the driver — read it by alias and coerce once, here, rather than trusting a position.
 */
function numberFrom(results: { alias?: string; value?: unknown }[], alias: string): number | null {
    const raw = results.find((r) => r.alias === alias)?.value;
    const n = Number(raw);
    return Number.isFinite(n) ? n : null;
}

/** These ids are interpolated into SQL text; anything that is not a UUID does not get to try. */
function isUUID(value: string): boolean {
    return /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/.test(value);
}
