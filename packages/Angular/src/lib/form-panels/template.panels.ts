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
 * template and every provision in one transaction. (`Sequence` and its gap-free renumbering were removed by R-11; ordering is derived from `ProvisionNumber` — the trailing text of this sentence is kept below for history.) Formerly: `Sequence` is renumbered gap-free by the
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
            @if (!IsUsable) {
                <div class="mjc-body">
                    <div class="mjc-flag">
                        <span class="mjc-chip mjc-chip--error">Unusable</span>
                        This version records no source URL and has no document attached, so nobody can read
                        the standard terms it names. Add a URL or attach the agreement document — until then a
                        contract cannot incorporate this version.
                    </div>
                </div>
            }

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
                                        <textarea class="mjc-clause"
                                                  [class.mjc-invalid]="IsProvisionTextMissing(p)"
                                                  rows="4" style="width:100%"
                                                  [ngModel]="p.ProvisionText"
                                                  (ngModelChange)="Set(p, 'ProvisionText', $event)"
                                                  placeholder="The clause text, verbatim."
                                                  [attr.aria-invalid]="IsProvisionTextMissing(p) ? 'true' : null"
                                                  [attr.aria-describedby]="IsProvisionTextMissing(p) ? 'mjc-prov-required-' + p.ID : null"
                                                  aria-label="Provision text (required)"></textarea>
                                        @if (IsProvisionTextMissing(p)) {
                                            <div class="mjc-flag" [id]="'mjc-prov-required-' + p.ID">
                                                Required — the standard wording of this clause. A provision
                                                with no text leaves every modification that negotiates it
                                                comparing against nothing.
                                            </div>
                                        }
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
                        No provisions yet. Add them and give each a provision number — the number is what
                        orders the list, via a derived sort key that makes <code>1.9</code> come before
                        <code>1.10</code>.
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
    /**
     * R-12 — whether the standard terms this version names can actually be READ.
     *
     * Derived in `vwContractTemplates` (a URL, or a file linked through `__mj.FileEntityRecordLink`), so
     * this reads the flag rather than recomputing it — the rule lives in one place and the UI renders it.
     *
     * WHY A CHIP AND NOT A REFUSAL, here. A template with neither is INCOMPLETE, not invalid: it is an
     * ordinary state to pass through while authoring one, and on CREATE the "or a file" half is
     * unsatisfiable in principle because a file cannot be linked to a record that does not exist yet. So
     * the template form says so and lets the work continue. The refusal lives one step downstream, where
     * the actual harm is — `ContractEntityServer` rejects a CONTRACT that references an unusable version.
     *
     * Defaults to TRUE while the record is loading, so the warning appears only when it is known to
     * apply. A chip that flashes on every form open teaches people to ignore it.
     */
    /**
     * Whether this provision's standard wording is missing — V202608200800, surfaced WHERE THE EDIT IS.
     *
     * Same threshold as the database (`CK_ContractTemplateProvision_TextNotBlank`, trimmed length > 0)
     * and the same reasoning as the modification editor's marker: the rule was enforced at every rung
     * that refuses a save and absent from the textarea a person actually types in, so the first signal
     * was a failed save. Marcelo saved an empty provision through this very panel on 2026-08-20.
     *
     * Not a minimum length. One character satisfies it, deliberately.
     */
    public IsProvisionTextMissing(p: mjBizAppsContractsContractTemplateProvisionEntity): boolean {
        return !String(p.ProvisionText ?? '').trim();
    }

    public get IsUsable(): boolean {
        const value = this.Record?.Get('IsUsable');
        return value === undefined || value === null ? true : value === true || value === 1;
    }

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
     * Add a clause. THERE IS NO POSITION TO SET ANY MORE — R-11 removed `Sequence` and the collection's
     * `{"Field":"Sequence","From":1}` auto-numbering with it.
     *
     * The order now comes from `ProvisionNumber` via the derived `ProvisionSortKey`, so a new row lands
     * wherever its number says it belongs the moment the number is typed. That is the point of the
     * change: the previous design maintained a second, hand-numbered copy of an order the provision
     * number already stated, and the two had ALREADY disagreed in the seeded data ('1' and '1.1' both
     * claiming position 1).
     *
     * Practical consequence for this panel: a provision with no number sorts to the top (its key is the
     * empty string) until one is entered. That is visible and self-correcting, unlike a duplicate
     * position, which was neither.
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
