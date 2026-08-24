/**
 * @fileoverview The three Explorer tabs.
 *
 * Each class is registered `@RegisterClass(BaseResourceComponent, '<DriverClass>')` under the name the
 * Application's `DefaultNavItems` reference (`metadata/applications/.contracts-application.json`), which
 * is what makes these plug into MJ Explorer with no host-side wiring: Explorer reads the nav metadata,
 * asks the class factory for the driver class, and mounts it as a tab. BOTH HALVES ARE REQUIRED —
 * metadata without a registered class renders a dead tab, a registered class without metadata never
 * appears.
 *
 * Each section is deliberately thin. It owns three things — its rail, which sub-page is showing, and
 * remembering that across sessions — and delegates the frame to {@link MJCSectionShellComponent} and the
 * content to page components.
 *
 * SUB-PAGE HOSTING: pages are created once and CACHED, so switching rails and coming back does not
 * discard a part-filled form or re-run every count query.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import {
    ChangeDetectorRef,
    Component,
    OnInit,
    Type,
    ViewChild,
    ViewContainerRef,
    inject,
    type ComponentRef,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { RegisterClass } from '@memberjunction/global';
import { BaseResourceComponent } from '@memberjunction/ng-shared';
import type { MJLeftNavSection } from '@memberjunction/ng-ui-components';
import type { ResourceData } from '@memberjunction/core-entities';

import { MJCSectionShellComponent } from './section-shell.component';
import {
    BuildLeftNavSections,
    CONFIGURATION_SUB_PAGES,
    CONTRACTS_SUB_PAGES,
    TEMPLATES_SUB_PAGES,
    type MJCNavBadges,
    type MJCSubPage,
} from './section-nav.model';
import { MJC_ENTITIES } from '../data/entity-names';
import { ScopedRunView } from '../data/provider';

import {
    MJCAllContractsPageComponent,
    MJCAwaitingDocumentsPageComponent,
    MJCRenewalsPageComponent,
} from '../pages/contract-grid.page';
import { MJCModificationsPageComponent } from '../pages/modifications.page';
import { MJCContractsDashboardPageComponent } from '../pages/contracts-dashboard.page';
import { MJCAgreementVersionsPageComponent, MJCAllProvisionsPageComponent } from '../pages/templates.page';
import {
    MJCContractTypesPageComponent,
    MJCTemplateTypesPageComponent,
} from '../pages/configuration.page';

/** Shared skeleton for all three sections. */
@Component({ template: '' })
export abstract class MJCSectionBaseComponent extends BaseResourceComponent implements OnInit {
    /** Where a sub-page is created. Declared once, inherited by all three. */
    @ViewChild('pageHost', { read: ViewContainerRef, static: false })
    protected pageHost?: ViewContainerRef;

    protected readonly cdr = inject(ChangeDetectorRef);

    public NavSections: MJLeftNavSection[] = [];
    public ActivePageId: string | null = null;
    public IsLoading = false;
    public LoadError: string | null = null;

    protected badges: MJCNavBadges = {};
    protected readonly mounted = new Map<string, ComponentRef<unknown>>();

    protected abstract get subPages(): MJCSubPage[];
    protected abstract get preferenceKey(): string;
    protected abstract get sectionTitle(): string;
    protected abstract get sectionIcon(): string;

    /**
     * Component type for a page id, or null while a page is still to be built. Returning null renders a
     * sentence rather than throwing — a rail item that cannot open is a bug, but a blank pane is a worse
     * one, because it reads as a broken app rather than as work in progress.
     */
    protected abstract resolvePage(pageId: string): Type<unknown> | null;

    public override ngOnInit(): void {
        super.ngOnInit();
        this.NavSections = BuildLeftNavSections(this.subPages, this.badges);
        this.ActivePageId = this.restorePageId();

        // MACROTASK, NOT MICROTASK, and this is load-bearing. The host view must exist before a page
        // can be created into it, AND the page must be created outside the change-detection pass
        // running now. queueMicrotask drains before the CD cycle finishes, so the page is constructed
        // inside this turn; its async ngOnInit then resolves between Angular's check pass and its
        // dev-mode verify pass, which is NG0100 — and NG0100 ABORTS the rest of that update with
        // nothing scheduling another tick. The result is a screen frozen on its pre-fetch render: a
        // dashboard showing zeroes against a database full of rows, which looks like a quiet day
        // rather than a bug. Orders debugged exactly this; inheriting the fix is cheaper than
        // rediscovering it.
        setTimeout(async () => {
            try {
                await this.showPage(this.ActivePageId!);
                await this.refreshBadges();
            } finally {
                // ALWAYS signal, even on failure. Explorer's loading screen BLOCKS on this; a resource
                // that never signals is carried by a 15-second watchdog that logs a warning naming the
                // class and fails open. Fifteen seconds of blank screen on every visit is not a
                // fallback to rely on, and `finally` means a thrown page load degrades to an empty
                // pane rather than a hung app.
                this.NotifyLoadComplete();
                this.cdr.detectChanges();
            }
        });
    }

    /** Rail click handler. */
    public async OnPageSelected(pageId: string): Promise<void> {
        this.ActivePageId = pageId;
        this.persistPageId(pageId);
        this.LoadError = null;
        await this.showPage(pageId);
        this.cdr.detectChanges();
    }

    /**
     * Mount a page, reusing the instance if it has been shown before.
     *
     * Cached views are DETACHED rather than destroyed, which is what preserves state across a trip to
     * another rail item.
     */
    protected async showPage(pageId: string): Promise<void> {
        const host = this.pageHost;
        if (!host) return;

        host.detach();

        const cached = this.mounted.get(pageId);
        if (cached) {
            host.insert(cached.hostView);
            return;
        }

        const type = this.resolvePage(pageId);
        if (!type) {
            const label = this.subPages.find((p) => p.Id === pageId)?.Label ?? pageId;
            this.LoadError = `${label} is not built yet.`;
            return;
        }

        const ref = host.createComponent(type);
        // A page that wants to move the rail asks; it does not route itself. Wired by DUCK TYPING
        // rather than a shared interface because the pages are otherwise independent of the section,
        // and an interface would make every page import the shell's world just to emit a string.
        const instance = ref.instance as { NavigateToPage?: { subscribe: (fn: (id: string) => void) => void } };
        instance.NavigateToPage?.subscribe((id: string) => void this.OnPageSelected(id));
        this.mounted.set(pageId, ref);
        ref.changeDetectorRef.detectChanges();
    }

    /**
     * Badge counts for the rail. Overridden by the section that has badges; the others inherit a no-op
     * rather than each declaring an empty method.
     */
    protected async refreshBadges(): Promise<void> {
        /* no badges by default */
    }

    /** First page in the rail — the fallback when nothing is remembered. */
    protected get defaultPageId(): string {
        return this.subPages[0]?.Id ?? '';
    }

    /**
     * Restore the last page this user was on. Guarded, and falls back to the default rather than
     * throwing: an unknown id means the rail was renamed since the preference was written, and
     * stranding someone on a blank tab because of a rename is the wrong trade.
     */
    protected restorePageId(): string {
        try {
            const saved = globalThis.localStorage?.getItem(this.preferenceKey);
            if (saved && this.subPages.some((p) => p.Id === saved)) return saved;
        } catch {
            /* storage unavailable — the default is a fine answer */
        }
        return this.defaultPageId;
    }

    protected persistPageId(pageId: string): void {
        try {
            globalThis.localStorage?.setItem(this.preferenceKey, pageId);
        } catch {
            /* preferences simply do not persist */
        }
    }

    public override async GetResourceDisplayName(_data: ResourceData): Promise<string> {
        return this.sectionTitle;
    }

    public override async GetResourceIconClass(_data: ResourceData): Promise<string> {
        return this.sectionIcon;
    }

    public override ngOnDestroy(): void {
        for (const ref of this.mounted.values()) ref.destroy();
        this.mounted.clear();
        // PLAIN CALL, not `super.ngOnDestroy?.()`. The optional-call form is valid TypeScript and
        // esbuild fails to PARSE the bundle it produces — "SyntaxError: 'super' keyword unexpected
        // here" — which kills the whole chunk, so every section and panel in this package silently
        // fails to register and the app renders no nav tab at all. Found by driving Explorer in a real
        // browser; nothing in the type-check or the build catches it. BaseResourceComponent declares
        // ngOnDestroy concretely, so the guard bought nothing anyway.
        super.ngOnDestroy();
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * Contracts — the default tab
 * ──────────────────────────────────────────────────────────────────────────── */

@RegisterClass(BaseResourceComponent, 'ContractsSectionResource')
@Component({
    selector: 'mjc-contracts-section',
    standalone: true,
    imports: [CommonModule, MJCSectionShellComponent],
    template: `
        <mjc-section-shell
            Title="Contracts"
            Icon="fa-solid fa-file-signature"
            Subtitle="What we agreed, and where the paper is"
            [NavSections]="NavSections"
            [ActivePageId]="ActivePageId"
            [Loading]="IsLoading"
            [Error]="LoadError"
            (PageSelected)="OnPageSelected($event)">
            <ng-container #pageHost />
        </mjc-section-shell>
    `,
})
export class ContractsSectionResource extends MJCSectionBaseComponent {
    protected get subPages(): MJCSubPage[] {
        return CONTRACTS_SUB_PAGES;
    }
    protected get preferenceKey(): string {
        return 'mjc.section.contracts.page';
    }
    protected get sectionTitle(): string {
        return 'Contracts';
    }
    protected get sectionIcon(): string {
        return 'fa-solid fa-file-signature';
    }

    protected resolvePage(pageId: string): Type<unknown> | null {
        switch (pageId) {
            case 'dashboard':
                return MJCContractsDashboardPageComponent;
            case 'list':
                return MJCAllContractsPageComponent;
            case 'renewals':
                return MJCRenewalsPageComponent;
            case 'awaiting':
                return MJCAwaitingDocumentsPageComponent;
            case 'modifications':
                return MJCModificationsPageComponent;
            default:
                return null;
        }
    }

    /**
     * The three work counts, read from the same derived columns the worklists filter on — so a badge
     * cannot promise work the page then fails to show.
     *
     * A count that fails is left UNSET rather than zeroed: `BuildLeftNavSections` omits a falsy badge,
     * so an unreadable count renders no badge at all instead of a "0" that says "nothing to do here".
     */
    protected override async refreshBadges(): Promise<void> {
        const rv = ScopedRunView();
        const count = async (filter: string): Promise<number | undefined> => {
            try {
                const r = await rv.RunView({ EntityName: MJC_ENTITIES.Contract, ExtraFilter: filter, MaxRows: 1 });
                return r?.TotalRowCount ?? 0;
            } catch {
                return undefined;
            }
        };

        const [renewals, awaiting, modified] = await Promise.all([
            count(
                `State IN ('Active','Executed') AND RenewalNoticeDeadline IS NOT NULL ` +
                    `AND RenewalNoticeDeadline >= CAST(GETUTCDATE() AS date) ` +
                    `AND RenewalNoticeDeadline <= DATEADD(day, 120, CAST(GETUTCDATE() AS date))`,
            ),
            count('IsAwaitingDocument = 1'),
            count('HasModifications = 1'),
        ]);

        this.badges = { RenewalsDue: renewals, AwaitingDocuments: awaiting, Modified: modified };
        this.NavSections = BuildLeftNavSections(this.subPages, this.badges);
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * Templates
 * ──────────────────────────────────────────────────────────────────────────── */

@RegisterClass(BaseResourceComponent, 'ContractsTemplatesSectionResource')
@Component({
    selector: 'mjc-templates-section',
    standalone: true,
    imports: [CommonModule, MJCSectionShellComponent],
    template: `
        <mjc-section-shell
            Title="Templates"
            Icon="fa-solid fa-file-lines"
            Subtitle="The standard terms, version by version"
            [NavSections]="NavSections"
            [ActivePageId]="ActivePageId"
            [Loading]="IsLoading"
            [Error]="LoadError"
            (PageSelected)="OnPageSelected($event)">
            <ng-container #pageHost />
        </mjc-section-shell>
    `,
})
export class ContractsTemplatesSectionResource extends MJCSectionBaseComponent {
    protected get subPages(): MJCSubPage[] {
        return TEMPLATES_SUB_PAGES;
    }
    protected get preferenceKey(): string {
        return 'mjc.section.templates.page';
    }
    protected get sectionTitle(): string {
        return 'Templates';
    }
    protected get sectionIcon(): string {
        return 'fa-solid fa-file-lines';
    }

    protected resolvePage(pageId: string): Type<unknown> | null {
        switch (pageId) {
            case 'versions':
                return MJCAgreementVersionsPageComponent;
            case 'provisions':
                return MJCAllProvisionsPageComponent;
            default:
                return null;
        }
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * Configuration
 * ──────────────────────────────────────────────────────────────────────────── */

@RegisterClass(BaseResourceComponent, 'ContractsConfigurationSectionResource')
@Component({
    selector: 'mjc-configuration-section',
    standalone: true,
    imports: [CommonModule, MJCSectionShellComponent],
    template: `
        <mjc-section-shell
            Title="Configuration"
            Icon="fa-solid fa-sliders"
            Subtitle="The vocabularies every contract inherits"
            [NavSections]="NavSections"
            [ActivePageId]="ActivePageId"
            [Loading]="IsLoading"
            [Error]="LoadError"
            (PageSelected)="OnPageSelected($event)">
            <ng-container #pageHost />
        </mjc-section-shell>
    `,
})
export class ContractsConfigurationSectionResource extends MJCSectionBaseComponent {
    protected get subPages(): MJCSubPage[] {
        return CONFIGURATION_SUB_PAGES;
    }
    protected get preferenceKey(): string {
        return 'mjc.section.configuration.page';
    }
    protected get sectionTitle(): string {
        return 'Configuration';
    }
    protected get sectionIcon(): string {
        return 'fa-solid fa-sliders';
    }

    protected resolvePage(pageId: string): Type<unknown> | null {
        switch (pageId) {
            case 'contract-types':
                return MJCContractTypesPageComponent;
            case 'template-types':
                return MJCTemplateTypesPageComponent;
            default:
                return null;
        }
    }
}
