/**
 * @fileoverview The Contracts dashboard — obligation command center.
 *
 * NOT A REVENUE CHART. Plan §1: contracts is not money. Every number here is a COUNT or a date.
 * Tiles are counted from the layered view's DERIVED columns (`IsAwaitingDocument`,
 * `RenewalNoticeDeadline`, `DaysToEnd`, `HasModifications`, `State`) with `TotalRowCount`, so they
 * cannot disagree with the worklists. Charts read the same columns off a roster; they do not
 * re-derive "expiring soon".
 *
 * A hot-list row is `NavigationService.OpenEntityRecord`. A tile click still jumps to the matching
 * rail worklist.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, EventEmitter, OnInit, Output, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CompositeKey, Metadata, type EntityInfo } from '@memberjunction/core';
import { NavigationService } from '@memberjunction/ng-shared';
import { EntityViewerModule, type RecordOpenedEvent } from '@memberjunction/ng-entity-viewer';
import type { MJUserViewEntityExtended } from '@memberjunction/core-entities';
import { CONTRACT_STATES } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';

/** One headline number, and where clicking it goes. */
interface AttentionTile {
    Id: string;
    Label: string;
    Hint: string;
    Filter: string;
    GoTo: string | null;
    Count: number | null;
}

interface StateBar {
    State: string;
    Count: number;
}

interface HorizonBucket {
    Label: string;
    Count: number;
}

interface ContractRow {
    ID: string;
    Name: string;
    ContractNumber: string | null;
    State: string;
    CustomerOrganization: string | null;
    DaysToEnd: number | null;
    IsAwaitingDocument: boolean | number | string | null;
    HasModifications: boolean | number | string | null;
    RenewalNoticeDeadline: string | Date | null;
    EndDate: string | Date | null;
}

@Component({
    selector: 'mjc-contracts-dashboard-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, EntityViewerModule],
    template: `
        <div class="mjc-page">
            <p class="mjc-page__intro">
                What needs a person. Tile counts come from the same view the worklists read. Charts
                are counts and dates — never dollars.
            </p>

            <div class="mjc-kpis">
                @for (tile of Tiles; track tile.Id) {
                    <button
                        type="button"
                        class="mjc-kpi"
                        [class.mjc-kpi--alert]="tile.Count !== null && tile.Count > 0 && (tile.Id === 'in-force-no-paper' || tile.Id === 'notice-window')"
                        [title]="tile.Hint"
                        [disabled]="!tile.GoTo"
                        (click)="Open(tile)">
                        <div class="mjc-kpi__l">{{ tile.Label }}</div>
                        <div class="mjc-kpi__v">{{ tile.Count === null ? '—' : tile.Count }}</div>
                        <div class="mjc-kpi__f">{{ tile.Hint }}</div>
                    </button>
                }
            </div>

            @if (LoadError) {
                <p class="mjc-empty">{{ LoadError }}</p>
            }

            <div class="mjc-dash-split">
                <div class="mjc-dash-card">
                    <div class="mjc-dash-card__h">
                        State mix
                        <span>layered-view <code>State</code> — not re-derived</span>
                    </div>
                    <div class="mjc-barlist">
                        @if (!StateBars.length) {
                            <p class="mjc-empty">No contracts to mix.</p>
                        } @else {
                            @for (bar of StateBars; track bar.State) {
                                <div class="mjc-barrow">
                                    <b>{{ bar.State }}</b>
                                    <div class="mjc-track">
                                        <div class="mjc-fill" [style.width]="BarPct(bar.Count)"></div>
                                    </div>
                                    <span class="mjc-num">{{ bar.Count }}</span>
                                </div>
                            }
                        }
                    </div>
                </div>
                <div class="mjc-dash-card">
                    <div class="mjc-dash-card__h">
                        Attention
                        <span>same counts as the tiles</span>
                    </div>
                    <div class="mjc-funnel">
                        @for (tile of ChartTiles; track tile.Id) {
                            <div class="mjc-funnel__col">
                                <div class="mjc-funnel__n">{{ tile.Count === null ? '—' : tile.Count }}</div>
                                <div class="mjc-funnel__bar" [style.height]="FunnelHeight(tile.Count)"></div>
                                <div class="mjc-funnel__lab">{{ ShortLabel(tile.Id) }}</div>
                            </div>
                        }
                    </div>
                </div>
            </div>

            <div class="mjc-dash-card">
                <div class="mjc-dash-card__h">
                    Days to end
                    <span>0–120 day horizon · <code>DaysToEnd</code></span>
                </div>
                <div class="mjc-buckets">
                    @for (b of Horizon; track b.Label) {
                        <div class="mjc-bucket">
                            <div class="mjc-kpi__l">{{ b.Label }}</div>
                            <div class="mjc-kpi__v">{{ b.Count }}</div>
                        </div>
                    }
                </div>
            </div>

            <div class="mjc-dash-card">
                <div class="mjc-dash-card__h">
                    Hot list
                    <span>paper, notice, or ending · click → Explorer tab</span>
                </div>
                <div class="mjc-viewer-host">
                    @if (ContractEntityInfo) {
                        <mj-entity-viewer
                            [Entity]="ContractEntityInfo"
                            [ViewEntity]="HotView"
                            (RecordOpened)="OnRecordOpened($event)">
                        </mj-entity-viewer>
                    } @else {
                        <p class="mjc-empty">Contract entity metadata is not loaded.</p>
                    }
                </div>
            </div>
        </div>
    `,
})
export class MJCContractsDashboardPageComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);
    private readonly navigation = inject(NavigationService);

    /** Asks the host section to switch rail pages. The dashboard does not route itself. */
    @Output() NavigateToPage = new EventEmitter<string>();

    public LoadError: string | null = null;
    public StateBars: StateBar[] = [];
    public Horizon: HorizonBucket[] = [];
    public ContractEntityInfo: EntityInfo | null = null;
    public HotView: MJUserViewEntityExtended | null = null;

    /**
     * The questions worth answering on open, in priority order.
     *
     * "In force without paper" leads because it is the only one that is both an obligation we are
     * already performing and a document we cannot produce — the combination that hurts in a dispute.
     */
    public Tiles: AttentionTile[] = [
        {
            Id: 'in-force-no-paper',
            Label: 'In force without paper',
            Hint: 'Active contracts whose type expects an executed document, with none attached',
            Filter: `State = 'Active' AND IsAwaitingDocument = 1`,
            GoTo: 'awaiting',
            Count: null,
        },
        {
            Id: 'notice-window',
            Label: 'Notice window closing (60 days)',
            Hint: 'The renewal-notice deadline falls within 60 days and has not passed',
            Filter:
                'RenewalNoticeDeadline IS NOT NULL ' +
                'AND RenewalNoticeDeadline >= CAST(GETUTCDATE() AS date) ' +
                'AND RenewalNoticeDeadline <= DATEADD(day, 60, CAST(GETUTCDATE() AS date))',
            GoTo: 'renewals',
            Count: null,
        },
        {
            Id: 'ends-120',
            Label: 'Ends within 120 days',
            Hint: 'The quarter-ahead view — renew, re-paper or let expire',
            Filter: 'DaysToEnd IS NOT NULL AND DaysToEnd BETWEEN 0 AND 120',
            GoTo: 'renewals',
            Count: null,
        },
        {
            Id: 'signed-not-started',
            Label: 'Signed, not yet in force',
            Hint: 'Executed with a future effective date — nothing to do until the date arrives',
            Filter: `State = 'Executed'`,
            GoTo: 'list',
            Count: null,
        },
        {
            Id: 'modified',
            Label: 'Modified agreements',
            Hint: 'Carry at least one recorded deviation from the standard terms',
            Filter: 'HasModifications = 1',
            GoTo: 'modifications',
            Count: null,
        },
    ];

    /** The four actionable tiles, in funnel order. Signed-not-started is informational, not a queue. */
    public get ChartTiles(): AttentionTile[] {
        return this.Tiles.filter((t) => t.Id !== 'signed-not-started');
    }

    public ngOnInit(): void {
        void this.refresh();
    }

    public Open(tile: AttentionTile): void {
        if (tile.GoTo) this.NavigateToPage.emit(tile.GoTo);
    }

    public OpenRecord(id: string): void {
        this.navigation.OpenEntityRecord(MJC_ENTITIES.Contract, CompositeKey.FromID(id));
    }

    public OnRecordOpened(event: RecordOpenedEvent): void {
        const id = (event.compositeKey?.GetValueByFieldName('ID') ?? event.record?.['ID']) as string | undefined;
        if (id) this.OpenRecord(id);
    }

    public BarPct(count: number): string {
        const max = Math.max(1, ...this.StateBars.map((b) => b.Count));
        return `${Math.round((count / max) * 100)}%`;
    }

    public FunnelHeight(count: number | null): string {
        const values = this.ChartTiles.map((t) => t.Count ?? 0);
        const max = Math.max(1, ...values);
        const n = count ?? 0;
        return `${Math.max(8, Math.round((n / max) * 100))}%`;
    }

    public ShortLabel(id: string): string {
        switch (id) {
            case 'in-force-no-paper':
                return 'No paper';
            case 'notice-window':
                return 'Notice';
            case 'ends-120':
                return 'Ending';
            case 'modified':
                return 'Modified';
            default:
                return id;
        }
    }

    /**
     * Count every tile concurrently, then load the roster used for mix / horizon / hot list.
     *
     * `MaxRows: 1` and read `TotalRowCount` for tiles — the count comes back without transferring
     * rows. A tile whose query fails shows an em dash rather than a zero.
     */
    private async refresh(): Promise<void> {
        const rv = ScopedRunView();
        let failures = 0;
        await Promise.all(
            this.Tiles.map(async (tile) => {
                try {
                    const result = await rv.RunView({
                        EntityName: MJC_ENTITIES.Contract,
                        ExtraFilter: tile.Filter,
                        MaxRows: 1,
                    });
                    tile.Count = result?.TotalRowCount ?? 0;
                } catch {
                    tile.Count = null;
                    failures += 1;
                }
            }),
        );

        try {
            const roster = await rv.RunView<ContractRow>({
                EntityName: MJC_ENTITIES.Contract,
                ResultType: 'simple',
                MaxRows: 500,
                Fields: [
                    'ID',
                    'Name',
                    'ContractNumber',
                    'State',
                    'CustomerOrganization',
                    'DaysToEnd',
                    'IsAwaitingDocument',
                    'HasModifications',
                    'RenewalNoticeDeadline',
                    'EndDate',
                ],
            });
            const rows = roster?.Success ? (roster.Results ?? []) : [];
            this.StateBars = this.mixStates(rows);
            this.Horizon = this.horizon(rows);
            this.ContractEntityInfo = new Metadata().Entities.find((e) => e.Name === MJC_ENTITIES.Contract) ?? null;
            this.HotView = this.ContractEntityInfo
                ? ({
                      EntityID: this.ContractEntityInfo.ID,
                      Entity: this.ContractEntityInfo.Name,
                      WhereClause: HOT_WHERE,
                      ID: 'contracts-hot',
                      Name: 'Needs a person',
                  } as unknown as MJUserViewEntityExtended)
                : null;
        } catch {
            failures += 1;
        }

        this.LoadError = failures
            ? `${failures} count(s) could not be read — tiles showing “—” are unknown, not zero.`
            : null;
        this.cdr.detectChanges();
    }

    private mixStates(rows: ContractRow[]): StateBar[] {
        const map = new Map<string, number>();
        for (const s of CONTRACT_STATES) map.set(s, 0);
        for (const r of rows) {
            const s = r.State || '—';
            map.set(s, (map.get(s) ?? 0) + 1);
        }
        return [...map.entries()]
            .filter(([, n]) => n > 0)
            .map(([State, Count]) => ({ State, Count }));
    }

    private horizon(rows: ContractRow[]): HorizonBucket[] {
        const buckets: HorizonBucket[] = [
            { Label: '0–30 days', Count: 0 },
            { Label: '31–60 days', Count: 0 },
            { Label: '61–90 days', Count: 0 },
            { Label: '91–120 days', Count: 0 },
        ];
        for (const r of rows) {
            const d = Number(r.DaysToEnd);
            if (!Number.isFinite(d) || d < 0 || d > 120) continue;
            if (d <= 30) buckets[0].Count += 1;
            else if (d <= 60) buckets[1].Count += 1;
            else if (d <= 90) buckets[2].Count += 1;
            else buckets[3].Count += 1;
        }
        return buckets;
    }

}

const HOT_WHERE =
    `(State = 'Active' AND IsAwaitingDocument = 1)` +
    ` OR (RenewalNoticeDeadline IS NOT NULL` +
    ` AND RenewalNoticeDeadline >= CAST(GETUTCDATE() AS date)` +
    ` AND RenewalNoticeDeadline <= DATEADD(day, 60, CAST(GETUTCDATE() AS date)))` +
    ` OR (DaysToEnd IS NOT NULL AND DaysToEnd BETWEEN 0 AND 120)`;


