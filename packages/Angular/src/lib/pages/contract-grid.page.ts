/**
 * @fileoverview The contract list, and the two worklists that are the same list with a filter.
 *
 * ONE BASE, THREE PAGES. "All contracts", "Renewals & expiry" and "Awaiting documents" are the same
 * grid over the same view with different `ExtraFilter`s and different default pills. Three separate
 * implementations would be three places to fix a column, and they would drift — this is exactly the
 * 2-to-4-locations-of-similar-logic case the workspace guide says to unify, parameterised by context
 * (Template Method: shared skeleton, overridden hooks).
 *
 * THE GRID IS MJ'S OWN (`mj-explorer-entity-data-grid`), not a bespoke table. D-21 ruled the watchlist
 * deliberately thin — stock grid plus filter pills, no saved views — and D-23 requires selecting the
 * BASE VIEW so foreign keys render as names. Both are satisfied by construction here: `vwContracts` is
 * what the entity's `BaseView` resolves to, and it already carries `ContractType`, `Company`,
 * `CustomerOrganization`, `ContractTemplate` and `ParentContract` as joined name columns, plus the six
 * derived columns from the layered wrapper. Showing a UUID would take extra work.
 *
 * WHY THE FILTERS ARE VIEW COLUMNS AND NOT DATE ARITHMETIC IN TYPESCRIPT. `RenewalNoticeDeadline`,
 * `DaysToEnd`, `IsAwaitingDocument` and `State` are computed in the wrapper view (item 12), so a filter
 * here is a comparison against a column rather than a re-derivation. That is the whole payoff of
 * deriving them in SQL: the rule renders once, and a worklist cannot disagree with a form.
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
import { ScopedRunView } from '../data/provider';

/** One filter pill: a label, the SQL it contributes, and a live count. */
export interface MJCFilterPill {
    Id: string;
    Label: string;
    /** SQL fragment ANDed into the grid's ExtraFilter. Empty means "no restriction". */
    Filter: string;
    /** Populated by a count query; omitted from the UI when zero or unknown. */
    Count?: number;
    /** One line explaining what the pill means, for its title attribute. */
    Hint?: string;
}

/**
 * Shared skeleton. A concrete page supplies its title, its pills, and which pill starts active.
 *
 * `standalone: false` is wrong for these — they are created dynamically by the section via
 * `createComponent`, so they must be standalone and self-sufficient in their imports.
 */
@Component({ template: '' })
export abstract class MJCContractGridPageBase implements OnInit {
    protected readonly cdr = inject(ChangeDetectorRef);
    protected readonly navigation = inject(NavigationService);


    /** Pills for this page, in display order. The first is the default. */
    public Pills: MJCFilterPill[] = [];

    /** Which pill is active. Null means "no pill" — the unfiltered list. */
    public ActivePillId: string | null = null;

    /** What the grid runs. Rebuilt whenever the active pill changes. */
    public Params: RunViewParams | null = null;

    public IsLoading = false;
    public LoadError: string | null = null;

    /** Free-text restriction the user typed, ANDed with the pill. */
    public SearchText = '';


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
            // that panel needs its own affordance, or MJ needs the option.
            //
            // Filed upstream in ~/MJDev/MJ-UPSTREAM.md, because it is a PLATFORM gap every family app
            // hosting a grid in a resource page will hit, and a comment here only reaches readers of
            // this repo.
            this.navigation.OpenNewEntityRecord(event.EntityName);
        }
    }

    protected abstract get pills(): MJCFilterPill[];

    /**
     * A restriction that applies to EVERY pill on this page — what makes a worklist a worklist.
     *
     * Kept separate from the pills rather than baked into each one: the page-level scope is the
     * page's identity ("contracts awaiting documents"), while a pill narrows within it. Merging them
     * would mean repeating the scope in every pill and being able to forget it in one.
     */
    protected get pageFilter(): string {
        return '';
    }

    public ngOnInit(): void {
        this.Pills = this.pills;
        this.ActivePillId = this.Pills[0]?.Id ?? null;
        this.rebuild();
        void this.refreshCounts();
    }

    /** Pill click. Re-selecting the active pill CLEARS it, which is how a user gets back to unfiltered. */
    public SelectPill(id: string): void {
        this.ActivePillId = this.ActivePillId === id ? null : id;
        this.rebuild();
    }

    public ApplySearch(text: string): void {
        this.SearchText = text ?? '';
        this.rebuild();
    }

    /** Compose page scope + active pill + search into one ExtraFilter. */
    protected rebuild(): void {
        const clauses: string[] = [];
        if (this.pageFilter) clauses.push(`(${this.pageFilter})`);

        const pill = this.Pills.find((p) => p.Id === this.ActivePillId);
        if (pill?.Filter) clauses.push(`(${pill.Filter})`);

        const search = this.SearchText.trim();
        if (search) {
            // Single quotes doubled — the only escaping this needs, and it must not be skipped: the
            // string reaches SQL. Searching the NAME columns rather than the ids is the point of D-23.
            const safe = search.replace(/'/g, "''");
            clauses.push(
                `(ContractNumber LIKE '%${safe}%' OR CustomerOrganization LIKE '%${safe}%' ` +
                    `OR ContractType LIKE '%${safe}%')`,
            );
        }

        this.Params = {
            EntityName: MJC_ENTITIES.Contract,
            ExtraFilter: clauses.join(' AND '),
            OrderBy: this.orderBy,
        };
        this.cdr.detectChanges();
    }

    /** Default ordering. Worklists override — a worklist sorts by urgency, not by identity. */
    protected get orderBy(): string {
        return 'ContractNumber DESC';
    }

    /**
     * Count each pill, so the rail and the pills agree about how much work there is.
     *
     * One `RunView` per pill with `MaxRows: 1` — the count comes from `TotalRowCount`, so nothing is
     * transferred. Failures are swallowed to a null count rather than surfaced: a missing badge is a
     * cosmetic loss, and a page that refuses to render because a count query failed is not.
     */
    protected async refreshCounts(): Promise<void> {
        const rv = ScopedRunView();
        await Promise.all(
            this.Pills.map(async (pill) => {
                const clauses = [this.pageFilter, pill.Filter].filter(Boolean).map((c) => `(${c})`);
                try {
                    const result = await rv.RunView({
                        EntityName: MJC_ENTITIES.Contract,
                        ExtraFilter: clauses.join(' AND '),
                        MaxRows: 1,
                    });
                    pill.Count = result?.TotalRowCount ?? undefined;
                } catch {
                    pill.Count = undefined;
                }
            }),
        );
        this.cdr.detectChanges();
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * The three pages
 * ──────────────────────────────────────────────────────────────────────────── */

/** Markup shared by all three. Hoisted so a column or a pill row is styled in one place. */
const GRID_TEMPLATE = `
    <div class="mjc-page mjc-page--grid">
        <p class="mjc-page__intro">{{ Intro }}</p>

        <div class="mjc-pills">
            @for (pill of Pills; track pill.Id) {
                <button
                    type="button"
                    class="mjc-pill"
                    [class.mjc-pill--active]="pill.Id === ActivePillId"
                    [attr.aria-pressed]="pill.Id === ActivePillId"
                    [title]="pill.Hint ?? ''"
                    (click)="SelectPill(pill.Id)">
                    {{ pill.Label }}
                    @if (pill.Count) { <span class="mjc-pill__count">{{ pill.Count }}</span> }
                </button>
            }
        </div>

        <div class="mjc-grid-fill">
            <mj-explorer-entity-data-grid
                [Params]="Params"
                [ShowToolbar]="true"
                [NavigateOnDoubleClick]="true"
                (Navigate)="OnNavigate($event)" />
        </div>
    </div>
`;

/** Every contract, newest number first. */
@Component({
    selector: 'mjc-all-contracts-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: GRID_TEMPLATE,
})
export class MJCAllContractsPageComponent extends MJCContractGridPageBase {
    public Intro = 'Every agreement on record. Double-click a row to open it.';

    protected get pills(): MJCFilterPill[] {
        return [
            { Id: 'open', Label: 'Open', Filter: `State IN ('Draft','Executed','Active')`, Hint: 'Not expired, terminated or superseded' },
            { Id: 'active', Label: 'In force', Filter: `State = 'Active'`, Hint: 'Started and not yet ended' },
            { Id: 'executed', Label: 'Signed, not started', Filter: `State = 'Executed'`, Hint: 'Executed with a future effective date' },
            { Id: 'modified', Label: 'Modified', Filter: 'HasModifications = 1', Hint: 'Deviates from the standard agreement' },
            { Id: 'all', Label: 'All', Filter: '', Hint: 'Including expired, terminated and superseded' },
        ];
    }
}

/**
 * Renewals & expiry — item 12's screen.
 *
 * Sorted by `RenewalNoticeDeadline`, not `EndDate`, because the date that matters is when our chance to
 * act ends rather than when the contract does. Nulls last: a contract with no notice period recorded
 * has no deadline to miss, so it should not head a list of deadlines.
 *
 * The four defaults are exactly D-21's, and there is deliberately no Save-as-view: users drive filters
 * in-session, and persisting custom watchlists is phase 2 or never.
 */
@Component({
    selector: 'mjc-renewals-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: GRID_TEMPLATE,
})
export class MJCRenewalsPageComponent extends MJCContractGridPageBase {
    public Intro =
        'What finance must act on. Sorted by the renewal-notice deadline — the day our chance to act ends, ' +
        'which is earlier than the day the contract does.';

    /** Only live agreements can be renewed or allowed to expire. */
    protected override get pageFilter(): string {
        return `State IN ('Active','Executed')`;
    }

    protected override get orderBy(): string {
        // CASE rather than NULLS LAST — T-SQL has no NULLS LAST, and sorting nulls first would put
        // every contract with no notice period at the top of a deadline list.
        return 'CASE WHEN RenewalNoticeDeadline IS NULL THEN 1 ELSE 0 END, RenewalNoticeDeadline ASC';
    }

    protected get pills(): MJCFilterPill[] {
        return [
            {
                Id: 'next120',
                Label: 'Ends in 120 days',
                Filter: 'DaysToEnd IS NOT NULL AND DaysToEnd BETWEEN 0 AND 120',
                Hint: 'The quarter-ahead view',
            },
            {
                Id: 'notice-open',
                Label: 'Notice window open',
                Filter: 'RenewalNoticeDeadline IS NOT NULL AND RenewalNoticeDeadline >= CAST(GETUTCDATE() AS date)',
                Hint: 'We can still give notice in time',
            },
            {
                Id: 'notice-missed',
                Label: 'Notice window passed',
                Filter: 'RenewalNoticeDeadline IS NOT NULL AND RenewalNoticeDeadline < CAST(GETUTCDATE() AS date)',
                Hint: 'The deadline to give notice has gone by — surfaced rather than hidden',
            },
            { Id: 'auto', Label: 'Auto-renewing', Filter: 'AutoRenew = 1', Hint: 'Renews unless someone acts' },
            { Id: 'cancellation', Label: 'In cancellation window', Filter: 'IsInCancellationWindow = 1', Hint: "Inside the customer's notice period" },
        ];
    }
}

/**
 * Awaiting documents — the other half of item 12's work group.
 *
 * `IsAwaitingDocument` is derived (the contract TYPE expects paper and no file is linked), which is why
 * this page is a filter rather than a stored worklist: a Payment Link never appears here, because its
 * type says paper was never expected. Nothing has to remember to clear a flag.
 */
@Component({
    selector: 'mjc-awaiting-documents-page',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule],
    template: GRID_TEMPLATE,
})
export class MJCAwaitingDocumentsPageComponent extends MJCContractGridPageBase {
    public Intro =
        'Contracts whose type expects an executed document, with none attached. Payment Links never appear ' +
        'here — their type says no signature was ever expected.';

    protected override get pageFilter(): string {
        return 'IsAwaitingDocument = 1';
    }

    protected override get orderBy(): string {
        // Oldest signature first: a contract executed months ago with no filed paper is the one to chase.
        return 'CASE WHEN ExecutedDate IS NULL THEN 1 ELSE 0 END, ExecutedDate ASC';
    }

    protected get pills(): MJCFilterPill[] {
        return [
            { Id: 'in-force', Label: 'Already in force', Filter: `State = 'Active'`, Hint: 'Operating without filed paper — the urgent ones' },
            { Id: 'signed', Label: 'Signed, awaiting file', Filter: 'ExecutedDate IS NOT NULL', Hint: 'Executed but the document is not attached' },
            { Id: 'unsigned', Label: 'Not signed yet', Filter: 'ExecutedDate IS NULL', Hint: 'Nothing to file yet — expected' },
            { Id: 'all', Label: 'All awaiting', Filter: '', Hint: 'Everything missing expected paper' },
        ];
    }
}
