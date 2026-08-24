/**
 * @fileoverview Make the grid's foreign-key links actually open the record they point at.
 *
 * THE DEFECT THIS EXISTS TO WORK AROUND (MJ, not ours). `mj-entity-data-grid` renders every FK cell as
 * an anchor (`.cell-fk-link`, blue + underlined), detects the click, and emits `ForeignKeyClick` with
 * the related entity and the FK value — see `entity-data-grid.component.ts` → `onAgCellClicked`. But
 * `mj-explorer-entity-data-grid`, the wrapper the forms + our pages use, **never binds that output and
 * declares no equivalent of its own** (verified in `explorer-entity-data-grid.component.ts`: the inner
 * grid's template binds `AfterRowDoubleClick`, `AfterRowClick`, `AfterDataLoad` and
 * `NewRecordTabRequested`, and nothing else). So the cell LOOKS like a link, the grid does its half of
 * the work, and the event dies inside the wrapper. Every FK link in every wrapper-hosted grid is inert.
 *
 * That is a silent-failure UI bug of the worst kind — the affordance advertises navigation that cannot
 * happen — and it is why Marcelo hit it immediately on the modifications grid.
 *
 * WHY A DIRECTIVE, and why this is not a DOM hack. The wrapper exposes the inner grid publicly
 * (`@ViewChild('innerGrid') innerGrid!: EntityDataGridComponent`), so a directive on the same host
 * element can inject the wrapper and subscribe to the inner component's own `@Output`. We use MJ's
 * public API and MJ's own event — we do not reach into the DOM, re-parse the `data-*` attributes, or
 * re-implement the hit test. When the wrapper grows a real `ForeignKeyClick` output, deleting this
 * file and binding it is a one-line change with identical behaviour.
 *
 * The navigation itself mirrors MJ's own canonical handler
 * (`grid-view-renderer.component.ts` → `onForeignKeyClick`): prefer the event's `relatedEntityName`,
 * else resolve the name from `relatedEntityId` through metadata.
 *
 * FILED: see `plans/WORKAROUNDS.md` — this belongs upstream, as an output on the wrapper.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { AfterViewInit, Directive, OnDestroy, inject } from '@angular/core';
import { CompositeKey } from '@memberjunction/core';
import { ExplorerEntityDataGridComponent } from '@memberjunction/ng-base-forms';
import { NavigationService } from '@memberjunction/ng-shared';
import { AmbientMetadata } from '../data/provider';

@Directive({
    selector: '[mjcFkNavigate]',
    standalone: true,
})
export class MJCFkNavigateDirective implements AfterViewInit, OnDestroy {
    private readonly grid = inject(ExplorerEntityDataGridComponent, { host: true });
    private readonly navigation = inject(NavigationService);
    /**
     * Typed structurally rather than as an rxjs `Subscription`: this package does not declare rxjs as a
     * dependency (Angular brings it transitively), and importing a type from an undeclared package is
     * how a build breaks the first time the hoisting changes. `unsubscribe()` is all we use.
     */
    private sub: { unsubscribe(): void } | null = null;

    /**
     * Subscribe after the view exists, because `innerGrid` is a `@ViewChild` on the wrapper and is
     * undefined until then. One retry on a microtask covers the case where the wrapper's own
     * `AfterViewInit` has not yet run — directive and component hook order on the same host is not
     * something to rely on.
     */
    public ngAfterViewInit(): void {
        if (this.subscribe()) return;
        void Promise.resolve().then(() => this.subscribe());
    }

    private subscribe(): boolean {
        if (this.sub) return true;
        const inner = this.grid?.innerGrid;
        if (!inner?.ForeignKeyClick) return false;
        this.sub = inner.ForeignKeyClick.subscribe((e) => this.open(e));
        return true;
    }

    /**
     * Open the related record.
     *
     * The FK event carries a bare value, not a key, so the primary-key FIELD NAME comes from the
     * related entity's metadata rather than being assumed to be `ID`. It is `ID` for every entity in
     * this app, but assuming it would break the first time this directive met a natural-key entity —
     * and it would break as a wrong-record navigation, not an error.
     */
    private open(e: { relatedEntityId: string; recordId: string; relatedEntityName?: string }): void {
        if (!e?.recordId) return;
        const md = AmbientMetadata();
        const entity =
            (e.relatedEntityName ? md.Entities.find((x) => x.Name === e.relatedEntityName) : undefined) ??
            md.Entities.find((x) => x.ID === e.relatedEntityId);
        if (!entity) return;

        const pkField = entity.PrimaryKeys?.[0]?.Name ?? 'ID';
        this.navigation.OpenEntityRecord(entity.Name, CompositeKey.FromKeyValuePair(pkField, e.recordId));
    }

    public ngOnDestroy(): void {
        this.sub?.unsubscribe();
        this.sub = null;
    }
}
