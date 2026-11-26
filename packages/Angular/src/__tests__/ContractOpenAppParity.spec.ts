/**
 * Deterministic OpenApp v3 Readiness & Parity Guard Suite for `@mj-biz-apps/contracts-ng`.
 *
 * Verifies:
 *   1. Dual Form Registration Parity via live `MJGlobal.Instance.ClassFactory.GetRegistration(BaseFormComponent, ...)`
 *      for `MJ_BizApps_Contracts: Contracts` and every entity in `packages/Angular/src/lib/generated/Entities/`.
 *   2. Contributed `BaseFormPanel` registrations including `MJCContractDocumentPreviewPanel` alongside
 *      relational `MJCContractNotesPanel`, `MJCContractModificationsPanel`, and `MJCContractExecutedAgreementPanel`.
 *   3. Navigation & Resource Parity (`metadata/applications/.contracts-application.json` `DefaultNavItems`
 *      <-> live `BaseResourceComponent` registrations + `<mj-page-layout>` + `NotifyLoadComplete()` +
 *      `ChangeDetectionStrategy.OnPush` + `UserInfoEngine.Instance`).
 *   4. Design-token & hygiene invariants across ALL Angular component `.ts`, `.css`, and `.html` files:
 *      - ZERO raw `#hex`, `rgb()`, `rgba()`, or `hsl()` / `hsla()` color literals.
 *      - ZERO `window.print()` calls.
 *      - ZERO `localStorage` or `sessionStorage` calls.
 *      - ZERO `6.3.0-edge.2`-only `@memberjunction/ng-artifacts` imports.
 */
import '@angular/compiler';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it, vi } from 'vitest';
import { MJGlobal } from '@memberjunction/global';
import { BaseFormComponent, BaseFormPanel } from '@memberjunction/ng-base-forms';
import { BaseResourceComponent } from '@memberjunction/ng-shared';

// `@mj-biz-apps/common-ng` transitively imports optional peer `@memberjunction/ng-graph-view`
// which is not required by Contracts' own form/section registrations under Vitest Node.
vi.mock('@mj-biz-apps/common-ng', () => ({
    PartyFieldComponent: class PartyFieldComponent {},
    RelatedChipsComponent: class RelatedChipsComponent {},
    StatRowComponent: class StatRowComponent {},
    StatTileComponent: class StatTileComponent {},
}));

import {
    LoadMjBizappsContractsClient,
    MJCContractDocumentPreviewPanel,
    MJCContractExecutedAgreementPanel,
    MJCContractModificationsPanel,
    MJCContractNotesPanel,
    mjBizAppsContractsContractFormComponent,
    mjBizAppsContractsContractOrderFormComponent,
    mjBizAppsContractsContractTemplateFormComponent,
    mjBizAppsContractsContractTemplateModificationFormComponent,
    mjBizAppsContractsContractTemplateProvisionFormComponent,
    mjBizAppsContractsContractTemplateTypeFormComponent,
    mjBizAppsContractsContractTypeFormComponent,
} from '../public-api';

const REPO_ROOT = fileURLToPath(new URL('../../../../', import.meta.url));
const ANGULAR_LIB_DIR = fileURLToPath(new URL('../lib', import.meta.url));
const APP_METADATA_PATH = join(REPO_ROOT, 'metadata/applications/.contracts-application.json');
const MJ_APP_MANIFEST_PATH = join(REPO_ROOT, 'mj-app.json');
const SECTIONS_FILE_PATH = join(ANGULAR_LIB_DIR, 'sections/contracts-sections.component.ts');

// Invoke the OpenApp client bootstrap export to ensure all registrations are anchored and live.
LoadMjBizappsContractsClient();

function walkAngularSourceFiles(dir: string): string[] {
    const results: string[] = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const fullPath = join(dir, entry.name);
        if (entry.isDirectory()) {
            if (entry.name === '__tests__') continue;
            results.push(...walkAngularSourceFiles(fullPath));
        } else if (/\.(ts|css|html)$/.test(entry.name)) {
            results.push(fullPath);
        }
    }
    return results;
}

/** Strips block and line comments so comment references like `golive#225` are not mistaken for CSS colors. */
function stripComments(source: string): string {
    return source
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/<!--[\s\S]*?-->/g, '')
        .replace(/^\s*\/\/.*$/gm, '');
}

/** Extracts CSS/style bodies from `.css` files, `.html` `<style>` blocks, and Angular `@Component({ styles: [...] })` literals. */
function extractStyleContent(filePath: string, source: string): string {
    const withoutComments = stripComments(source);
    if (filePath.endsWith('.css')) {
        return withoutComments;
    }
    if (filePath.endsWith('.html')) {
        const styleTags = [...withoutComments.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)].map((m) => m[1] ?? '');
        const inlineStyles = [...withoutComments.matchAll(/style\s*=\s*["']([^"']*)["']/gi)].map((m) => m[1] ?? '');
        return [...styleTags, ...inlineStyles].join('\n');
    }
    // Extract `styles: [ ... ]` and `const *_STYLES = \`...\`` blocks from TypeScript component files.
    const matches: string[] = [];
    for (const m of withoutComments.matchAll(/styles\s*:\s*\[([\s\S]*?)\]/g)) {
        matches.push(m[1] ?? '');
    }
    for (const m of withoutComments.matchAll(/STYLES\s*=\s*`([\s\S]*?)`/g)) {
        matches.push(m[1] ?? '');
    }
    return matches.join('\n');
}

describe('OpenApp v3 Dual Form Registration Parity', () => {
    const EXPECTED_FORMS: ReadonlyArray<{
        entityName: string;
        formClass:
            | typeof mjBizAppsContractsContractFormComponent
            | typeof mjBizAppsContractsContractOrderFormComponent
            | typeof mjBizAppsContractsContractTemplateFormComponent
            | typeof mjBizAppsContractsContractTemplateModificationFormComponent
            | typeof mjBizAppsContractsContractTemplateProvisionFormComponent
            | typeof mjBizAppsContractsContractTemplateTypeFormComponent
            | typeof mjBizAppsContractsContractTypeFormComponent;
    }> = [
        { entityName: 'MJ_BizApps_Contracts: Contracts', formClass: mjBizAppsContractsContractFormComponent },
        { entityName: 'MJ_BizApps_Contracts: Contract Orders', formClass: mjBizAppsContractsContractOrderFormComponent },
        { entityName: 'MJ_BizApps_Contracts: Contract Templates', formClass: mjBizAppsContractsContractTemplateFormComponent },
        {
            entityName: 'MJ_BizApps_Contracts: Contract Template Modifications',
            formClass: mjBizAppsContractsContractTemplateModificationFormComponent,
        },
        {
            entityName: 'MJ_BizApps_Contracts: Contract Template Provisions',
            formClass: mjBizAppsContractsContractTemplateProvisionFormComponent,
        },
        {
            entityName: 'MJ_BizApps_Contracts: Contract Template Types',
            formClass: mjBizAppsContractsContractTemplateTypeFormComponent,
        },
        { entityName: 'MJ_BizApps_Contracts: Contract Types', formClass: mjBizAppsContractsContractTypeFormComponent },
    ];

    for (const { entityName, formClass } of EXPECTED_FORMS) {
        it(`registers BaseFormComponent for "${entityName}" in MJGlobal.Instance.ClassFactory`, () => {
            const reg = MJGlobal.Instance.ClassFactory.GetRegistration(BaseFormComponent, entityName);
            expect(reg, `Missing BaseFormComponent registration for "${entityName}"`).toBeDefined();
            expect(reg?.SubClass).toBe(formClass);
        });
    }

    it('contributes MJCContractDocumentPreviewPanel alongside relational Notes, Modifications, and Executed Agreement panels without replacing the generated Contract form', () => {
        const formReg = MJGlobal.Instance.ClassFactory.GetRegistration(
            BaseFormComponent,
            'MJ_BizApps_Contracts: Contracts',
        );
        expect(formReg?.SubClass).toBe(mjBizAppsContractsContractFormComponent);

        const panelClasses = MJGlobal.Instance.ClassFactory.GetAllRegistrations(BaseFormPanel).map(
            (r) => r.SubClass,
        );
        expect(panelClasses).toContain(MJCContractDocumentPreviewPanel);
        expect(panelClasses).toContain(MJCContractNotesPanel);
        expect(panelClasses).toContain(MJCContractModificationsPanel);
        expect(panelClasses).toContain(MJCContractExecutedAgreementPanel);
    });

    it('anchors client startupExport from mj-app.json to LoadMjBizappsContractsClient', () => {
        const manifest = JSON.parse(readFileSync(MJ_APP_MANIFEST_PATH, 'utf8')) as {
            packages?: { client?: Array<{ name: string; startupExport?: string }> };
        };
        const clientPkg = manifest.packages?.client?.find((p) => p.name === '@mj-biz-apps/contracts-ng');
        expect(clientPkg?.startupExport).toBe('LoadMjBizappsContractsClient');
    });
});

describe('OpenApp v3 Navigation & Resource Parity', () => {
    it('registers every DefaultNavItems DriverClass as a BaseResourceComponent with <mj-page-layout>, NotifyLoadComplete(), OnPush, and UserInfoEngine.Instance', () => {
        const appMetadata = JSON.parse(readFileSync(APP_METADATA_PATH, 'utf8')) as Array<{
            fields?: {
                DefaultNavItems?: Array<{ Label: string; DriverClass: string; ResourceType: string }>;
            };
        }>;
        const navItems = appMetadata[0]?.fields?.DefaultNavItems ?? [];
        expect(navItems.length).toBeGreaterThanOrEqual(3);

        const sectionsSrc = readFileSync(SECTIONS_FILE_PATH, 'utf8');
        expect(sectionsSrc).toContain('this.NotifyLoadComplete()');
        expect(sectionsSrc).toContain('UserInfoEngine.Instance');
        expect(sectionsSrc).not.toMatch(/\blocalStorage\b|\bsessionStorage\b/);

        for (const item of navItems) {
            const reg = MJGlobal.Instance.ClassFactory.GetRegistration(BaseResourceComponent, item.DriverClass);
            expect(reg, `DefaultNavItems DriverClass "${item.DriverClass}" is not registered`).toBeDefined();

            // Verify each section component block declares <mj-page-layout> and ChangeDetectionStrategy.OnPush
            const classAnchor = `@RegisterClass(BaseResourceComponent, '${item.DriverClass}')`;
            const startIdx = sectionsSrc.indexOf(classAnchor);
            expect(startIdx, `Missing @RegisterClass anchor for ${item.DriverClass}`).toBeGreaterThanOrEqual(0);
            const nextIdx = sectionsSrc.indexOf('@RegisterClass(BaseResourceComponent,', startIdx + classAnchor.length);
            const block = sectionsSrc.slice(startIdx, nextIdx === -1 ? sectionsSrc.length : nextIdx);
            expect(block, `${item.DriverClass} must wrap its template in <mj-page-layout>`).toContain('<mj-page-layout>');
            expect(block, `${item.DriverClass} must use ChangeDetectionStrategy.OnPush`).toContain(
                'ChangeDetectionStrategy.OnPush',
            );
        }
    });
});

describe('OpenApp v3 Design Tokens, Print, Storage, and edge.1 Compatibility Gates', () => {
    const files = walkAngularSourceFiles(ANGULAR_LIB_DIR);

    it('discovers Angular component source, style, and template files', () => {
        expect(files.length).toBeGreaterThan(10);
    });

    it('enforces ZERO raw #hex, rgb(), rgba(), hsl(), or hsla() color literals across Angular CSS/HTML/inline styles', () => {
        const rawColorPattern = /#[0-9a-fA-F]{3,8}\b|\brgba?\s*\(|\bhsla?\s*\(/;
        const violations: string[] = [];

        for (const file of files) {
            const raw = readFileSync(file, 'utf8');
            const cssText = extractStyleContent(file, raw);
            if (!cssText) continue;
            const match = cssText.match(rawColorPattern);
            if (match) {
                violations.push(`${file}: matched raw color literal "${match[0]}"`);
            }
        }

        expect(violations, `Raw color literals found in Angular styles:\n${violations.join('\n')}`).toEqual([]);
    });

    it('enforces ZERO window.print(), ZERO localStorage/sessionStorage, and ZERO edge.2-only ng-artifacts imports', () => {
        const violations: string[] = [];

        for (const file of files) {
            const cleaned = stripComments(readFileSync(file, 'utf8'));
            if (/\bwindow\.print\s*\(/.test(cleaned)) {
                violations.push(`${file}: contains forbidden window.print()`);
            }
            if (/\blocalStorage\b|\bsessionStorage\b/.test(cleaned)) {
                violations.push(`${file}: contains forbidden localStorage/sessionStorage (use UserInfoEngine.Instance)`);
            }
            if (
                /\b(MJEmbeddedDocPanelComponent|MJArtifactSlideoverComponent|MJRecordDocsListComponent|ArtifactRelatedPanelComponent)\b/.test(
                    cleaned,
                )
            ) {
                violations.push(`${file}: imports edge.2-only @memberjunction/ng-artifacts symbol`);
            }
        }

        expect(violations, `OpenApp v3 hygiene violations:\n${violations.join('\n')}`).toEqual([]);
    });
});
