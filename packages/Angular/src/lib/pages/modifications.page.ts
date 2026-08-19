/**
 * @fileoverview Every recorded deviation, across all contracts.
 *
 * WHY THIS IS A PAGE AT ALL. A modification is normally read on its contract, in the editor panel. But
 * "which clauses do we keep negotiating away?" is a question about the PROVISION, not about any one
 * contract, and it is the question that tells the business its standard terms need changing. That
 * question has no home on a contract form.
 *
 * It is a rail item under Contracts rather than its own section because it is a way of READING
 * contracts, not a separate job.
 *
 * The grid selects the modification entity's base view, so `Contract`, `ContractTemplateProvision` and
 * their name columns render as names rather than UUIDs (D-23) — a grid of modification rows showing
 * three UUIDs would be unreadable, and this is the surface that proves the rule earns its keep.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, OnInit, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NavigationService } from '@memberjunction/ng-shared';
import type { CompositeKey } from '@memberjunction/core';
import type { RunViewParams } from '@memberjunction/core';
import { BaseFormsModule } from '@memberjunction/ng-base-forms';
import { MJC_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';

/** One provision and how often it has been modified. */
interface ProvisionTally {
    ProvisionID: string;
    Label: string;
    Count: number;
}

@Component({
    selector: 'mjc-modifications-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <div class="mjc-page mjc-page--grid">
            <p class="mjc-page__intro">
                Every deviation from standard terms that has been recorded, across all contracts. The
                clauses at the top are the ones the business negotiates away most often — which is the
                signal that a standard term needs revisiting rather than re-negotiating.
            </p>

            @if (TopProvisions.length) {
                <div class="mjc-card">
                    <h3 class="mjc-card__title">Most-modified provisions</h3>
                    <div class="mjc-pills">
                        @for (t of TopProvisions; track t.ProvisionID) {
                            <button
                                type="button"
                                class="mjc-pill"
                                [class.mjc-pill--active]="t.ProvisionID === ActiveProvisionID"
                                [attr.aria-pressed]="t.ProvisionID === ActiveProvisionID"
                                (click)="FilterByProvision(t.ProvisionID)">
                                {{ t.Label }}
                                <span class="mjc-pill__count">{{ t.Count }}</span>
                            </button>
                        }
                    </div>
                </div>
            }

            <div class="mjc-grid-fill">

                <mj-explorer-entity-data-grid

                    [Params]="Params"
                        [ShowToolbar]="true"
                        [NavigateOnDoubleClick]="true"
                (Navigate)="OnNavigate($event)" />

            </div>
        </div>
    `,
})
export class MJCModificationsPageComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);
    protected readonly navigation = inject(NavigationService);

    /**
     * Open the double-clicked record.
     *
     * THE GRID DOES NOT NAVIGATE ITSELF. `NavigateOnDoubleClick` only controls whether it EMITS
     * `Navigate`; acting on it is the HOST's job. Without this, a double-click merely selected the row
     * — measured in a real browser, where it looked exactly like the grid being broken. Explorer's own
     * host wires this for generated forms; a page hosting the grid inside a BaseResourceComponent must
     * do it itself.
     */
    public OnNavigate(event: {
        Kind?: string;
        EntityName?: string;
        PrimaryKey?: CompositeKey;
        DefaultValues?: Record<string, unknown>;
    }): void {
        if (!event?.EntityName) return;
        if (event.Kind === 'record' && event.PrimaryKey) {
            this.navigation.OpenEntityRecord(event.EntityName, event.PrimaryKey);
            return;
        }
        if (event.Kind === 'new-record') {
            // TWO kinds, and missing this one meant the toolbar's New button did NOTHING on every grid
            // page — found in the browser, after the double-click bug had already taught me the same
            // lesson about this component. Handling only 'record' silently dropped it.
            //
            // ⚠ `event.DefaultValues` is DISCARDED here, and it has nowhere to go: NavigationOptions
            // carries no default-values field, so `OpenNewEntityRecord` cannot pre-populate. Harmless on
            // these pages (nothing sets NewRecordValues), but it means the Organization agreements
            // panel's pre-linking to the customer will NOT survive a New click routed through here —
            // that panel needs its own affordance, or MJ needs the option. Written down rather than
            // discovered later as "New forgets the customer".
            this.navigation.OpenNewEntityRecord(event.EntityName);
        }
    }


    public Params: RunViewParams | null = null;
    public TopProvisions: ProvisionTally[] = [];
    public ActiveProvisionID: string | null = null;

    /**
     * MJ's grid ALREADY has a filter toggle and a column chooser — `showFilterToggle` and
     * `showColumnChooser` on `GridToolbarConfig`. We were passing no `ToolbarConfig` at all and got the
     * default, which omits both; the pages then looked like they had no way to filter beyond the pills.
     *
     * Using the stock affordance rather than building a bespoke filter dropdown beside it: AG Grid's
     * per-column filters carry the whole operator set (equals / contains / greater-than / in / is-null),
     * which covers filtering by date, category and the derived State without us writing a filter UI at
     * all. The pills stay because they encode the QUESTIONS finance asks — "notice window passed" is not
     * something a user would assemble from column filters — and the filter button covers everything else.
     */
    public readonly GridToolbar = {
        showSearch: true,
        showFilterToggle: true,
        showColumnChooser: true,
        showRefresh: true,
        showExport: true,
        showRowCount: true,
    };


    public ngOnInit(): void {
        this.rebuild();
        void this.loadTally();
    }

    /** Clicking the active provision clears the filter — the way back to everything. */
    public FilterByProvision(provisionID: string): void {
        this.ActiveProvisionID = this.ActiveProvisionID === provisionID ? null : provisionID;
        this.rebuild();
    }

    private rebuild(): void {
        this.Params = {
            EntityName: MJC_ENTITIES.ContractTemplateModification,
            ExtraFilter: this.ActiveProvisionID ? `ContractTemplateProvisionID = '${this.ActiveProvisionID}'` : '',
            OrderBy: '__mj_CreatedAt DESC',
        };
        this.cdr.detectChanges();
    }

    /**
     * Count modifications per provision, client-side.
     *
     * `RunView` has no GROUP BY, so this reads the rows and tallies them in memory. That is honest at
     * this scale — a modification is a rare, human-authored record, so the whole table is hundreds of
     * rows for years — and it avoids adding an entity or a stored procedure for a single panel. If it
     * ever grows past a few thousand, the right answer is an MJ Query with real SQL, not a bigger loop
     * here; that swap is why the tally is isolated in this method.
     *
     * Failure is swallowed to an empty list: the panel is an aid, and the grid below it is the page.
     */
    private async loadTally(): Promise<void> {
        try {
            const result = await ScopedRunView().RunView({
                EntityName: MJC_ENTITIES.ContractTemplateModification,
                // The base view already joins the provision's name columns (D-23), so no second read.
                ResultType: 'simple',
            });
            const rows = (result?.Results ?? []) as Array<Record<string, unknown>>;
            const counts = new Map<string, ProvisionTally>();
            for (const row of rows) {
                const id = String(row['ContractTemplateProvisionID'] ?? '');
                if (!id) continue;
                const existing = counts.get(id);
                if (existing) {
                    existing.Count += 1;
                    continue;
                }
                // The joined name column is the provision's name field; fall back to the number so a
                // tally never shows a blank pill.
                const label = String(row['ContractTemplateProvision'] ?? row['ProvisionNumber'] ?? 'provision');
                counts.set(id, { ProvisionID: id, Label: label, Count: 1 });
            }
            this.TopProvisions = [...counts.values()].sort((a, b) => b.Count - a.Count).slice(0, 8);
        } catch {
            this.TopProvisions = [];
        }
        this.cdr.detectChanges();
    }
}
