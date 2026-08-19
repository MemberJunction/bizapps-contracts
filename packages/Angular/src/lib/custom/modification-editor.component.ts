/**
 * @fileoverview `mjc-modification-editor` — built to `mockups-v2/modifications-editor.html`.
 *
 * THIS IS THE APP. Everything else records facts a document already states; this is where a person
 * records a negotiated deviation. It is the acceptance test for D-15: no remote operation, no draft
 * object, no second network call — rows are staged on the contract's `Modifications` collection and land
 * in the SAME transaction as the header when the form's Save runs one `record.Save()`.
 *
 * ONE COMPONENT, TWO HOSTS (D-22): inline in the contract form's panel, and as the body of a
 * modification's own form. MJ cannot embed a child entity's form inside a parent's, so rather than
 * choose we render one component in both places.
 *
 * WHAT THE MOCKUP SPECIFIES THAT AN EARLIER VERSION OF THIS FILE MISSED:
 *
 *  · A **table**, one row per modification, with the clause pair revealed by clicking the row. The first
 *    version stacked every row as a card with both texts always open — unreadable at three rows, and
 *    9.1's standard clause alone is 1,100 characters.
 *  · A **searchable picker** with a scope banner naming the agreement version, not a bare `<select>`.
 *    The scope line matters: the filter to this contract's template is what replaces the dropped
 *    `ContractTemplateID` column (R-16), so it is a correctness feature and worth stating on screen.
 *  · **The modified text is PRE-FILLED from the standard clause.** *"You edit the clause, you do not
 *    retype it."* This is the single most valuable detail in the mockup and the first version had an
 *    empty textarea — which asks a person to retype a 1,100-character clause to change four words, so
 *    in practice they would paraphrase, and a paraphrased contract clause is exactly what this app
 *    exists to prevent.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, EventEmitter, Input, OnInit, Output, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import type { IMetadataProvider } from '@memberjunction/core';
import type {
    ContractEntity,
    mjBizAppsContractsContractTemplateModificationEntity,
    mjBizAppsContractsContractTemplateProvisionEntity,
} from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';

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
        @if (LoadError) { <div class="mjc-body"><div class="mjc-flag">{{ LoadError }}</div></div> }

        @if (Rows.length) {
            <table class="mjc-grid">
                <thead>
                    <tr>
                        <th style="width:7rem">Provision</th>
                        <th>Clause</th>
                        <th style="width:13rem">Notes</th>
                        <th style="width:5rem"></th>
                    </tr>
                </thead>
                <tbody>
                    @for (row of Rows; track row.mod.ID ?? $index) {
                        <tr class="mjc-row--click" (click)="ToggleRow(row)">
                            <td class="mjc-mono">{{ row.provision?.ProvisionNumber || '—' }}</td>
                            <td>
                                <strong>{{ row.provision?.Title || 'No provision selected' }}</strong>
                                @if (!row.open) {
                                    <button type="button" class="mjc-toggle">show standard &amp; modified text ⌄</button>
                                }
                                @if (row.open) {
                                    <div class="mjc-pair">
                                        <div>
                                            <span class="mjc-pair__tag">Standard — {{ TemplateName || 'the agreement' }}</span>
                                            <p class="mjc-clause">{{ row.provision?.ProvisionText || '(no text captured for this provision)' }}</p>
                                        </div>
                                        <div>
                                            <span class="mjc-pair__tag mjc-pair__tag--mod">As modified — this contract</span>
                                            @if (EditMode) {
                                                <textarea
                                                    class="mjc-clause mjc-clause--mod"
                                                    rows="7"
                                                    style="width:100%"
                                                    [ngModel]="row.mod.ModificationText"
                                                    (ngModelChange)="SetText(row.mod, $event)"
                                                    (click)="$event.stopPropagation()"
                                                    aria-label="The negotiated language"></textarea>
                                            } @else {
                                                <p class="mjc-clause mjc-clause--mod">{{ row.mod.ModificationText || '(not recorded)' }}</p>
                                            }
                                        </div>
                                    </div>
                                    <button type="button" class="mjc-toggle">hide standard &amp; modified text ⌃</button>
                                }
                            </td>
                            <td class="mjc-muted">
                                @if (EditMode) {
                                    <input type="text" style="width:100%"
                                           [ngModel]="row.mod.Notes"
                                           (ngModelChange)="SetNotes(row.mod, $event)"
                                           (click)="$event.stopPropagation()"
                                           placeholder="e.g. who negotiated it" aria-label="Note" />
                                } @else {
                                    {{ row.mod.Notes || '—' }}
                                }
                            </td>
                            <td>
                                @if (EditMode) {
                                    <button type="button" class="mjc-btn mjc-btn--danger mjc-btn--sm"
                                            (click)="Remove(row.mod); $event.stopPropagation()"
                                            aria-label="Remove this modification">&times;</button>
                                }
                            </td>
                        </tr>
                    }
                </tbody>
            </table>
        } @else {
            <div class="mjc-body">
                <div class="mjc-empty">
                    @if (Record?.HasModifications) {
                        This contract is <strong>flagged as modified</strong> but no modifications are recorded —
                        so the paper differs somewhere and nobody has written down where.
                    } @else {
                        No modifications recorded. This contract is on the standard terms.
                    }
                </div>
            </div>
        }

        <!-- ADD FLOW — the picker, then the pair, then Add to list -->
        @if (EditMode && !SingleRowMode) {
            @if (!Adding) {
                <div class="mjc-body">
                    <button type="button" class="mjc-btn mjc-btn--flat" (click)="StartAdd()" [disabled]="!Provisions.length">
                        <i class="fa-solid fa-plus" aria-hidden="true"></i> Add modification
                    </button>
                    @if (!Provisions.length) {
                        <p class="mjc-note">
                            This contract references no agreement version, so there are no provisions to modify.
                            Set its Contract Template first.
                        </p>
                    }
                </div>
            } @else {
                <div class="mjc-body" style="background: var(--mj-color-warning-50); border-left: 3px solid var(--mj-status-warning)">
                    <div style="display:flex; align-items:center; gap:var(--mj-space-2)">
                        <span class="mjc-chip mjc-chip--warn">unsaved</span>
                        <span class="mjc-note">saved with the contract, never on its own</span>
                    </div>

                    @if (!Picked) {
                        <div style="background:var(--mj-bg-surface); border:1px solid var(--mj-brand-primary); border-radius:var(--mj-radius-md); overflow:hidden">
                            <div style="display:flex; align-items:center; gap:var(--mj-space-2); padding:var(--mj-space-3); border-bottom:1px solid var(--mj-border-default)">
                                <i class="fa-solid fa-magnifying-glass mjc-muted" aria-hidden="true"></i>
                                <input type="text" style="flex:1" [ngModel]="Search" (ngModelChange)="Search = $event"
                                       placeholder="Search provisions…" aria-label="Search provisions" />
                            </div>
                            <div style="padding:var(--mj-space-2) var(--mj-space-3); background:var(--mj-color-brand-50); color:var(--mj-color-brand-900); font-size:var(--mj-text-xs); border-bottom:1px solid var(--mj-color-brand-100)">
                                Showing provisions of <strong>{{ TemplateName }}</strong> only — the version this
                                contract incorporates.
                            </div>
                            <div style="max-height:22rem; overflow-y:auto">
                                @for (p of FilteredProvisions; track p.ID) {
                                    <div style="display:flex; gap:var(--mj-space-3); padding:var(--mj-space-3); border-bottom:1px solid var(--mj-color-neutral-100); cursor:pointer"
                                         (click)="Pick(p)">
                                        <div class="mjc-mono" style="flex:none; width:4.5rem">{{ p.ProvisionNumber }}</div>
                                        <div style="flex:1; min-width:0">
                                            <div style="font-weight:700">{{ p.Title }}</div>
                                            @if (Expanded[p.ID]) {
                                                <p class="mjc-clause">{{ p.ProvisionText || '(no text captured)' }}</p>
                                            }
                                            <button type="button" class="mjc-toggle" (click)="ToggleProvision(p); $event.stopPropagation()">
                                                {{ Expanded[p.ID] ? 'hide standard text ⌃' : 'show standard text ⌄' }}
                                            </button>
                                        </div>
                                    </div>
                                }
                                @if (!FilteredProvisions.length) {
                                    <div class="mjc-empty" style="border:0; background:transparent">
                                        No provision matches “{{ Search }}”.
                                    </div>
                                }
                            </div>
                        </div>
                    } @else {
                        <div class="mjc-fields">
                            <div class="mjc-field">
                                <label>Provision</label>
                                <div class="mjc-val">
                                    <strong class="mjc-mono">{{ Picked.ProvisionNumber }}</strong> — {{ Picked.Title }}
                                </div>
                            </div>
                            <div class="mjc-field">
                                <label>Notes (optional)</label>
                                <input type="text" style="width:100%" [ngModel]="DraftNotes" (ngModelChange)="DraftNotes = $event"
                                       placeholder="e.g. who negotiated it" aria-label="Notes" />
                            </div>
                        </div>

                        <div class="mjc-field">
                            <label>Standard text — read-only, from the provision</label>
                            <p class="mjc-clause">{{ Picked.ProvisionText || '(no text captured for this provision)' }}</p>
                        </div>

                        <div class="mjc-field">
                            <label>Modified text — as this contract states it</label>
                            <textarea class="mjc-clause mjc-clause--mod" rows="8" style="width:100%"
                                      [ngModel]="DraftText" (ngModelChange)="DraftText = $event"
                                      aria-label="The negotiated language"></textarea>
                            <div class="mjc-hint">
                                Pre-filled from the standard text so the negotiated version is <strong>edited, not
                                retyped</strong>.
                            </div>
                        </div>

                        <div style="display:flex; gap:var(--mj-space-2)">
                            <button type="button" class="mjc-btn mjc-btn--sm" (click)="CancelAdd()">Cancel</button>
                            <button type="button" class="mjc-btn mjc-btn--primary mjc-btn--sm"
                                    (click)="Commit()" [disabled]="!DraftText.trim()">Add to list</button>
                            <button type="button" class="mjc-btn mjc-btn--flat mjc-btn--sm" (click)="Picked = null">
                                Choose a different provision
                            </button>
                        </div>
                    }
                </div>
            }
        }
    `,
})
export class MJCModificationEditorComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);

    @Input() Record?: ContractEntity;
    @Input() EditMode = false;
    @Input() SingleRowMode = false;
    @Input() OnlyModificationID: string | null = null;
    /** D-25: whichever host mounts this passes its provider; falls back to the ambient one. */
    @Input() Provider?: IMetadataProvider | null;
    @Output() Changed = new EventEmitter<void>();

    public Provisions: ProvisionOption[] = [];
    public LoadError: string | null = null;

    /** Add-flow state. `Picked === null` means the picker is showing. */
    public Adding = false;
    public Picked: ProvisionOption | null = null;
    public Search = '';
    public DraftText = '';
    public DraftNotes = '';
    public Expanded: Record<string, boolean> = {};

    /** Which existing rows are expanded, keyed by row identity. */
    private openRows = new Set<string>();

    public async ngOnInit(): Promise<void> {
        await this.ensureLoaded();
        await this.loadProvisions();
    }

    /** The template version this contract incorporates, for the scope banner. */
    public get TemplateName(): string {
        return this.Record?.ContractTemplate ?? '';
    }

    /**
     * Rows to render, each paired with its provision so the table can show the clause without a lookup
     * per cell. In single-row mode only the one row the host form is editing.
     */
    public get Rows(): Array<{
        mod: mjBizAppsContractsContractTemplateModificationEntity;
        provision: ProvisionOption | undefined;
        open: boolean;
    }> {
        let items = [...(this.Record?.Modifications?.Items ?? [])];
        if (this.SingleRowMode && this.OnlyModificationID) {
            items = items.filter((m) => m.ID === this.OnlyModificationID);
        }
        return items.map((mod, i) => {
            const key = mod.ID ?? `new-${i}`;
            return {
                mod,
                provision: mod.ContractTemplateProvisionID
                    ? this.Provisions.find((p) => p.ID === mod.ContractTemplateProvisionID)
                    : undefined,
                // In single-row mode the point IS the text, so it opens by default.
                open: this.SingleRowMode || this.openRows.has(key),
            };
        });
    }

    public ToggleRow(row: { mod: mjBizAppsContractsContractTemplateModificationEntity }): void {
        if (this.SingleRowMode) return;
        const key = row.mod.ID ?? `new-${this.Rows.indexOf(row as never)}`;
        if (this.openRows.has(key)) this.openRows.delete(key);
        else this.openRows.add(key);
        this.cdr.detectChanges();
    }

    /** Provisions matching the search box — number, title or text. */
    public get FilteredProvisions(): ProvisionOption[] {
        const q = this.Search.trim().toLowerCase();
        if (!q) return this.Provisions;
        return this.Provisions.filter(
            (p) =>
                p.ProvisionNumber.toLowerCase().includes(q) ||
                p.Title.toLowerCase().includes(q) ||
                (p.ProvisionText ?? '').toLowerCase().includes(q),
        );
    }

    public ToggleProvision(p: ProvisionOption): void {
        this.Expanded = { ...this.Expanded, [p.ID]: !this.Expanded[p.ID] };
    }

    public StartAdd(): void {
        this.Adding = true;
        this.Picked = null;
        this.Search = '';
        this.DraftNotes = '';
        this.DraftText = '';
    }

    public CancelAdd(): void {
        this.Adding = false;
        this.Picked = null;
    }

    /**
     * Choose a provision — and PRE-FILL the modified text from its standard clause.
     *
     * This is the mockup's key detail. A blank box asks a person to retype a 1,100-character clause to
     * change four words; in practice they would paraphrase, and a paraphrased clause sitting next to the
     * real one is precisely the failure this app exists to prevent. Pre-filling makes the negotiated
     * version an EDIT of the standard, which is also what it is in the paper.
     */
    public Pick(p: ProvisionOption): void {
        this.Picked = p;
        this.DraftText = p.ProvisionText ?? '';
        this.cdr.detectChanges();
    }

    /**
     * Stage the row on the collection. Nothing is saved — the form's Save toolbar drives one
     * `contract.Save()`, so the header and its modifications commit together or not at all.
     */
    public async Commit(): Promise<void> {
        const collection = this.Record?.Modifications;
        if (!collection || !this.Record || !this.Picked) return;
        const m = await collection.Create();
        m.ContractTemplateProvisionID = this.Picked.ID;
        m.ModificationText = this.DraftText;
        if (this.DraftNotes.trim()) m.Notes = this.DraftNotes.trim();
        // The first modification sets the parent flag in the SAME graph — otherwise the shared
        // Validate() refuses the save, which is the invariant working, not an obstacle.
        this.Record.HasModifications = true;
        this.Adding = false;
        this.Picked = null;
        this.Changed.emit();
        this.cdr.detectChanges();
    }

    /**
     * Remove a row — deleted on save (`OnRemove: 'delete'`).
     *
     * `HasModifications` is NOT cleared even when this empties the list: the flag is monotonic by rule
     * (ERD §4.4). Its job is to say "the paper differs, go read it", which can be true before anything is
     * recorded and stays true after a mistaken row is removed.
     */
    public Remove(mod: mjBizAppsContractsContractTemplateModificationEntity): void {
        this.Record?.Modifications?.Remove(mod);
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

    /**
     * Load the collection if it can hold rows and has not been read. `Load: 'explicit'` means nothing
     * fetches it for us — deliberate, so a contract list does not drag every modification along.
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
     * The provisions this contract may modify — its template's, and only its template's (ERD §7.1).
     *
     * One read at bind time. §6.6 rules that provisions belong in the reference-data cache precisely so
     * this is not a `RunView` per row; until that engine exists this has the same effect for the user and
     * is honest about not being the cache yet.
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
}
