/**
 * @fileoverview The Contract Template form's Provisions editor (item 7).
 *
 * A template version's provisions ARE its content — the reason the row exists. So they get the body of
 * the form rather than a related grid underneath it, which is what Marcelo ruled: a grid of 71 rows with
 * a UUID column is a list of records, not a document.
 *
 * WRITES THROUGH THE SAME COLLECTION THE SEED USES. `template.Provisions` is declared in metadata, so
 * item 4's seeded list and a version typed in here by finance travel identical code paths — which is why
 * "there is no machine-readable source" is not a blocker for a new edition. One `Save()` writes the
 * template and every provision in one transaction, and `Sequence` is renumbered gap-free by the
 * collection rather than by hand.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import type {
    mjBizAppsContractsContractTemplateEntity,
    mjBizAppsContractsContractTemplateProvisionEntity,
} from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:template-provisions',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.ContractTemplate,
        slot: 'after-related',
        sortKey: 100,
        contributionKey: 'provisions',
        relatedEntity: MJC_ENTITIES.ContractTemplateProvision,
    },
})
@Component({
    selector: 'mjc-template-provisions-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    template: `
        <div class="mjc-card">
            <h3 class="mjc-card__title">Provisions ({{ Provisions.length }})</h3>
            <p class="mjc-page__intro">
                The numbered clauses of this agreement version, in document order. A contract records a
                deviation by naming one of these, so the text here is what finance reads beside the
                negotiated language — an empty clause is a picker entry nobody can evaluate.
            </p>

            @if (LoadError) { <p class="mjc-empty">{{ LoadError }}</p> }

            @if (!Provisions.length) {
                <p class="mjc-empty">
                    No provisions yet. Add them in document order — <code>Sequence</code> is what orders
                    the list, because provision numbers do not sort as text.
                </p>
            }

            @for (p of Provisions; track p.ID ?? $index) {
                <div style="border-top:1px solid var(--mj-border-subtle); padding:var(--mj-space-3) 0">
                    @if (EditMode) {
                        <div style="display:flex; gap:var(--mj-space-2); align-items:center; flex-wrap:wrap">
                            <input type="text" style="width:6rem" [ngModel]="p.ProvisionNumber"
                                   (ngModelChange)="Set(p, 'ProvisionNumber', $event)"
                                   placeholder="4.2" aria-label="Provision number" />
                            <input type="text" style="flex:1 1 18rem" [ngModel]="p.Title"
                                   (ngModelChange)="Set(p, 'Title', $event)"
                                   placeholder="Limitation of Liability" aria-label="Title" />
                            <button type="button" class="mjc-pill" (click)="Remove(p)">Remove</button>
                        </div>
                        <textarea rows="5" style="width:100%; margin-top:var(--mj-space-2)"
                                  [ngModel]="p.ProvisionText"
                                  (ngModelChange)="Set(p, 'ProvisionText', $event)"
                                  placeholder="The clause text, verbatim." aria-label="Provision text"></textarea>
                    } @else {
                        <strong>{{ p.ProvisionNumber }} · {{ p.Title }}</strong>
                        <p class="mjc-clause">{{ p.ProvisionText || '(no text captured)' }}</p>
                    }
                </div>
            }

            @if (EditMode) {
                <button type="button" class="mjc-pill" style="margin-top:var(--mj-space-3)" (click)="Add()">
                    <i class="fa-solid fa-plus" aria-hidden="true"></i> Add a provision
                </button>
            }
        </div>
    `,
})
export class MJCTemplateProvisionsPanel extends BaseFormPanel<mjBizAppsContractsContractTemplateEntity> {
    private readonly cdr = inject(ChangeDetectorRef);
    public LoadError: string | null = null;
    private loadStarted = false;

    /** Spread so Angular sees a fresh reference when the collection mutates. */
    public get Provisions(): mjBizAppsContractsContractTemplateProvisionEntity[] {
        // Lazily kick the load on first read rather than in ngOnInit: BaseFormPanel has no lifecycle
        // hook of its own, and the slot host sets `Record` before view init, so the first template read
        // is the earliest reliable moment.
        if (!this.loadStarted) {
            this.loadStarted = true;
            void this.ensureLoaded();
        }
        return [...(this.Record?.Provisions?.Items ?? [])];
    }

    private async ensureLoaded(): Promise<void> {
        const collection = this.Record?.Provisions;
        if (!collection || !this.Record?.IsSaved || collection.IsLoaded) return;
        try {
            await collection.Load();
        } catch (err) {
            this.LoadError = `Could not read this version's provisions: ${String(err)}`;
        }
        this.cdr.detectChanges();
    }

    /**
     * Add a clause at the end. `Sequence` is left to the collection: the declaration carries
     * `{"Field":"Sequence","From":1}`, so it numbers gap-free on save across adds AND removals. Setting
     * it here would fight that and produce duplicates the moment a row is deleted.
     */
    public async Add(): Promise<void> {
        await this.Record?.Provisions?.Create();
        this.cdr.detectChanges();
    }

    public Remove(p: mjBizAppsContractsContractTemplateProvisionEntity): void {
        this.Record?.Provisions?.Remove(p);
        this.cdr.detectChanges();
    }

    public Set(p: mjBizAppsContractsContractTemplateProvisionEntity, field: string, value: string): void {
        (p as unknown as Record<string, unknown>)[field] = value;
    }
}
