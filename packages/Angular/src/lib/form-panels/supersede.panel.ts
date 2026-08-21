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
import { ContractEntity } from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';

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
    },
})
@Component({
    selector: 'mjc-contract-supersede-panel',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, FormsModule, BaseFormsModule, MJComboboxComponent, MJButtonDirective, MJAlertComponent],
    template: `
        <mj-collapsible-panel
            SectionKey="contractSupersede"
            SectionName="Re-papering"
            Icon="fa-solid fa-arrow-right-arrow-left"
            [Form]="FormComponent"
            [FormContext]="FormContext">

            <!-- WHAT REPLACED THIS ONE. Read-only, and a plain field line rather than a callout: it is
                 simply the value of this record's own SupersededByContractID, shown by name. Moved here
                 from the Lineage panel (Marcelo, 2026-08-21) so both directions of the re-papering
                 relationship read side by side in Details - what replaced this, and what this replaced. -->
            @if (SupersededBy) {
                <div class="mj-forms-field">
                    <label class="mj-forms-field-label">Superseded by</label>
                    <div class="mj-forms-field-control">
                        <span class="mj-forms-field-value">
                            {{ SupersededBy }}
                            <span class="mjc-chip mjc-chip--muted">this agreement's terms no longer govern</span>
                        </span>
                    </div>
                </div>
            }

            <!-- Mirrors mj-form-field's own markup (mj-forms-field / -label / -control / -value) so this
                 reads as an ordinary form line. It cannot BE an mj-form-field: that binds to a field on
                 THIS record, and the supersession FK lives on the predecessor. -->
            <div class="mj-forms-field">
                <label class="mj-forms-field-label">Supersedes</label>
                <div class="mj-forms-field-control">

                    @if (!EditMode) {
                        <span class="mj-forms-field-value">
                            @if (Supersedes.length) {
                                @for (p of Supersedes; track p.ID) {
                                    {{ p.ContractNumber }}{{ $last ? '' : ', ' }}
                                }
                            } @else {
                                —
                            }
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

    /**
     * The successor's NUMBER, from the generated virtual FK-name field rather than the id.
     *
     * ⚠ Known to go stale within one edit session: MJ's FK picker writes a read-only joined name field
     * only ONCE and silently drops later writes (MJ#3996), so changing the successor twice before
     * saving leaves the first name on screen. A save-and-reload corrects it.
     */
    public get SupersededBy(): string { return this.Record?.SupersededByContract ?? ''; }

    public PickedPredecessorID = '';
    public Busy = false;
    public LinkError = '';
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
     * Point this agreement at the contract it replaces — and UN-point whichever it replaced before.
     *
     * REPLACE, NOT ADD, and the distinction is load-bearing. The schema deliberately permits MANY
     * predecessors to name one successor (three order forms consolidating into one master), so simply
     * setting the new predecessor would leave the old one still pointing here and this agreement would
     * silently supersede BOTH. That is a legal state in the model and the wrong one for a user who just
     * changed their mind in a single-select control. So: clear the previous, set the new.
     *
     * If genuine consolidation is ever wanted, it needs a multi-select, not this combobox — the control
     * is what decides the semantics here, and a single-select means one predecessor.
     *
     * ORDER: unlink first, then link. Not one transaction (a TransactionGroup defers writes until
     * Submit(), so the predecessor would validate against a successor with an ID and no row, and the
     * level guard could not tell an unwritten sibling from a bad reference). The failure modes are
     * therefore visible rather than silent, and each is reported with what actually landed:
     *   · unlink fails      -> nothing changed
     *   · unlink ok, link fails -> the old link is gone and the new one is not set; the panel reloads
     *     showing "Supersedes -" so the state on screen is true, and the user can pick again.
     */
    public async LinkSupersedes(): Promise<void> {
        const predecessorID = this.PickedPredecessorID;
        if (!predecessorID || !this.Record) return;
        this.Busy = true;
        this.LinkError = '';
        try {
            const { Metadata } = await import('@memberjunction/core');
            const provider = this.FormComponent?.ProviderToUse ?? Metadata.Provider;

            // The successor must exist before anything can point at it.
            if (this.Record.Dirty || !this.Record.IsSaved) {
                if (!(await this.Record.Save())) {
                    throw new Error(this.Record.LatestResult?.Message ?? 'This contract could not be saved, so nothing was superseded.');
                }
            }

            // Release any predecessor this agreement already replaces, except the one just chosen —
            // re-picking the same contract must not clear and re-set it.
            for (const previous of this.Supersedes) {
                if (previous.ID.toLowerCase() === predecessorID.toLowerCase()) continue;
                if (!(await this.setSuccessor(provider, previous.ID, null))) {
                    throw new Error(
                        `Could not release ${previous.ContractNumber}, so nothing was changed. ` +
                            `It is still recorded as superseded by this agreement.`,
                    );
                }
            }

            if (!(await this.setSuccessor(provider, predecessorID, this.Record.ID))) {
                throw new Error(
                    `Could not mark that contract superseded. Any previous link was already released, ` +
                        `so this agreement now supersedes nothing — pick a contract and try again.`,
                );
            }

            this.PickedPredecessorID = '';
            await this.load();
        } catch (e) {
            this.LinkError = e instanceof Error ? e.message : String(e);
            await this.load(); // whatever the DB now says, show THAT rather than the optimistic view
        } finally {
            this.Busy = false;
            this.cdr.detectChanges();
        }
    }

    /**
     * Set (or clear) one contract's successor FK. Returns false with the entity's own reason left on
     * `LinkError` when the server refuses — the level guard's message is far more useful than "failed".
     */
    private async setSuccessor(provider: { GetEntityObject: <T>(n: string) => Promise<T> }, contractID: string, successorID: string | null): Promise<boolean> {
        const target = await provider.GetEntityObject<ContractEntity>(MJC_ENTITIES.Contract);
        if (!(await target.Load(contractID))) return false;
        if (successorID === null) {
            target.SupersededByContractID = null;
        } else {
            // Supersede() carries the intent-setter's own guards (saved, not self) rather than a bare
            // field write, so the entity keeps owning the rule.
            target.Supersede(this.Record!);
        }
        if (await target.Save()) return true;
        const why = target.LatestResult?.Message;
        if (why) this.LinkError = why;
        return false;
    }

    /** Undo a re-papering. Left available deliberately — supersedes is unlocked for now. */
    public async UnlinkSupersedes(predecessorID: string): Promise<void> {
        this.Busy = true;
        this.LinkError = '';
        try {
            const { Metadata } = await import('@memberjunction/core');
            const provider = this.FormComponent?.ProviderToUse ?? Metadata.Provider;
            if (!(await this.setSuccessor(provider, predecessorID, null))) {
                throw new Error(this.LinkError || 'Could not unlink. Nothing was changed.');
            }
            await this.load();
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
