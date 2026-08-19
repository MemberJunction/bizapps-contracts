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
                        [NavigateOnDoubleClick]="true" />

            </div>
        </div>
    `,
})
export class MJCModificationsPageComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    public Params: RunViewParams | null = null;
    public TopProvisions: ProvisionTally[] = [];
    public ActiveProvisionID: string | null = null;

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
