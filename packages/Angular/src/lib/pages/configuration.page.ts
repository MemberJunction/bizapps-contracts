/**
 * @fileoverview Configuration — the small vocabularies every contract inherits (item 6).
 *
 * MOSTLY FREE, AND THAT IS THE DESIGN. The generated entity forms already cover creating and editing a
 * contract type or a template type; what was missing was a place to FIND them. So these pages are
 * grids over the generated base views plus one sentence of context each — no custom form, no bespoke
 * editor. Item 6's "done" is "confirm each generated form opens clean", not "build CRUD".
 *
 * The sentences matter more than they look. `RequiresExecutedDocument` is the only rule column in the
 * whole app, and a business user retiring a type by flipping `Status` needs to know old contracts keep
 * resolving. Neither fact is visible from a grid of columns.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, OnInit, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import type { RunViewParams } from '@memberjunction/core';
import { ExplorerEntityDataGridComponent } from '@memberjunction/ng-base-forms';
import { MJC_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';

/** Shared skeleton: one intro sentence, one stock grid. */
@Component({ template: '' })
abstract class MJCConfigPageBase implements OnInit {
    protected readonly cdr = inject(ChangeDetectorRef);
    public Params: RunViewParams | null = null;

    protected abstract get entityName(): string;
    protected get orderBy(): string {
        return 'Name ASC';
    }

    public ngOnInit(): void {
        this.Params = { EntityName: this.entityName, OrderBy: this.orderBy };
        this.cdr.detectChanges();
    }
}

const CONFIG_TEMPLATE = `
    <div class="mjc-page">
        <p class="mjc-page__intro"><ng-content /></p>
        <mj-explorer-entity-data-grid [Params]="Params" [ShowToolbar]="true" [NavigateOnDoubleClick]="true" />
    </div>
`;

@Component({
    selector: 'mjc-contract-types-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, ExplorerEntityDataGridComponent],
    template: `
        <div class="mjc-page">
            <p class="mjc-page__intro">
                What kind of document a contract is. One column here carries a rule:
                <strong>Requires Executed Document</strong> is what makes a contract appear on the
                <em>Awaiting documents</em> worklist, so a Payment Link — where nobody signs anything —
                never reports as missing paper. Everything else about a type is a label.
            </p>
            <p class="mjc-page__intro">
                Retire a type by setting its <strong>Status</strong> to <em>Inactive</em> rather than
                deleting it: it stops being offered for new contracts, and every contract already
                referencing it keeps resolving.
            </p>
            <mj-explorer-entity-data-grid [Params]="Params" [ShowToolbar]="true" [NavigateOnDoubleClick]="true" />
        </div>
    `,
})
export class MJCContractTypesPageComponent extends MJCConfigPageBase {
    protected get entityName(): string {
        return MJC_ENTITIES.ContractType;
    }
}

@Component({
    selector: 'mjc-template-types-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, ExplorerEntityDataGridComponent],
    template: `
        <div class="mjc-page">
            <p class="mjc-page__intro">
                What kind of standard-terms document a version belongs to. Two rows today, and only one
                has a real template behind it: <strong>Master Agreement</strong> is the versioned,
                numbered-provision document every Order Form incorporates.
                <strong>Statement of Work</strong> exists so the type is available — the business has
                standard SOW language but does not version it, so no template is registered against it.
                That absence is a fact about the business, not a gap in the data.
            </p>
            <mj-explorer-entity-data-grid [Params]="Params" [ShowToolbar]="true" [NavigateOnDoubleClick]="true" />
        </div>
    `,
})
export class MJCTemplateTypesPageComponent extends MJCConfigPageBase {
    protected get entityName(): string {
        return MJC_ENTITIES.ContractTemplateType;
    }
}

/**
 * The contract-number sequence.
 *
 * A single-row table, which makes a grid a slightly odd surface for it — but the number it holds is
 * the one piece of configuration that can visibly go wrong ("why is the next contract CTR-000412?"),
 * and having nowhere to look at it is worse than an odd-looking grid. Read-only in practice: the
 * counter is taken under a lock by the server subclass, so editing it by hand is a way to create
 * duplicate numbers, and the page says so.
 */
@Component({
    selector: 'mjc-numbering-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, ExplorerEntityDataGridComponent],
    template: `
        <div class="mjc-page">
            <p class="mjc-page__intro">
                Contract numbers are minted <code>CTR-000001</code> from a single counter, taken under a
                lock inside the save that uses it. The next value is below.
            </p>
            <p class="mjc-page__intro">
                <strong>Do not edit it to fix a gap.</strong> Gaps are normal — a save that fails after
                taking a number leaves one behind, and the unique index, not this counter, is what
                guarantees no two contracts share a number. Winding it backwards is how you get a
                collision.
            </p>
            @if (NextNumber !== null) {
                <div class="mjc-card">
                    <h3 class="mjc-card__title">Next contract number</h3>
                    <p>CTR-{{ PaddedNext }}</p>
                </div>
            }
            <mj-explorer-entity-data-grid [Params]="Params" [ShowToolbar]="false" />
        </div>
    `,
})
export class MJCNumberingPageComponent extends MJCConfigPageBase {
    public NextNumber: number | null = null;

    protected get entityName(): string {
        return MJC_ENTITIES.ContractSequence;
    }
    protected override get orderBy(): string {
        return 'ID ASC';
    }

    /** Rendered the way the server formats it, so what is shown is what the next contract will carry. */
    public get PaddedNext(): string {
        return String(this.NextNumber ?? 0).padStart(6, '0');
    }

    public override ngOnInit(): void {
        super.ngOnInit();
        void this.readNext();
    }

    private async readNext(): Promise<void> {
        try {
            const result = await ScopedRunView().RunView({
                EntityName: MJC_ENTITIES.ContractSequence,
                ResultType: 'simple',
                MaxRows: 1,
            });
            const row = (result?.Results ?? [])[0] as Record<string, unknown> | undefined;
            const value = Number(row?.['NextSequenceNumber']);
            this.NextNumber = Number.isFinite(value) ? value : null;
        } catch {
            // The grid below still shows the row; the card is a convenience.
            this.NextNumber = null;
        }
        this.cdr.detectChanges();
    }
}
