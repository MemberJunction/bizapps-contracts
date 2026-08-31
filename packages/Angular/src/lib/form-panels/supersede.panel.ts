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

interface Candidate { ID: string; ContractNumber: string; ContractType: string; Label: string }

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

            <!-- Mirrors mj-form-field's own markup (mj-forms-field / -label / -control / -value) so this
                 reads as an ordinary form line. It cannot BE an mj-form-field: that binds to a field on
                 THIS record, and the supersession FK lives on the predecessor. -->
            <div class="mj-forms-field">
                <label class="mj-forms-field-label">Supersedes</label>
                <div class="mj-forms-field-control">

                    <!-- AVAILABLE WHEN NOT EDITING, unavailable while editing (Marcelo, 2026-08-21).
                         Inverted from the usual field pattern on purpose: this control does not edit a
                         field on THIS record, it writes the OTHER contract. It therefore needs this
                         contract SAVED - a predecessor cannot point at a row that does not exist yet -
                         and an in-progress edit is exactly when that is not true. So while the form is
                         dirty/editing it shows the value read-only, and the picker returns when the
                         edit is finished. -->
                    @if (EditMode || !Record?.IsSaved) {
                        <span class="mj-forms-field-value">
                            @if (Supersedes.length) {
                                @for (p of Supersedes; track p.ID) {
                                    {{ p.ContractNumber }}{{ $last ? '' : ', ' }}
                                }
                            } @else {
                                —
                            }
                            <span class="mjc-chip mjc-chip--muted">
                                {{ Record?.IsSaved ? 'finish editing to change this' : 'save this contract first' }}
                            </span>
                        </span>
                    } @else {
                        <mj-combobox
                            [Data]="Candidates"
                            TextField="Label"
                            ValueField="ID"
                            [ValuePrimitive]="true"
                            [Filterable]="true"
                            [Disabled]="Busy"
                            Placeholder="Search contracts at this level…"
                            [(ngModel)]="PickedPredecessorID" />

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

                        <div class="mjc-hint">
                            Link writes the OTHER contract - it marks the one you pick as superseded by this
                            agreement - so Save cannot do it: Save only writes this record.
                        </div>

                        @if (LoadError) { <mj-alert Variant="warning" Size="sm" [Message]="LoadError" /> }
                        @if (LinkError) { <mj-alert Variant="error" Size="sm" [Message]="LinkError" /> }
                        @if (LinkOk) { <mj-alert Variant="success" Size="sm" [Message]="LinkOk" /> }
                        @if (!Candidates.length && !CandidatesLoading && !LoadError) {
                            <div class="mjc-hint">
                                Nothing eligible: a predecessor must sit at the same level as this contract and
                                must not already be superseded.
                            </div>
                        }
                    }
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
    private loaded = false;

    /** Eligible predecessors. Loaded on first read; no EditMode gate, because the panel is always shown. */
    public get Candidates(): Candidate[] {
        if (!this.loaded && this.Record?.ID) { this.loaded = true; void this.load(); }
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
    public async LinkSupersedes(): Promise<void> {
        await this.invoke(this.PickedPredecessorID || null, 'Linked — that contract is now superseded by this agreement.');
    }

    /** Release one predecessor. `null` predecessor = release everything. */
    public async UnlinkSupersedes(_predecessorID: string): Promise<void> {
        await this.invoke(null, 'Unlinked — that agreement is no longer superseded by this one.');
    }

    private async invoke(predecessorID: string | null, okMessage: string): Promise<void> {
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
                { SuccessorID: string; PredecessorID: string | null },
                { Supersedes: Array<{ ID: string; ContractNumber: string }>; Released: string[]; Refused?: string }
            >(SUPERSEDE_OP, { SuccessorID: this.Record.ID, PredecessorID: predecessorID });

            if (!result?.Success) {
                throw new Error(result?.ErrorMessage || 'The server did not complete the request.');
            }
            const out = result.Output;
            // Trust the server's list over anything this panel believed.
            this.Supersedes = out?.Supersedes ?? [];
            if (out?.Refused) {
                this.LinkError = out.Refused;
            } else {
                this.LinkOk = okMessage + (out?.Released?.length ? ` Released ${out.Released.join(', ')}.` : '');
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

    /** Eligible predecessors: same level, not already superseded, not this contract. */
    private async loadCandidates(): Promise<void> {
        const me = this.Record!.ID;
        const { ScopedRunView } = await import('../data/provider');
        const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
        this.CandidatesLoading = true;
        try {
            const parentID = this.Record?.ParentContractID ?? null;
            const sameLevel = parentID === null ? 'ParentContractID IS NULL' : `ParentContractID = '${parentID}'`;
            const r = await rv.RunView<{ ID: string; ContractNumber: string; ContractType: string }>({
                EntityName: MJC_ENTITIES.Contract,
                Fields: ['ID', 'ContractNumber', 'ContractType'],
                ExtraFilter: `${sameLevel} AND SupersededByContractID IS NULL AND ID <> '${me}'`,
                OrderBy: 'ContractNumber ASC',
                ResultType: 'simple',
            });
            this._candidates = (r?.Success ? r.Results : []).map((c) => ({
                ...c,
                Label: `${c.ContractNumber} — ${c.ContractType ?? 'Contract'}`,
            }));
        } catch (e) {
            // Do NOT swallow this. An empty list and a failed read look identical in the UI, and the
            // difference is the whole diagnosis — an earlier version returned [] here and the picker
            // simply sat greyed out with nothing to explain it.
            this._candidates = [];
            this.LoadError = `Could not read eligible contracts: ${e instanceof Error ? e.message : String(e)}`;
            this.loaded = false; // let the next read retry
        } finally {
            this.CandidatesLoading = false;
            this.cdr.detectChanges();
        }
    }
}
