/**
 * @fileoverview Re-papering — "this agreement supersedes …" — as a FIELD panel, not a related one.
 *
 * WHY IT LIVES HERE AND NOT ON LINEAGE. It started on the Lineage panel, which is where the
 * supersession FACTS belong. But Lineage has to be a rail item, a rail item needs
 * `Variant="related-entity"`, and that variant renders any non-AG-Grid child completely blank
 * (MJ#3999) — so the picker was present in the DOM and invisible. Rather than fight the variant,
 * the control moved to a plain field panel in the Details group, which has no such constraint.
 * Lineage keeps the tree and the read-only facts.
 *
 * ALWAYS VISIBLE, not gated on EditMode (Marcelo, 2026-08-21). Re-papering is a deliberate act with
 * its own confirm button that writes another record in its own save — it is not one of the form's
 * fields, so hiding it until the form happens to be in edit mode only made it hard to find. Its
 * button is what commits, so showing it in read mode changes nothing until pressed.
 *
 * THE DIRECTION, restated because it is the whole reason this panel is odd: the FK lives on the
 * PREDECESSOR (`SupersededByContractID`), which is correct — one column there makes "superseded at
 * most once" structurally true and keeps `Superseded` derivable from a column the base view already
 * projects. The cost is exactly this: the successor's form reaches over and writes another record.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import { MJComboboxComponent, MJButtonDirective, MJAlertComponent } from '@memberjunction/ng-ui-components';
import type { IRemoteOperationProvider } from '@memberjunction/core';
import { ContractEntity } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';

/** The server-side operation key. One place, because RouteOperation is stringly typed. */
const SUPERSEDE_OP = 'Contracts.Supersede';

interface Candidate {
    ID: string;
    ContractNumber: string;
    ContractType: string;
    Description: string | null;
    Label: string;
}

@RegisterClassEx(BaseFormPanel, {
    key: 'contracts:supersede',
    skipNullKeyWarning: true,
    metadata: {
        entity: MJC_ENTITIES.Contract,
        // `after-fields` puts this in the FIELD-panel band, which the left-nav chrome collapses into
        // the single "Details" rail item (FORMS_ARCHITECTURE_GUIDE §7d). That is deliberate: it is a
        // property of this agreement, and it avoids the related-entity variant entirely.
        slot: 'after-fields',
        sortKey: 40,
        contributionKey: 'supersede',
        relatedEntity: MJC_ENTITIES.Contract,
        relatedJoinField: 'SupersededByContractID',
    },
})
@Component({
    selector: 'mjc-contract-supersede-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule, BaseFormsModule, MJComboboxComponent, MJButtonDirective, MJAlertComponent],
    template: `
        <mj-collapsible-panel
            SectionKey="supersede"
            SectionName="Re-papering"
            Icon="fa-solid fa-arrow-right-arrow-left"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            <!-- The KIT's field markup (.mjc-fields / .mjc-field / .mjc-val), not MJ's
                 mj-forms-field. Both render a form line; the kit's is the one every other custom panel
                 on this form uses, and mixing the two put a differently-sized, differently-cased label
                 next to the Dates and Renewal ones (issue #28 item 3). It cannot be a real
                 mj-form-field either way: that binds to a field on THIS record, and the supersession FK
                 lives on the predecessor. -->
            <div class="mjc-body">
                <div class="mjc-fields">
                    <div class="mjc-field">
                        <label>Supersedes</label>

                        <!-- AVAILABLE WHEN NOT EDITING, unavailable while editing (Marcelo, 2026-08-21).
                             Inverted from the usual field pattern on purpose: this control does not edit a
                             field on THIS record, it writes the OTHER contract. It therefore needs this
                             contract SAVED - a predecessor cannot point at a row that does not exist yet -
                             and an in-progress edit is exactly when that is not true. So while the form is
                             dirty/editing it shows the value read-only, and the picker returns when the
                             edit is finished. -->
                        @if (EditMode || !Record?.IsSaved) {
                            <div class="mjc-val">
                                @if (Supersedes.length) {
                                    @for (p of Supersedes; track p.ID) {
                                        {{ p.ContractNumber }}{{ $last ? '' : ', ' }}
                                    }
                                } @else {
                                    —
                                }
                                <span class="mjc-chip mjc-chip--muted">
                                    {{ Record?.IsSaved ? 'Finish editing to change' : 'Save this contract first' }}
                                </span>
                            </div>
                        } @else {
                            <mj-combobox
                                [Data]="Candidates"
                                TextField="Label"
                                ValueField="ID"
                                [ValuePrimitive]="true"
                                [Filterable]="true"
                                [Disabled]="Busy"
                                [Placeholder]="PickerPlaceholder"
                                [ngModel]="PickedPredecessorID"
                                (ngModelChange)="PickPredecessor($event)" />

                            <div class="mjc-field__actions">
                                <button mjButton variant="primary" size="sm" type="button"
                                        [disabled]="Busy || !PickedPredecessorID"
                                        (click)="LinkSupersedes()">
                                    {{ Busy ? 'Linking…' : 'Link' }}
                                </button>

                                @for (p of Supersedes; track p.ID) {
                                    <button mjButton variant="flat" size="sm" type="button" [disabled]="Busy"
                                            (click)="UnlinkSupersedes(p.ID)"
                                            [attr.aria-label]="'Stop superseding ' + p.ContractNumber">
                                        Unlink {{ p.ContractNumber }}
                                    </button>
                                }
                            </div>

                            @if (LoadError) { <mj-alert Variant="warning" Size="sm" [Message]="LoadError" /> }
                            @if (LinkError) { <mj-alert Variant="error" Size="sm" [Message]="LinkError" /> }
                            @if (LinkOk) { <mj-alert Variant="success" Size="sm" [Message]="LinkOk" /> }
                        }
                    </div>
                </div>
            </div>
        </mj-collapsible-panel>
    `,
})
export class MJCContractSupersedePanel extends BaseFormPanel<ContractEntity> {
    private readonly cdr = inject(ChangeDetectorRef);

    public PickedPredecessorID = '';
    public Busy = false;
    public LinkError = '';
    /** Confirmation, so a working link is never indistinguishable from a silent no-op. */
    public LinkOk = '';
    public CandidatesLoading = false;
    /** Why the candidate list is empty, when the reason is a failure rather than genuinely nothing. */
    public LoadError = '';
    public Supersedes: Array<{ ID: string; ContractNumber: string }> = [];

    private _candidates: Candidate[] = [];
    /**
     * WHICH contract the candidate list was loaded for, not merely whether it was (issue #28 item 23).
     *
     * A boolean belongs to the panel, and the panel outlives the record: the form reuses the same
     * component instance when it navigates to another contract, so the flag stayed true and the picker
     * went on offering the PREVIOUS contract's candidates — filtered to the previous customer and the
     * previous level, which is a wrong list rather than a stale one.
     */
    private loadedFor: string | null = null;

    /**
     * What the combobox says when it is not showing options.
     *
     * REPLACES A PARAGRAPH (issue #28 item 2). An empty picker used to be explained by a block of
     * `.mjc-hint` prose underneath it — "Nothing eligible: a predecessor must sit at the same level…" —
     * which is a rule restated at the reader rather than an answer. The control itself is where a
     * person looks when it offers nothing, so the answer goes there and the paragraph is gone.
     */
    public get PickerPlaceholder(): string {
        if (this.CandidatesLoading) return 'Loading…';
        return this.Candidates.length ? 'Search contracts for this customer…' : 'No eligible contracts';
    }

    /** Eligible predecessors. Loaded on first read; no EditMode gate, because the panel is always shown. */
    public get Candidates(): Candidate[] {
        const id = this.Record?.ID;
        if (id && this.loadedFor !== id) { this.loadedFor = id; void this.load(); }
        return this._candidates;
    }

    /**
     * Re-paper: ask the SERVER to point this agreement at the contract it replaces.
     *
     * WHY AN OPERATION AND NOT ENTITY CALLS FROM HERE. The write targets a different record — the FK
     * lives on the predecessor — so this panel used to load and save a foreign contract itself, which
     * is server work done in the client. It also could not work: in the browser MJ resolves the
     * CodeGen-generated entity class rather than the app subclass, so `ContractEntity.Supersede()` is
     * absent client-side (MJ#4002). Server-side the app subclass resolves correctly and every rule in
     * `ContractEntityServer.ValidateAsync()` actually runs.
     *
     * `RouteOperation` rather than a generated typed client: the server resolves an operation purely
     * from the ClassFactory by key, so no `MJ: Remote Operations` metadata row and no CodeGen file run
     * is needed for this to work. The trade is a stringly-typed key, kept in one place below.
     *
     * The operation RETURNS the live list, which is what fixes the stale Unlink button: this panel no
     * longer maintains its own cached idea of what the contract supersedes.
     */
    /**
     * Take a new selection, and drop the outcome of the last one.
     *
     * A `[(ngModel)]` two-way binding was enough to hold the value and is not enough here: the
     * success and error banners sat until the next click, so "Linked — that contract is now superseded
     * by this agreement." stayed on screen while the user picked a DIFFERENT contract, appearing to
     * describe the new selection. A stale success is worse than no message; it reports an action
     * nobody took.
     */
    public PickPredecessor(id: string): void {
        this.PickedPredecessorID = id ?? '';
        this.LinkOk = '';
        this.LinkError = '';
    }

    public async LinkSupersedes(): Promise<void> {
        if (!this.PickedPredecessorID) return;
        await this.invoke(
            { PredecessorID: this.PickedPredecessorID },
            'Linked — that contract is now superseded by this agreement.',
        );
    }

    /**
     * Release the ONE predecessor whose button was clicked.
     *
     * The argument used to be discarded and the operation called with `PredecessorID: null`, which the
     * server read as "release every predecessor" — so unlinking one of three unlinked all three
     * (issue #28 item 9). The ID now reaches the server as `ReleasePredecessorID`, which names a
     * single record and refuses anything this agreement does not actually supersede.
     */
    public async UnlinkSupersedes(predecessorID: string): Promise<void> {
        if (!predecessorID) return;
        await this.invoke(
            { ReleasePredecessorID: predecessorID },
            'Unlinked — that agreement is no longer superseded by this one.',
        );
    }

    private async invoke(
        target: { PredecessorID?: string; ReleasePredecessorID?: string },
        okMessage: string,
    ): Promise<void> {
        if (!this.Record?.ID) return;
        this.Busy = true;
        this.LinkError = '';
        this.LinkOk = '';
        try {
            const { Metadata } = await import('@memberjunction/core');
            // RouteOperation is declared on IRemoteOperationProvider, not IMetadataProvider — the same
            // narrowing BaseRemotableOperation.Execute() does before calling it.
            const provider = (this.FormComponent?.ProviderToUse ?? Metadata.Provider) as unknown as IRemoteOperationProvider;
            if (typeof provider?.RouteOperation !== 'function') {
                throw new Error('This provider cannot route remote operations, so re-papering is unavailable here.');
            }
            const result = await provider.RouteOperation<
                { SuccessorID: string; PredecessorID?: string; ReleasePredecessorID?: string },
                { Supersedes: Array<{ ID: string; ContractNumber: string }>; Released: string[]; Refused?: string }
            >(SUPERSEDE_OP, { SuccessorID: this.Record.ID, ...target });

            if (!result?.Success) {
                throw new Error(result?.ErrorMessage || 'The server did not complete the request.');
            }
            const out = result.Output;
            // Trust the server's list over anything this panel believed.
            this.Supersedes = out?.Supersedes ?? [];
            if (out?.Refused) {
                this.LinkError = out.Refused;
            } else {
                this.LinkOk = okMessage;
                this.PickedPredecessorID = '';
            }
            await this.loadCandidates();
        } catch (e) {
            this.LinkError = e instanceof Error ? e.message : String(e);
        } finally {
            this.Busy = false;
            this.cdr.detectChanges();
        }
    }

    /**
     * What this contract already replaces, and what it may replace.
     *
     * The same-level predicate is written two ways because `ParentContractID = NULL` matches nothing in
     * SQL: a top-level contract's peers need `IS NULL`, a child's need an equality. Getting that wrong
     * silently offers an empty list to every root contract, which is most of them.
     *
     * This mirrors `refuseCrossLevelSupersession` on the server but does not replace it: this decides
     * what to OFFER, the server decides what is ALLOWED, and if they disagree the server wins.
     */
    private async load(): Promise<void> {
        await this.loadSupersedes();
        await this.loadCandidates();
    }

    /** What this contract already replaces. Read live; the operation also returns it after a write. */
    private async loadSupersedes(): Promise<void> {
        const me = this.Record!.ID;
        const { ScopedRunView } = await import('../data/provider');
        const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
        this.CandidatesLoading = true;
        try {
            const mine = await rv.RunView<{ ID: string; ContractNumber: string }>({
                EntityName: MJC_ENTITIES.Contract,
                Fields: ['ID', 'ContractNumber'],
                ExtraFilter: `SupersededByContractID = '${me}'`,
                OrderBy: 'ContractNumber ASC',
                ResultType: 'simple',
            });
            this.Supersedes = mine?.Success ? mine.Results : [];
        } catch {
            this.Supersedes = [];
        }
    }

    /**
     * Eligible predecessors: SAME CUSTOMER, same level, not already superseded, not this contract.
     *
     * The same-customer rule is the one added for issue #28 item 4, and it is the rule that makes the
     * list mean something: re-papering replaces one customer's agreement with a later agreement for
     * that same customer, so every other customer's contracts were noise the reader had to filter by
     * eye. `refuseCrossCustomerSupersession` on the server enforces it — this only decides what to
     * OFFER, and if the two ever disagree the server wins.
     */
    private async loadCandidates(): Promise<void> {
        const me = this.Record!.ID;
        const customerID = this.Record?.CustomerOrganizationID;
        const { ScopedRunView } = await import('../data/provider');
        const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
        this.CandidatesLoading = true;
        try {
            // No customer means an unsaved or half-built record; offering every contract in the
            // database would be worse than offering none.
            if (!customerID) {
                this._candidates = [];
                return;
            }
            const parentID = this.Record?.ParentContractID ?? null;
            const sameLevel = parentID === null ? 'ParentContractID IS NULL' : `ParentContractID = '${parentID}'`;
            const r = await rv.RunView<{
                ID: string; ContractNumber: string; ContractType: string; Description: string | null;
            }>({
                EntityName: MJC_ENTITIES.Contract,
                Fields: ['ID', 'ContractNumber', 'ContractType', 'Description'],
                ExtraFilter:
                    `CustomerOrganizationID = '${customerID}' AND ${sameLevel} ` +
                    `AND SupersededByContractID IS NULL AND ID <> '${me}'`,
                OrderBy: 'ContractNumber ASC',
                ResultType: 'simple',
            });
            this._candidates = (r?.Success ? r.Results : []).map((c) => ({
                ...c,
                // `<number> — <description>`, because the number alone identifies nothing to a reader
                // choosing between three of them. Type is the fallback, not the default: it is the same
                // word on most of the list, so it distinguishes contracts only when nothing else can.
                Label: `${c.ContractNumber} — ${c.Description?.trim() || c.ContractType || 'Contract'}`,
            }));
            // A later success must clear an earlier failure's banner, or the warning outlives the
            // problem and the panel accuses itself of being broken while working (item 23, in part).
            this.LoadError = '';
        } catch (e) {
            // Do NOT swallow this. An empty list and a failed read look identical in the UI, and the
            // difference is the whole diagnosis — an earlier version returned [] here and the picker
            // simply sat greyed out with nothing to explain it.
            this._candidates = [];
            this.LoadError = `Could not read eligible contracts: ${e instanceof Error ? e.message : String(e)}`;
            this.loadedFor = null; // let the next read retry
        } finally {
            this.CandidatesLoading = false;
            this.cdr.detectChanges();
        }
    }
}
