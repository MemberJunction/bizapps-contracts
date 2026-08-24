/**
 * @fileoverview The Contracts dashboard — "what needs attention", not "how are we doing".
 *
 * DELIBERATELY NOT A CHART. This app tracks obligations; the useful question on opening it is which
 * agreements need a person this quarter, and the honest answer is four numbers and the lists behind
 * them. A revenue chart would be a chart about orders' data drawn on contracts' screen, and it would
 * invite reading it as authoritative about money — which contracts explicitly is not (plan §1).
 *
 * Every number is a count over the layered base view's DERIVED columns, so the dashboard cannot
 * disagree with the worklists: both read `IsAwaitingDocument`, `RenewalNoticeDeadline` and `State`
 * from the same view. A dashboard computing its own version of "expiring soon" is how a summary and a
 * worklist end up giving different answers to the same question.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, EventEmitter, OnInit, Output, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MJC_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';

/** One headline number, and where clicking it goes. */
interface AttentionTile {
    Id: string;
    Label: string;
    /** What the number means, in a sentence — shown as the tile's title. */
    Hint: string;
    Filter: string;
    /** Rail page id to open. Null means the tile is informational only. */
    GoTo: string | null;
    Count: number | null;
}

@Component({
    selector: 'mjc-contracts-dashboard-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule],
    template: `
        <div class="mjc-page">
            <p class="mjc-page__intro">
                What needs a person. Every number below is counted from the same view the worklists read,
                so this page and those pages cannot disagree.
            </p>

            <div class="mjc-pills">
                @for (tile of Tiles; track tile.Id) {
                    <button
                        type="button"
                        class="mjc-pill"
                        [class.mjc-pill--active]="tile.Count !== null && tile.Count > 0"
                        [title]="tile.Hint"
                        [disabled]="!tile.GoTo"
                        (click)="Open(tile)">
                        {{ tile.Label }}
                        <span class="mjc-pill__count">{{ tile.Count === null ? '—' : tile.Count }}</span>
                    </button>
                }
            </div>

            @if (LoadError) {
                <p class="mjc-empty">{{ LoadError }}</p>
            }

            <div class="mjc-card">
                <h3 class="mjc-card__title">What this app is, and is not</h3>
                <p class="mjc-page__intro">
                    Contracts is the record of <strong>what we agreed</strong>: the agreement, the standard
                    terms it incorporates, the provisions negotiated away from those terms, and the
                    executed paper. It does not bill and it does not price — orders does that, and a number
                    here is never a number about money owed.
                </p>
            </div>
        </div>
    `,
})
export class MJCContractsDashboardPageComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    /** Asks the host section to switch rail pages. The dashboard does not route itself. */
    @Output() NavigateToPage = new EventEmitter<string>();

    public LoadError: string | null = null;

    /**
     * The four questions worth answering on open, in priority order.
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

    public ngOnInit(): void {
        void this.refresh();
    }

    public Open(tile: AttentionTile): void {
        if (tile.GoTo) this.NavigateToPage.emit(tile.GoTo);
    }

    /**
     * Count every tile concurrently.
     *
     * `MaxRows: 1` and read `TotalRowCount` — the count comes back without transferring rows. A tile
     * whose query fails shows an em dash rather than a zero: "we do not know" and "there are none" are
     * different answers, and showing 0 for the first is the kind of quiet lie a dashboard should never
     * tell. One shared error line explains it once rather than five times.
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
        this.LoadError = failures
            ? `${failures} of ${this.Tiles.length} counts could not be read — the tiles showing “—” are unknown, not zero.`
            : null;
        this.cdr.detectChanges();
    }
}
