/**
 * WHO WINS THE CLASS FACTORY ON THE SERVER — the control the shared-side test cannot provide.
 *
 * `packages/Entities/src/__tests__/class-registration.test.ts` asserts the BROWSER answer: it imports
 * only the Entities package, so it sees only the shared registrations. The server registers a second,
 * later class for four of these names, and last-highest-priority-wins, so on the server those are the
 * classes that actually run. Nothing asserted them until now.
 *
 * The plan (R-8) predicted the shared test would fail when the new subclasses were added. It did not,
 * and the reason is exactly why this file exists: the shared test cannot see the server package at all.
 * A registration added there is invisible to it in both directions — it will not fail on a new one, and
 * it will not notice a lost one.
 *
 * THE STAKES ARE HIGHER HERE THAN ON THE SHARED SIDE. `ContractTemplateEntityServer`,
 * `ContractTemplateProvisionEntityServer`, `ContractTypeEntityServer` and
 * `ContractTemplateTypeEntityServer` carry NOTHING but a `Delete()` override. There is no validation to
 * fail and no save to refuse, so if a production build tree-shakes one away the only symptom is that a
 * refused delete goes back to reading as a raw foreign-key constraint error — which looks like MJ
 * behaving normally. That is the definition of a silent regression, and the anti-tree-shake anchors in
 * `index.ts` are what this file is really checking.
 */
import { describe, expect, it } from 'vitest';
import { BaseEntity } from '@memberjunction/core';
import { MJGlobal } from '@memberjunction/global';

// Import for SIDE EFFECT — this is what fires the decorators, exactly as the server bootstrap does.
import '../index.js';
import { LoadMjBizappsContractsEntitiesServer } from '../index.js';

/** Every entity whose SERVER-side implementation differs from the shared one. */
const SERVER_OVERRIDES: ReadonlyArray<{ entity: string; className: string; why: string }> = [
    { entity: 'MJ_BizApps_Contracts: Contracts', className: 'ContractEntityServer', why: 'number minting, HasModifications EXISTS, retired-type check, delete guard' },
    { entity: 'MJ_BizApps_Contracts: Contract Template Modifications', className: 'ContractTemplateModificationEntityServer', why: 'provision/template consistency, parent flag' },
    { entity: 'MJ_BizApps_Contracts: Contract Templates', className: 'ContractTemplateEntityServer', why: 'R-8 delete guard ONLY — a lost registration is silent' },
    { entity: 'MJ_BizApps_Contracts: Contract Template Provisions', className: 'ContractTemplateProvisionEntityServer', why: 'R-8 delete guard ONLY — a lost registration is silent' },
    { entity: 'MJ_BizApps_Contracts: Contract Types', className: 'ContractTypeEntityServer', why: 'R-8 delete guard ONLY — a lost registration is silent' },
    { entity: 'MJ_BizApps_Contracts: Contract Template Types', className: 'ContractTemplateTypeEntityServer', why: 'R-8 delete guard ONLY — a lost registration is silent' },
];

/**
 * No server subclass exists for these, so the shared/generated class is the correct answer.
 *
 * Empty since R-7 retired `Contract Sequences` — every entity this app still owns now has a server
 * subclass. Kept rather than deleted because the assertion below is the guard against a server class
 * being registered for an entity that is supposed to run the shared one, and the next entity added to
 * this app will want it.
 */
const NO_SERVER_OVERRIDE: readonly string[] = [];

const resolve = (entity: string) => MJGlobal.Instance.ClassFactory.GetRegistration(BaseEntity, entity);

describe('the server resolves its own subclass for every entity that has one', () => {
    for (const { entity, className, why } of SERVER_OVERRIDES) {
        it(`${entity} -> ${className} (${why})`, () => {
            const registration = resolve(entity);
            expect(registration, `nothing is registered for ${entity}`).toBeTruthy();
            expect(registration!.SubClass.name).toBe(className);
        });
    }
});

describe('the anti-tree-shake anchors cover every server subclass', () => {
    it('calling the bootstrap loader leaves all of them registered', () => {
        // The real failure mode: a production build drops an import whose class is never referenced.
        // `LoadMjBizappsContractsEntitiesServer` is the live reference that prevents it, and forgetting
        // to add a new subclass to it is the mistake this catches.
        LoadMjBizappsContractsEntitiesServer();
        for (const { entity, className } of SERVER_OVERRIDES) {
            expect(resolve(entity)?.SubClass.name, entity).toBe(className);
        }
    });

    it('the loader is idempotent', () => {
        LoadMjBizappsContractsEntitiesServer();
        LoadMjBizappsContractsEntitiesServer();
        expect(resolve('MJ_BizApps_Contracts: Contract Types')?.SubClass.name).toBe('ContractTypeEntityServer');
    });
});

describe('entities with no server subclass do not accidentally get one', () => {
    // One test rather than a loop, so an EMPTY list is a passing assertion rather than a suite with no
    // tests in it (vitest fails the file for that, which reads as a broken test rather than an empty
    // list). The list is empty today because R-7 retired the last entity without a server subclass.
    it('none of them resolves to an *EntityServer class', () => {
        const wrong = NO_SERVER_OVERRIDE.filter((entity) => /EntityServer$/.test(resolve(entity)?.SubClass.name ?? ''));
        expect(wrong).toEqual([]);
    });
});
