/**
 * contracts-numbering — ContractNumber is minted from seq_ContractNumber, uniquely.
 *
 * The lock lives in `spAssignNextContractNumber`. Gaps are normal (the sequence does not roll
 * back); uniqueness is the property that matters. Each check rolls its transaction back, so
 * Explorer never sees these rows — the numbers themselves are spent, which the column comment
 * already documents.
 */
import { randomUUID } from 'node:crypto';
import {
    Assert,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration/registry';
import {
    InRolledBackTransaction,
    NewContract,
    RefuseSave,
    RequireSave,
    ResolveContractsFixture,
} from '../fixture.js';

type Ctx = IntegrationCheckContext;

export const NumberingChecks: NamedCheck[] = [
    {
        Id: 'contracts-numbering.N1',
        Name: 'N1 — a blank ContractNumber is minted as CTR-<digits> on first save',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f);
                Assert(!(contract.ContractNumber ?? '').trim(), 'N1 started with a number already set');
                await RequireSave(contract, 'N1 first save');
                const minted = (contract.ContractNumber ?? '').trim();
                Assert(/^CTR-\d+$/i.test(minted), `N1 minted ${JSON.stringify(minted)}, expected CTR-<digits>`);
            });
        },
    },
    {
        Id: 'contracts-numbering.N2',
        Name: 'N2 — two sequential creates receive different numbers',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const a = await NewContract(ctx, f);
                const b = await NewContract(ctx, f);
                await RequireSave(a, 'N2 first');
                await RequireSave(b, 'N2 second');
                const left = (a.ContractNumber ?? '').trim();
                const right = (b.ContractNumber ?? '').trim();
                Assert(left !== right, `N2 both contracts received ${left}`);
            });
        },
    },
    {
        Id: 'contracts-numbering.N3',
        Name: 'N3 — two concurrent creates receive different numbers',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const a = await NewContract(ctx, f);
                const b = await NewContract(ctx, f);
                const [okA, okB] = await Promise.all([a.Save(), b.Save()]);
                Assert(okA, `N3 first save failed: ${a.LatestResult?.CompleteMessage ?? 'unknown'}`);
                Assert(okB, `N3 second save failed: ${b.LatestResult?.CompleteMessage ?? 'unknown'}`);
                const left = (a.ContractNumber ?? '').trim();
                const right = (b.ContractNumber ?? '').trim();
                Assert(!!left && !!right, `N3 missing a number: ${left} / ${right}`);
                Assert(left !== right, `N3 concurrent creates collided on ${left}`);
            });
        },
    },
    {
        Id: 'contracts-numbering.N4',
        Name: 'N4 — a hand-typed number outside the CTR- namespace is kept',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const custom = `DEMO-${randomUUID().slice(0, 8).toUpperCase()}`;
                const contract = await NewContract(ctx, f, (c) => {
                    c.ContractNumber = custom;
                });
                await RequireSave(contract, 'N4 custom number');
                Assert(
                    (contract.ContractNumber ?? '').trim() === custom,
                    `N4 expected to keep ${custom}, got ${contract.ContractNumber}`,
                );
            });
        },
    },
    {
        Id: 'contracts-numbering.N5',
        Name: 'N5 — a hand-typed CTR- number is refused so it cannot collide with the sequence later',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await NewContract(ctx, f, (c) => {
                    c.ContractNumber = 'CTR-900099';
                });
                await RefuseSave(contract, 'N5 reserved CTR-900099', /reserved|cannot be entered by hand/i);
            });
        },
    },
];

for (const check of NumberingChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-numbering', {
    Setup: async (ctx) => {
        await ResolveContractsFixture(ctx);
    },
    Teardown: async () => undefined,
});
