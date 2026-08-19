/**
 * @fileoverview The agreement-version registry, and the flat clause list across versions.
 *
 * Item 7's surface. "Agreement versions" rather than "Templates" in the UI, deliberately: a row here is
 * one DATED version of the Master Agreement and is never edited in place, because signed contracts
 * reference it. The word "template" invites editing; "version" does not.
 *
 * The provisions of ONE version are edited on the template's own form, through the `Provisions`
 * collection panel — not here. This page is the registry (which versions exist) plus a flat list
 * (every clause across every version), which is the view you want when answering "what does 4.2 say,
 * and did it change between editions?"
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { ChangeDetectorRef, Component, OnInit, ViewEncapsulation, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NavigationService } from '@memberjunction/ng-shared';
import type { CompositeKey } from '@memberjunction/core';
import type { RunViewParams } from '@memberjunction/core';
import { BaseFormsModule } from '@memberjunction/ng-base-forms';
import { MJC_ENTITIES } from '../data/entity-names';
import { MJCFkNavigateDirective } from '../directives/fk-navigate.directive';

/** One row per published agreement version. */
@Component({
    selector: 'mjc-agreement-versions-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule, MJCFkNavigateDirective],
    template: `
        <div class="mjc-page mjc-page--grid">
            <p class="mjc-page__intro">
                Every published version of the standard terms. Open one to read and curate its
                provisions. A new edition is a <strong>new row</strong> — an existing version is never
                rewritten, because contracts already signed against it say they incorporate exactly
                what it said at the time.
            </p>
            <div class="mjc-grid-fill">
                <mj-explorer-entity-data-grid mjcFkNavigate
                    [Params]="Params"
                        [ShowToolbar]="true"
                        [NavigateOnDoubleClick]="true"
                (Navigate)="OnNavigate($event)" />
            </div>
        </div>
    `,
})
export class MJCAgreementVersionsPageComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);
    protected readonly navigation = inject(NavigationService);

    /**
     * Open the double-clicked record.
     *
     * THE GRID DOES NOT NAVIGATE ITSELF. `NavigateOnDoubleClick` only controls whether it EMITS
     * `Navigate`; acting on it is the HOST's job. Without this, a double-click merely selected the row
     * — measured in a real browser, where it looked exactly like the grid being broken. Explorer's own
     * host wires this for generated forms; a page hosting the grid inside a BaseResourceComponent must
     * do it itself.
     */
    public OnNavigate(event: {
        Kind?: string;
        EntityName?: string;
        PrimaryKey?: CompositeKey;
        DefaultValues?: Record<string, unknown>;
    }): void {
        if (!event?.EntityName) return;
        if (event.Kind === 'record' && event.PrimaryKey) {
            this.navigation.OpenEntityRecord(event.EntityName, event.PrimaryKey);
            return;
        }
        if (event.Kind === 'new-record') {
            // TWO kinds, and missing this one meant the toolbar's New button did NOTHING on every grid
            // page — found in the browser, after the double-click bug had already taught me the same
            // lesson about this component. Handling only 'record' silently dropped it.
            //
            // ⚠ `event.DefaultValues` is DISCARDED here, and it has nowhere to go: NavigationOptions
            // carries no default-values field, so `OpenNewEntityRecord` cannot pre-populate. Harmless on
            // these pages (nothing sets NewRecordValues), but it means the Organization agreements
            // panel's pre-linking to the customer will NOT survive a New click routed through here —
            // that panel needs its own affordance, or MJ needs the option. Written down rather than
            // discovered later as "New forgets the customer".
            this.navigation.OpenNewEntityRecord(event.EntityName);
        }
    }

    public Params: RunViewParams | null = null;

    /**
     * Toolbar affordances that actually work, and one that does not.
     *
     * ⚠ `showFilterToggle` IS A NO-OP, and this comment used to claim the opposite. It is declared on
     * `GridToolbarConfig` (`grid-types.ts:249`) and documented in the entity-viewer README, and it is
     * **read nowhere in MJ** — no template branch renders a filter button. Three sibling hooks are dead
     * the same way: the `AllowColumnFilters` input stores `_allowColumnFilters` and nothing reads it,
     * `_filterState` is declared and never touched, and `defaultColDef.filter` is hardcoded `false`, so
     * AG Grid's per-column filters are off with no input to turn them on. It is left set to `true` here
     * because it costs nothing and is the flag to keep passing if MJ ever wires it up.
     *
     * So the ONLY filtering this page has beyond the pills is `showSearch` — which sets AG Grid's
     * `quickFilterText`, a client-side substring match over the rows already loaded. It is not
     * structured and not server-side. Filtering by date range / category / derived State needs a real
     * filter popover (see `design-docs/ui-design/mockups-v2/renewal-watchlist.html`), which is ours to
     * build; the pills stay regardless, because they encode the QUESTIONS people ask rather than
     * predicates a user would assemble by hand.
     */
    public readonly GridToolbar = {
        showSearch: true,
        showFilterToggle: true,
        showColumnChooser: true,
        showRefresh: true,
        showExport: true,
        showRowCount: true,
    };


    public ngOnInit(): void {
        this.Params = {
            EntityName: MJC_ENTITIES.ContractTemplate,
            // Newest edition first: the current terms are what people look for.
            OrderBy: 'IntroducedDate DESC',
        };
        this.cdr.detectChanges();
    }
}

/** Every clause of every version, in canonical order within each. */
@Component({
    selector: 'mjc-all-provisions-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule, MJCFkNavigateDirective],
    template: `
        <div class="mjc-page mjc-page--grid">
            <p class="mjc-page__intro">
                Every numbered clause across every agreement version, in document order. Ordered by
                <code>Sequence</code>, not by provision number — <code>1.10</code> sorts before
                <code>1.2</code> as text, and the Master Agreement's two longest sections are exactly
                the ones that breaks.
            </p>
            <div class="mjc-grid-fill">
                <mj-explorer-entity-data-grid mjcFkNavigate
                    [Params]="Params"
                        [ShowToolbar]="true"
                        [NavigateOnDoubleClick]="true"
                (Navigate)="OnNavigate($event)" />
            </div>
        </div>
    `,
})
export class MJCAllProvisionsPageComponent implements OnInit {
    private readonly cdr = inject(ChangeDetectorRef);
    protected readonly navigation = inject(NavigationService);

    /**
     * Open the double-clicked record.
     *
     * THE GRID DOES NOT NAVIGATE ITSELF. `NavigateOnDoubleClick` only controls whether it EMITS
     * `Navigate`; acting on it is the HOST's job. Without this, a double-click merely selected the row
     * — measured in a real browser, where it looked exactly like the grid being broken. Explorer's own
     * host wires this for generated forms; a page hosting the grid inside a BaseResourceComponent must
     * do it itself.
     */
    public OnNavigate(event: {
        Kind?: string;
        EntityName?: string;
        PrimaryKey?: CompositeKey;
        DefaultValues?: Record<string, unknown>;
    }): void {
        if (!event?.EntityName) return;
        if (event.Kind === 'record' && event.PrimaryKey) {
            this.navigation.OpenEntityRecord(event.EntityName, event.PrimaryKey);
            return;
        }
        if (event.Kind === 'new-record') {
            // TWO kinds, and missing this one meant the toolbar's New button did NOTHING on every grid
            // page — found in the browser, after the double-click bug had already taught me the same
            // lesson about this component. Handling only 'record' silently dropped it.
            //
            // ⚠ `event.DefaultValues` is DISCARDED here, and it has nowhere to go: NavigationOptions
            // carries no default-values field, so `OpenNewEntityRecord` cannot pre-populate. Harmless on
            // these pages (nothing sets NewRecordValues), but it means the Organization agreements
            // panel's pre-linking to the customer will NOT survive a New click routed through here —
            // that panel needs its own affordance, or MJ needs the option. Written down rather than
            // discovered later as "New forgets the customer".
            this.navigation.OpenNewEntityRecord(event.EntityName);
        }
    }

    public Params: RunViewParams | null = null;

    /**
     * Toolbar affordances that actually work, and one that does not.
     *
     * ⚠ `showFilterToggle` IS A NO-OP, and this comment used to claim the opposite. It is declared on
     * `GridToolbarConfig` (`grid-types.ts:249`) and documented in the entity-viewer README, and it is
     * **read nowhere in MJ** — no template branch renders a filter button. Three sibling hooks are dead
     * the same way: the `AllowColumnFilters` input stores `_allowColumnFilters` and nothing reads it,
     * `_filterState` is declared and never touched, and `defaultColDef.filter` is hardcoded `false`, so
     * AG Grid's per-column filters are off with no input to turn them on. It is left set to `true` here
     * because it costs nothing and is the flag to keep passing if MJ ever wires it up.
     *
     * So the ONLY filtering this page has beyond the pills is `showSearch` — which sets AG Grid's
     * `quickFilterText`, a client-side substring match over the rows already loaded. It is not
     * structured and not server-side. Filtering by date range / category / derived State needs a real
     * filter popover (see `design-docs/ui-design/mockups-v2/renewal-watchlist.html`), which is ours to
     * build; the pills stay regardless, because they encode the QUESTIONS people ask rather than
     * predicates a user would assemble by hand.
     */
    public readonly GridToolbar = {
        showSearch: true,
        showFilterToggle: true,
        showColumnChooser: true,
        showRefresh: true,
        showExport: true,
        showRowCount: true,
    };


    public ngOnInit(): void {
        this.Params = {
            EntityName: MJC_ENTITIES.ContractTemplateProvision,
            // Group by version, then document order within it. The base view carries the template's
            // name column, so grouping by it reads as a name (D-23).
            OrderBy: 'ContractTemplate ASC, Sequence ASC',
        };
        this.cdr.detectChanges();
    }
}
