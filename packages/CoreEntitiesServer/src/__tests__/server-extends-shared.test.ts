/**
 * EVERY SERVER SUBCLASS MUST EXTEND THE SHARED ONE, NOT THE GENERATED ONE.
 *
 * `server-class-registration.test.ts` asserts that the server class WINS the ClassFactory for each
 * entity, and it does check the chain: it already loops its own list asserting each winner is linear
 * with what it beat. What it never asks is what the win COSTS when that chain is broken -- it does
 * not mention `Validate` anywhere -- and for two entities here the cost was the shared rule itself.
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
 * So the chain assertion here overlaps the sibling deliberately, and the three things it adds are
 * the point: that the shared `Validate` override survives on the class the server actually resolves,
 * that the pair list cannot quietly fall behind the registrations in the package, and that the
 * shared side's hand-written set is pinned too. A sixth entity added tomorrow with the same mistake
 * fails here rather than at a customer's constraint violation.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
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

/**
 * THE LIST ABOVE CANNOT QUIETLY FALL BEHIND THE PACKAGE.
 *
 * It is hand-written, and the sibling guard in bizapps-orders (#345) showed what that costs: four
 * pairs listed while six entities were registered on both sides, so two were unguarded for as long
 * as they happened to be correct. This list is complete today; this keeps it complete.
 *
 * Every `@RegisterClass(BaseEntity, ...)` in this package must be classified, as a pair above or as
 * one with no shared sibling. A new server entity class fails this until someone says which it is,
 * which is the decision the drift skipped.
 */
describe('every server entity registration is classified', () => {
    const SRC = fileURLToPath(new URL('..', import.meta.url));

    /** The key each pair above is written with in the source, so the two lists can be compared. */
    const COVERED: ReadonlySet<string> = new Set(PAIRS.map((p) => `'${p.entity}'`));

    /**
     * Server classes with NO hand-written shared sibling, for which extending the generated class is
     * correct. Empty today: every entity class this package registers has a shared counterpart.
     */
    const NO_SHARED_SIBLING: ReadonlySet<string> = new Set<string>();

    /** The second argument of every `@RegisterClass(BaseEntity, ...)` in the package, as written. */
    const registeredKeys = (): string[] => {
        const keys: string[] = [];
        for (const file of readdirSync(SRC)) {
            if (!file.endsWith('.ts')) continue;
            const text = readFileSync(join(SRC, file), 'utf8');
            for (const m of text.matchAll(/@RegisterClass\(BaseEntity,\s*([^)]+)\)/g)) {
                keys.push(m[1].trim());
            }
        }
        return keys;
    };

    it('names every one of them either as a pair or as having no shared sibling', () => {
        const unclassified = registeredKeys().filter((k) => !COVERED.has(k) && !NO_SHARED_SIBLING.has(k));
        expect(
            unclassified,
            'these register an entity class on the server and are in neither list. If a hand-written '
                + 'shared subclass registers for the same key, add the pair; if not, add it to '
                + 'NO_SHARED_SIBLING with that as the reason.',
        ).toEqual([]);
    });

    it('finds the registrations at all, so an empty scan cannot pass this', () => {
        expect(registeredKeys().length).toBeGreaterThanOrEqual(COVERED.size);
    });
});

/**
 * THE OTHER HALF OF THE CLASSIFICATION, WHICH THE BLOCK ABOVE CANNOT SEE.
 *
 * `NO_SHARED_SIBLING` is a claim about the SHARED package, and the block above reads only the server
 * package, so it cannot check that claim. The set is empty today -- every server class here has a
 * hand-written sibling -- so there is nothing false in it yet. It stops being empty the first time a
 * server class is added for an entity the shared package does not hand-write, and from that moment a
 * shared subclass appearing for that key is silently replaced, with every assertion here still green.
 *
 * Pinning the shared package's hand-written registrations by file closes that before it opens, and
 * keeps this suite identical to its counterpart in bizapps-orders, where the set is not empty.
 */
describe('the shared package hand-writes exactly the subclasses the pairs assume', () => {
    const SHARED_SRC = fileURLToPath(new URL('../../../Entities/src', import.meta.url));

    /** Files outside `generated/` that register an entity class. The generated ones are not siblings. */
    const registeringFiles = (): string[] =>
        readdirSync(SHARED_SRC)
            .filter((f) => f.endsWith('.ts'))
            .filter((f) => /@RegisterClass\(BaseEntity,/.test(readFileSync(join(SHARED_SRC, f), 'utf8')))
            .sort();

    /** Five files for six pairs: `ContractTypeEntity.ts` registers both of the lookup types. */
    const EXPECTED = [
        'ContractEntity.ts',
        'ContractTemplateEntity.ts',
        'ContractTemplateModificationEntity.ts',
        'ContractTemplateProvisionEntity.ts',
        'ContractTypeEntity.ts',
    ];

    it('registers from exactly these files, so a new shared subclass forces the pairs to be re-checked', () => {
        expect(
            registeringFiles(),
            'a file added here may have a server class registering the same key. If it does, add the '
                + 'pair above and take the key out of NO_SHARED_SIBLING; if it does not, add the file here.',
        ).toEqual(EXPECTED);
    });

    it('found files at all, so an empty scan cannot pass this', () => {
        expect(registeringFiles().length).toBeGreaterThan(0);
    });
});
