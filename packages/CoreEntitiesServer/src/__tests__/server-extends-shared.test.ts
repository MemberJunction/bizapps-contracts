/**
 * EVERY SERVER SUBCLASS MUST EXTEND THE SHARED ONE, NOT THE GENERATED ONE.
 *
 * `server-class-registration.test.ts` asserts that the server class WINS the ClassFactory for each
 * entity. It does not ask what winning costs, and for two entities it cost the shared rule.
 *
 * `@RegisterClass` resolves last-registered-wins. When the server class and the shared class both
 * register for one key and both extend the GENERATED class, they are siblings rather than a chain —
 * so the winner does not inherit the loser, it replaces it. MJAPI says so out loud at boot:
 *
 *     ContractTypeEntityServer is registering for base class BaseEntity with key
 *     'MJ_BizApps_Contracts: Contract Types', which is already registered by unrelated class(es):
 *     ContractTypeEntity. These are not in the same inheritance chain, so this is a COLLISION
 *     rather than a subclass override — ContractTypeEntityServer wins only by virtue of
 *     registering last, and ContractTypeEntity will never be resolved for this key.
 *
 * WHAT IT COST. `ContractTypeEntity` and `ContractTemplateTypeEntity` exist for one reason: they
 * override `Validate()` to run `ValidateValueLists`, because CodeGen renders a `CHECK (… IN (…))`
 * constraint as value-list METADATA that `BaseEntity` never reads (MJ#3969). Losing them on the
 * server does not fail loudly — the database still refuses a bad `Status` at the very end, as a
 * constraint violation naming no field, which is precisely the round trip the subclass was written
 * to prevent.
 *
 * The sibling test's own note said these server classes "carry NOTHING but a `Delete()` override.
 * There is no validation to fail" — true of the server class in isolation, and wrong about the pair.
 * That sentence is why this file exists: the belief was reasonable and checkable, and nothing
 * checked it.
 *
 * This asserts the CHAIN rather than the two known cases, so a sixth entity added tomorrow with the
 * same mistake fails here instead of at a customer's constraint violation.
 */
import { describe, expect, it } from 'vitest';
import { BaseEntity } from '@memberjunction/core';
import { MJGlobal } from '@memberjunction/global';
import {
    ContractEntity,
    ContractTemplateEntity,
    ContractTemplateModificationEntity,
    ContractTemplateProvisionEntity,
    ContractTemplateTypeEntity,
    ContractTypeEntity,
} from '@mj-biz-apps/contracts-entities';

// Import for SIDE EFFECT — this is what fires the decorators, exactly as the server bootstrap does.
import '../index.js';

/**
 * Every entity this app registers on both sides, with the SHARED class the server one must descend
 * from. All six are listed rather than only the two that were broken: the assertion is the rule, and
 * a rule that only covers its known violations stops being a guard the moment a new one appears.
 */
const PAIRS: ReadonlyArray<{ entity: string; shared: Function; sharedName: string }> = [
    { entity: 'MJ_BizApps_Contracts: Contracts', shared: ContractEntity, sharedName: 'ContractEntity' },
    { entity: 'MJ_BizApps_Contracts: Contract Templates', shared: ContractTemplateEntity, sharedName: 'ContractTemplateEntity' },
    {
        entity: 'MJ_BizApps_Contracts: Contract Template Modifications',
        shared: ContractTemplateModificationEntity,
        sharedName: 'ContractTemplateModificationEntity',
    },
    {
        entity: 'MJ_BizApps_Contracts: Contract Template Provisions',
        shared: ContractTemplateProvisionEntity,
        sharedName: 'ContractTemplateProvisionEntity',
    },
    { entity: 'MJ_BizApps_Contracts: Contract Types', shared: ContractTypeEntity, sharedName: 'ContractTypeEntity' },
    {
        entity: 'MJ_BizApps_Contracts: Contract Template Types',
        shared: ContractTemplateTypeEntity,
        sharedName: 'ContractTemplateTypeEntity',
    },
];

const resolve = (entity: string) => MJGlobal.Instance.ClassFactory.GetRegistration(BaseEntity, entity);

describe('the class the server resolves descends from the shared class', () => {
    for (const { entity, shared, sharedName } of PAIRS) {
        it(`${entity} -> ... -> ${sharedName}`, () => {
            const registration = resolve(entity);
            expect(registration, `nothing is registered for ${entity}`).toBeTruthy();

            const resolved = registration!.SubClass as unknown as Function;
            const isChained = resolved === shared || resolved.prototype instanceof shared;

            expect(
                isChained,
                `${resolved.name} does not extend ${sharedName}, so everything ${sharedName} overrides is `
                    + `lost on the server. Extend the shared class, not the generated one.`,
            ).toBe(true);
        });
    }
});

/**
 * The behavioural half. The chain above is the mechanism; this is what the mechanism was protecting.
 *
 * Comparing against the GENERATED class's `Validate` rather than `BaseEntity`'s, because the generated
 * subclass may define its own — the question is whether the value-list override is still in front of
 * it, not whether any override exists at all.
 */
describe('the value-list validation survives on the server', () => {
    for (const { entity, shared, sharedName } of [PAIRS[4], PAIRS[5]]) {
        it(`${entity} keeps ${sharedName}.Validate`, () => {
            const resolved = resolve(entity)!.SubClass as unknown as Function;
            expect(
                resolved.prototype.Validate,
                `Validate on the resolved class is not the one ${sharedName} defines, so a bad Status `
                    + `reaches the database and comes back as a constraint violation naming no field.`,
            ).toBe(shared.prototype.Validate);
        });
    }
});
