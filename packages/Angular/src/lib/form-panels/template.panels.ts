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
        // The provisions ARE the template's content, so this is its own rail item rather than folded
        // into Details with the four header fields (see contract.panels.ts's header for why this key
        // is load-bearing under Layout: 'left-nav').
        inclusion: 'Primary',
    },
})
@Component({
    selector: 'mjc-template-provisions-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule, BaseFormsModule],
    template: `
        <mj-collapsible-panel
            SectionKey="templateProvisions"
            SectionName="Provisions"
            Icon="fa-solid fa-list-ol"
            Variant="related-entity"
            [BadgeCount]="Count"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            @if (LoadError) { <div class="mjc-body"><div class="mjc-flag">{{ LoadError }}</div></div> }

            @if (Provisions.length) {
                <table class="mjc-grid">
                    <thead>
                        <tr>
                            <th style="width:7rem">Number</th>
                            <th style="width:16rem">Title</th>
                            <th>Text</th>
                            @if (EditMode) { <th style="width:5rem"></th> }
                        </tr>
                    </thead>
                    <tbody>
                        @for (p of Provisions; track p.ID ?? $index) {
                            <tr>
                                <td class="mjc-mono">
                                    @if (EditMode) {
                                        <input type="text" style="width:100%" [ngModel]="p.ProvisionNumber"
                                               (ngModelChange)="Set(p, 'ProvisionNumber', $event)"
                                               placeholder="4.2" aria-label="Provision number" />
                                    } @else { {{ p.ProvisionNumber }} }
                                </td>
                                <td>
                                    @if (EditMode) {
                                        <input type="text" style="width:100%" [ngModel]="p.Title"
                                               (ngModelChange)="Set(p, 'Title', $event)"
                                               placeholder="Limitation of Liability" aria-label="Title" />
                                    } @else { <strong>{{ p.Title }}</strong> }
                                </td>
                                <td>
                                    @if (EditMode) {
                                        <textarea class="mjc-clause" rows="4" style="width:100%"
                                                  [ngModel]="p.ProvisionText"
                                                  (ngModelChange)="Set(p, 'ProvisionText', $event)"
                                                  placeholder="The clause text, verbatim."
                                                  aria-label="Provision text"></textarea>
                                    } @else {
                                        <p class="mjc-clause">{{ p.ProvisionText || '(no text captured)' }}</p>
                                    }
                                </td>
                                @if (EditMode) {
                                    <td>
                                        <button type="button" class="mjc-btn mjc-btn--danger mjc-btn--sm"
                                                (click)="Remove(p)" aria-label="Remove this provision">&times;</button>
                                    </td>
                                }
                            </tr>
                        }
                    </tbody>
                </table>
            } @else {
                <div class="mjc-body">
                    <div class="mjc-empty">
                        No provisions yet. Add them in document order — <code>Sequence</code> is what orders the
                        list, because provision numbers do not sort as text.
                    </div>
                </div>
            }

            <div class="mjc-body">
                @if (EditMode) {
                    <button type="button" class="mjc-btn mjc-btn--flat" (click)="Add()">
                        <i class="fa-solid fa-plus" aria-hidden="true"></i> Add a provision
                    </button>
                } @else {
                    <p class="mjc-note">
                        A contract records a deviation by naming one of these, and the text here is what finance
                        reads beside the negotiated language — so an empty clause is a picker entry nobody can
                        evaluate. Use the toolbar's edit button to change them.
                    </p>
                }
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCTemplateProvisionsPanel extends BaseFormPanel<mjBizAppsContractsContractTemplateEntity> {
    private readonly cdr = inject(ChangeDetectorRef);
    public LoadError: string | null = null;
    private loadStarted = false;

    /** Drives the rail badge; undefined so an empty section shows none. */
    public get Count(): number | undefined {
        const n = this.Provisions.length;
        return n > 0 ? n : undefined;
    }

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
