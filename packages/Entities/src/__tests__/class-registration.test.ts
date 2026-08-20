/**
 * WHO WINS THE CLASS FACTORY — the test that would have caught the worst thing in the v1 tree.
 *
 * MJ resolves an entity's implementation through `MJGlobal.ClassFactory`, keyed on the entity NAME.
 * Registrations are silent and last-highest-priority-wins, so a stale registration does not error —
 * it just quietly serves a different class than the one you are reading.
 *
 * That is not hypothetical here. v1 shipped `MJCContractFormComponent` registered at PRIORITY 2 for
 * `MJ_BizApps_Contracts: Contracts`; it survived the schema rebuild, would have beaten the
 * regenerated form at runtime, and bound `Status` — a column D-19 deleted. It was found by a human
 * reading the diff, which is not a control we can rely on twice. This file is the control.
 *
 * Scope: registration only. Nothing here instantiates an entity or touches a provider, so it runs in
 * the cheap tier with no database.
 */
import { describe, expect, it } from 'vitest';
import { BaseEntity } from '@memberjunction/core';
import { MJGlobal } from '@memberjunction/global';

// Import for SIDE EFFECT: this is what fires the decorators. If this import were dropped, every
// assertion below would fail — which is the honest failure, since the app's registration depends on
// exactly this import happening in the bootstrap.
import '../index.js';
import { ContractEntity } from '../ContractEntity.js';

/** Every entity this app owns, and the class each name must resolve to. */
const EXPECTED: ReadonlyArray<{ entity: string; className: string }> = [
    // Entities with a hand-written shared subclass. Resolving to the generated class instead would
    // silently drop the rules the subclass carries — which is the whole failure mode this file exists
    // for, since a lost registration does not error.
    //   Contracts             — the HasModifications guard and Supersede().
    //   the two lookup tables — the value-list guard standing in for MJ#3969, without which their
    //                           IN(...) CHECK constraints have no TypeScript representation at all.
    //   Contract Template Provisions   — the same required-field prose, once ProvisionText became
    //                           required (V202608200800). Shares the mechanism via required-field-prose.ts.
    //   Contract Template Modifications — the required-field prose (R-6). It carries no RULE, so
    //                           losing the registration would not fail a save; it would quietly
    //                           restore MJ's "<field> cannot be null", which nothing else detects.
    { entity: 'MJ_BizApps_Contracts: Contracts', className: 'ContractEntity' },
    { entity: 'MJ_BizApps_Contracts: Contract Types', className: 'ContractTypeEntity' },
    { entity: 'MJ_BizApps_Contracts: Contract Template Types', className: 'ContractTemplateTypeEntity' },
    { entity: 'MJ_BizApps_Contracts: Contract Template Modifications', className: 'ContractTemplateModificationEntity' },
    { entity: 'MJ_BizApps_Contracts: Contract Template Provisions', className: 'ContractTemplateProvisionEntity' },
    // The rest have no hand-written subclass yet, so the GENERATED class is the correct answer.
    // Asserting that is not redundant: it is what fails if someone adds a subclass without adding it
    // to this list, or re-registers one of v1's deleted classes.
    { entity: 'MJ_BizApps_Contracts: Contract Templates', className: 'mjBizAppsContractsContractTemplateEntity' },
];

/** v1 entity names. Nothing may still register for them — the tables are gone. */
const DELETED_V1_ENTITIES: readonly string[] = [
    // R-7 (2026-08-20): the ContractSequence TABLE became a SQL SEQUENCE, which CodeGen cannot see,
    // so the entity, its 4 fields and its 2 generated validators are gone. Listed here rather than
    // merely deleted from EXPECTED so a re-registration is caught: the whole point of R-7 was that an
    // API-writable counter is a surface with no legitimate use.
    'MJ_BizApps_Contracts: Contract Sequences',
    'MJ_BizApps_Contracts: Contract Terms',
    'MJ_BizApps_Contracts: Contract Lines',
    'MJ_BizApps_Contracts: Contract Amendments',
    'MJ_BizApps_Contracts: Contract Billing Schedules',
    'MJ_BizApps_Contracts: Contract Billing Events',
    'MJ_BizApps_Contracts: Contract Commitments',
    'MJ_BizApps_Contracts: Contract Events',
];

const resolve = (entity: string) => MJGlobal.Instance.ClassFactory.GetRegistration(BaseEntity, entity);

describe('every contracts entity resolves to the intended class', () => {
    for (const { entity, className } of EXPECTED) {
        it(`${entity} → ${className}`, () => {
            const registration = resolve(entity);
            expect(registration, `nothing is registered for "${entity}"`).toBeTruthy();
            expect(registration!.SubClass.name).toBe(className);
        });
    }
});

describe('the shared subclass is what the browser gets', () => {
    it('Contracts resolves to the class carrying the rules, not the generated base', () => {
        // The distinction that matters: the generated class has no Validate() override, so if this
        // resolved to it, HasModifications could be cleared with modification rows present and the
        // browser would never object.
        expect(resolve('MJ_BizApps_Contracts: Contracts')!.SubClass).toBe(ContractEntity);
    });

    it('exposes the rules the form depends on', () => {
        // Cheap, but it is what breaks if a refactor moves these off the shared class and onto the
        // server one, where the browser cannot reach them.
        expect(typeof ContractEntity.prototype.Supersede).toBe('function');
        expect(typeof ContractEntity.prototype.Validate).toBe('function');
    });
});

describe('nothing registers for an entity the rebuild deleted', () => {
    for (const entity of DELETED_V1_ENTITIES) {
        it(`${entity} has no registration`, () => {
            // A surviving registration here is the v1 failure mode exactly: a class that loads
            // successfully and then reads columns that no longer exist.
            expect(resolve(entity)).toBeFalsy();
        });
    }
});
