/**
 * @fileoverview `mjc-section-shell` — the frame every Contracts section renders inside.
 *
 * One of the three top-level sections occupies a tab in MJ Explorer; each owns a LEFT rail over its
 * own sub-pages. This component is that frame: MJ's chrome trio plus `<mj-left-nav>`, with the active
 * sub-page projected into the content pane.
 *
 * COMPOSITION RATHER THAN INHERITANCE, deliberately. Angular does not inherit templates, so a base
 * *class* would force one copy of this markup per section — and three copies of a frame is three
 * places for the frame to drift. Each section is a thin component that hands this one a rail and
 * projects a page.
 *
 * Nothing here is bespoke chrome: header, body, rail and content pane all come from
 * `@memberjunction/ng-ui-components`. A section with its own gradient header is a section that no
 * longer looks like MJ.
 *
 * THREE TRAPS ORDERS PAID FOR, INHERITED HERE RATHER THAN REDISCOVERED — each is load-bearing and
 * each looks like styling:
 *
 *  1. NO TOOLBAR SLOT. MJ hides its toolbar row when empty (`:empty` on
 *     `mj-page-header-row--toolbar`), but a wrapper `div` carrying the `toolbar` attribute is itself a
 *     child node, so the row stops counting as empty and renders its border plus padding on every
 *     section forever — orders measured 29px of dead space on all four. No section here projects a
 *     toolbar, so the slot would only ever cost height. A section that needs one must add the wrapper
 *     back AND guard it with an `@if`.
 *  2. `mj-page-body-interior` IS REQUIRED FOR SCROLLING. `mj-left-nav-content` forces every DIRECT
 *     child to flex + `height:100%` + `overflow:hidden` via a `::ng-deep` child rule that outranks a
 *     page's own `:host { overflow:auto }`. Projected straight in, every page becomes a fixed-height
 *     box with its overflow hidden and anything past the fold is unreachable — a mouse wheel cannot
 *     scroll `overflow:hidden`. `mj-page-body-interior` is MJ's own answer: it is named in that rule's
 *     `:not()` exemption list and self-declares `flex:1 1 auto; overflow-y:auto`. Wrapping here fixes
 *     every section at once and keeps pages as grandchildren, so their own `:host` layout applies.
 *  3. `ViewEncapsulation.None` + `styleUrls` IS HOW THE KIT SHIPS. `ngc` only compiles what a
 *     component references, so a standalone stylesheet nothing imports gets built into `dist` and
 *     never loaded by a real Explorer — the app renders as unstyled text while the mockups look
 *     perfect, because those `@import` it by hand. Referencing the kit from the shell every section
 *     renders inside means Angular carries it wherever the app is mounted. `None` is required, not
 *     lazy: these classes are used by DESCENDANT components, so scoping them breaks them.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { Component, EventEmitter, Input, Output, ViewEncapsulation } from '@angular/core';
import { CommonModule } from '@angular/common';
import {
    MJLeftNavComponent,
    MJLeftNavContentComponent,
    MJPageBodyComponent,
    MJPageBodyInteriorComponent,
    MJPageHeaderComponent,
    MJPageLayoutComponent,
    type MJLeftNavItem,
    type MJLeftNavSection,
} from '@memberjunction/ng-ui-components';

@Component({
    selector: 'mjc-section-shell',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    styleUrls: ['../styles/contracts-kit.css'],
    imports: [
        CommonModule,
        MJPageLayoutComponent,
        MJPageHeaderComponent,
        MJPageBodyComponent,
        MJLeftNavComponent,
        MJLeftNavContentComponent,
        MJPageBodyInteriorComponent,
    ],
    template: `
        <mj-page-layout>
            <mj-page-header [Title]="Title" [Icon]="Icon" [Subtitle]="Subtitle">
                <div meta><ng-content select="[meta]"></ng-content></div>
                <div actions><ng-content select="[actions]"></ng-content></div>
                <!-- No toolbar slot — see trap 1 in the file header. -->
            </mj-page-header>

            <mj-page-body [Flex]="true" [Padding]="false" Direction="row">
                <mj-left-nav
                    [Sections]="NavSections"
                    [ActiveId]="ActivePageId"
                    [Width]="RailWidth"
                    [MobileTitle]="Title"
                    (ItemClicked)="onItemClicked($event)" />

                <mj-left-nav-content [Loading]="Loading" [Error]="Error">
                    <!-- Required for scrolling — see trap 2. Padding off; each page supplies its own. -->
                    <mj-page-body-interior [Padding]="false">
                        <ng-content></ng-content>
                    </mj-page-body-interior>
                </mj-left-nav-content>
            </mj-page-body>
        </mj-page-layout>
    `,
})
export class MJCSectionShellComponent {
    /** Section title — the identity of the whole tab, so sub-pages never restate it. */
    @Input() Title = '';

    /** Font Awesome class for the title. */
    @Input() Icon = '';

    /** One line saying what this section is for. */
    @Input() Subtitle = '';

    /** The rail, built by {@link BuildLeftNavSections} from the section's page list. */
    @Input() NavSections: MJLeftNavSection[] = [];

    /** Which sub-page is showing. Drives the rail's active state. */
    @Input() ActivePageId: string | null = null;

    /** Rail width in pixels. 232 matches the mockups and orders. */
    @Input() RailWidth = 232;

    /** Shows the content pane's built-in spinner instead of the projected page. */
    @Input() Loading = false;

    /** Shows the content pane's built-in error state. Null clears it. */
    @Input() Error: string | null = null;

    /**
     * A rail item was chosen. Emits the page id.
     *
     * Emitted rather than acted on: this component does not know how the host loads a page, and a
     * shell that routed would stop being reusable outside the one app that taught it how.
     */
    @Output() PageSelected = new EventEmitter<string>();

    protected onItemClicked(item: MJLeftNavItem): void {
        if (item.disabled) return;
        // Re-selecting the current page is a no-op rather than a reload — people click the rail item
        // they are already on surprisingly often.
        if (item.id === this.ActivePageId) return;
        this.PageSelected.emit(item.id);
    }
}
