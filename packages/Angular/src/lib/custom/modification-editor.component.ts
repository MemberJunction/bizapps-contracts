/**
 * @fileoverview `mjc-modification-editor` — recording what a contract changed about the standard terms.
 *
 * THIS IS THE APP. Everything else tracks facts a document already states; this is where a person
 * records a negotiated deviation, and it is the acceptance test for D-15: no remote operation, no draft
 * object, no second network call. Rows are staged on the contract's `Modifications` collection and land
 * in the SAME transaction as the header when the form's Save toolbar runs one `record.Save()`.
 *
 * ONE COMPONENT, TWO HOSTS (D-22). MJ has no way to embed a child entity's form inside a parent form, so
 * rather than choose between the inline panel and a real form we built one component and render it in
 * both places:
 *
 *   · inline, inside the contract form's modifications panel — binds to `Record.Modifications`, joins
 *     the parent's single save, and `ContractLocked` is true because the contract is the host record;
 *   · as the body of a modification's own custom form, reached from a row's Open action — same
 *     component, one row, the contract fixed rather than editable.
 *
 * IT NEVER SAVES. That is the whole point of the collection: the form container's Save drives one
 * `contract.Save()`, so header and rows commit together or not at all. A component that saved would
 * reintroduce exactly the two-round-trip inconsistency v1's draft object existed to paper over.
 *
 * THE PICKER IS FILTERED, AND THAT IS A RULE NOT A CONVENIENCE. A modification may only name a provision
 * belonging to the template this contract incorporates (ERD §7.1). The server enforces it with two
 * joins; here the picker simply never offers an out-of-template provision, so the rule is invisible in
 * normal use rather than a rejection after the fact.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, EventEmitter, Input, OnInit, Output, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import type { IMetadataProvider } from '@memberjunction/core';
import { ScopedRunView } from '../data/provider';
import type {
    ContractEntity,
    mjBizAppsContractsContractTemplateModificationEntity,
    mjBizAppsContractsContractTemplateProvisionEntity,
} from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';

/** A provision as the picker needs it — enough to choose, and to read the standard clause. */
export interface ProvisionOption {
    ID: string;
    ProvisionNumber: string;
    Title: string;
    ProvisionText: string | null;
    Sequence: number;
}

@Component({
    selector: 'mjc-modification-editor',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule],
    template: `
        @if (LoadError) {
            <p class="mjc-empty">{{ LoadError }}</p>
        }

        @if (!Modifications.length) {
            <p class="mjc-empty">
                No modifications recorded. This contract is on the standard terms
                @if (Record?.HasModifications) {
                    — but it is <strong>flagged as modified</strong>, so the paper differs somewhere.
                    Record what changed, or clear the flag if it was set in error.
                }
            </p>
        }

        @for (mod of Modifications; track mod.ID ?? $index) {
            <div class="mjc-card" style="margin-bottom: var(--mj-space-3)">
                <div class="mjc-clause-pair">
                    <div>
                        <span class="mjc-clause__label">Standard clause</span>
                        @if (provisionFor(mod); as p) {
                            <strong>{{ p.ProvisionNumber }} · {{ p.Title }}</strong>
                            <p class="mjc-clause">{{ p.ProvisionText || '(no text captured for this provision)' }}</p>
                        } @else if (EditMode) {
                            <select
                                [ngModel]="mod.ContractTemplateProvisionID"
                                (ngModelChange)="SetProvision(mod, $event)"
                                aria-label="Which provision does this contract change?">
                                <option [ngValue]="null">Choose a provision…</option>
                                @for (p of Provisions; track p.ID) {
                                    <option [ngValue]="p.ID">{{ p.ProvisionNumber }} · {{ p.Title }}</option>
                                }
                            </select>
                            @if (!Provisions.length) {
                                <p class="mjc-empty">
                                    This contract references no agreement version, so there are no
                                    provisions to choose from. Set its template first.
                                </p>
                            }
                        } @else {
                            <em>No provision selected.</em>
                        }
                    </div>

                    <div>
                        <span class="mjc-clause__label">What this contract says instead</span>
                        @if (EditMode) {
                            <textarea
                                rows="6"
                                [ngModel]="mod.ModificationText"
                                (ngModelChange)="SetText(mod, $event)"
                                aria-label="The negotiated language"></textarea>
                        } @else {
                            <p class="mjc-clause mjc-clause--modified">{{ mod.ModificationText || '(not recorded)' }}</p>
                        }
                    </div>
                </div>

                @if (EditMode) {
                    <div style="margin-top: var(--mj-space-3); display:flex; gap: var(--mj-space-2); align-items:center">
                        <input
                            type="text"
                            [ngModel]="mod.Notes"
                            (ngModelChange)="SetNotes(mod, $event)"
                            placeholder="Optional note — e.g. who negotiated it"
                            aria-label="Note" />
                        <button type="button" class="mjc-pill" (click)="Remove(mod)">Remove</button>
                    </div>
                }
            </div>
        }

        @if (EditMode && !SingleRowMode) {
            <button type="button" class="mjc-pill" (click)="Add()" [disabled]="!Provisions.length">
                <i class="fa-solid fa-plus" aria-hidden="true"></i> Record a modification
            </button>
        }
    `,
})
export class MJCModificationEditorComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    /** The contract whose modifications are being edited. Required in both hosts. */
    @Input() Record?: ContractEntity;

    /** True when the host is a form (so the toolbar owns Save) — drives read/edit rendering. */
    @Input() EditMode = false;

    /**
     * Single-row mode: the modification's own form hosts this component for ONE row, so there is no
     * Add affordance and no list. Same component, different host (D-22).
     */
    @Input() SingleRowMode = false;

    /** In single-row mode, which row. Ignored inline. */
    @Input() OnlyModificationID: string | null = null;

    /**
     * The provider to read through (D-25). Supplied by whichever host mounts this — the contract form's
     * panel passes `FormComponent.ProviderToUse`; the modification form passes its own. Falls back to
     * the ambient provider so the component is still usable in a context that has only one, which is
     * the orders lines-editor shape.
     */
    @Input() Provider?: IMetadataProvider | null;

    /** Raised when a row is added or removed, so the host can mark the form dirty. */
    @Output() Changed = new EventEmitter<void>();

    public Provisions: ProvisionOption[] = [];
    public LoadError: string | null = null;

    public async ngOnInit(): Promise<void> {
        await this.ensureLoaded();
        await this.loadProvisions();
    }

    /** The rows to render. Spread so Angular sees a fresh reference when the collection mutates. */
    public get Modifications(): mjBizAppsContractsContractTemplateModificationEntity[] {
        const items = [...(this.Record?.Modifications?.Items ?? [])];
        if (this.SingleRowMode && this.OnlyModificationID) {
            return items.filter((m) => m.ID === this.OnlyModificationID);
        }
        return items;
    }

    /**
     * Load the collection if it can hold rows and has not been read.
     *
     * `Load: 'explicit'` on the declaration means nothing fetches it for us — which is deliberate, so
     * a contract list does not drag every modification along. The guard mirrors the validation guard:
     * an unsaved record cannot have rows on disk, so there is nothing to fetch.
     */
    private async ensureLoaded(): Promise<void> {
        const collection = this.Record?.Modifications;
        if (!collection || !this.Record?.IsSaved || collection.IsLoaded) return;
        try {
            await collection.Load();
        } catch (err) {
            this.LoadError = `Could not read this contract's modifications: ${String(err)}`;
        }
        this.cdr.detectChanges();
    }

    /**
     * The provisions this contract may modify — its template's, and only its template's.
     *
     * Read once per contract. §6.6 rules that provisions belong in the reference-data cache precisely
     * so this is not a `RunView` per row added; until that engine exists this is one query at bind
     * time, which has the same effect for the user and is honest about not being the cache yet.
     */
    private async loadProvisions(): Promise<void> {
        const templateID = this.Record?.ContractTemplateID;
        if (!templateID) {
            this.Provisions = [];
            return;
        }
        try {
            const result = await ScopedRunView(this.Provider).RunView<mjBizAppsContractsContractTemplateProvisionEntity>({
                EntityName: MJC_ENTITIES.ContractTemplateProvision,
                ExtraFilter: `ContractTemplateID = '${templateID}'`,
                OrderBy: 'Sequence ASC',
                ResultType: 'simple',
            });
            this.Provisions = ((result?.Results ?? []) as unknown as Array<Record<string, unknown>>).map((r) => ({
                ID: String(r['ID']),
                ProvisionNumber: String(r['ProvisionNumber'] ?? ''),
                Title: String(r['Title'] ?? ''),
                ProvisionText: (r['ProvisionText'] as string | null) ?? null,
                Sequence: Number(r['Sequence'] ?? 0),
            }));
        } catch (err) {
            this.LoadError = `Could not read the agreement's provisions: ${String(err)}`;
            this.Provisions = [];
        }
        this.cdr.detectChanges();
    }

    /** The chosen provision for a row, for rendering the standard clause beside the negotiated one. */
    public provisionFor(mod: mjBizAppsContractsContractTemplateModificationEntity): ProvisionOption | undefined {
        const id = mod.ContractTemplateProvisionID;
        return id ? this.Provisions.find((p) => p.ID === id) : undefined;
    }

    /**
     * Add a row.
     *
     * `Modifications.Create()` stamps `ContractID` — that is what the collection is for. Adding the
     * FIRST modification also sets `HasModifications` on the parent in the same graph, so the flag and
     * the rows commit together: the shared `Validate()` would otherwise refuse the save, which is the
     * invariant working as intended rather than an obstacle to route around.
     */
    public async Add(): Promise<void> {
        const collection = this.Record?.Modifications;
        if (!collection || !this.Record) return;
        await collection.Create();
        this.Record.HasModifications = true;
        this.Changed.emit();
        this.cdr.detectChanges();
    }

    /**
     * Remove a row. Deleted on save (`OnRemove: 'delete'`).
     *
     * `HasModifications` is NOT cleared, even when this empties the list. The flag is monotonic by rule
     * (ERD §4.4): its job is to say "the paper differs, go read it", which can be true before any
     * modification is recorded and stays true after a mistaken row is removed. A person clears it
     * deliberately or it stays.
     */
    public Remove(mod: mjBizAppsContractsContractTemplateModificationEntity): void {
        this.Record?.Modifications?.Remove(mod);
        this.Changed.emit();
        this.cdr.detectChanges();
    }

    public SetProvision(mod: mjBizAppsContractsContractTemplateModificationEntity, provisionID: string | null): void {
        mod.ContractTemplateProvisionID = provisionID as string;
        this.Changed.emit();
        this.cdr.detectChanges();
    }

    public SetText(mod: mjBizAppsContractsContractTemplateModificationEntity, text: string): void {
        mod.ModificationText = text;
        this.Changed.emit();
    }

    public SetNotes(mod: mjBizAppsContractsContractTemplateModificationEntity, notes: string): void {
        mod.Notes = notes;
        this.Changed.emit();
    }
}
