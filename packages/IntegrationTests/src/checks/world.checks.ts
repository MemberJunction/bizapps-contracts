/**
 * contracts-world — commit CTR-WORLD (template, customers, a portfolio covering every State).
 *
 * One check: the rows a person clicks in Explorer actually exist, with minted contract numbers
 * and relative dates so the watchlist does not drift.
 */
import { Assert, IntegrationCheckRegistry, type IntegrationCheckContext, type NamedCheck } from '@memberjunction/testing-integration/registry';
import { CONTRACT_STATES } from '@mj-biz-apps/contracts-entities';
import { E_CONTRACT, FindRows, WORLD_NOTE } from '../fixture.js';
import { LoadWorld } from '../world/load-world.js';
import { World } from '../world/world.js';

export const ContractsWorldChecks: NamedCheck[] = [
    {
        Id: 'contracts-world.CW1',
        Name: 'CW1 — CTR-WORLD is loaded: every State, a change order, and two modifications',
        RequiresMutation: true,
        Fn: async (ctx: IntegrationCheckContext) => {
            const world = await LoadWorld(ctx);

            Assert(!!world.TemplateID, 'IT Master Agreement was not published');
            Assert(Object.keys(world.Contracts).length === Object.keys(WORLD_NOTE).length, 'missing CTR-WORLD contracts');

            for (const [key, row] of Object.entries(world.Contracts)) {
                Assert(!!row.ID, `CTR-WORLD ${key} has no ID`);
                Assert(/^CTR-\d+$/i.test(row.ContractNumber), `CTR-WORLD ${key} number ${row.ContractNumber} was not minted`);
            }

            const states = await FindRows<{ Notes: string; State: string; ContractNumber: string }>(
                ctx,
                E_CONTRACT,
                `Notes LIKE 'CTR-WORLD:%'`,
                ['Notes', 'State', 'ContractNumber'],
            );
            const byNote = new Map(states.map((s) => [s.Notes, s.State]));
            AssertEqualState(byNote, WORLD_NOTE.activeMsa, 'Active');
            AssertEqualState(byNote, WORLD_NOTE.noticePassed, 'Active');
            AssertEqualState(byNote, WORLD_NOTE.executedFuture, 'Executed');
            AssertEqualState(byNote, WORLD_NOTE.awaitingDoc, 'Active');
            AssertEqualState(byNote, WORLD_NOTE.paymentLink, 'Active');
            AssertEqualState(byNote, WORLD_NOTE.expired, 'Expired');
            AssertEqualState(byNote, WORLD_NOTE.draft, 'Draft');
            AssertEqualState(byNote, WORLD_NOTE.changeOrder, 'Active');
            AssertEqualState(byNote, WORLD_NOTE.terminated, 'Terminated');
            AssertEqualState(byNote, WORLD_NOTE.cancelWindow, 'Active');
            AssertEqualState(byNote, WORLD_NOTE.supersededPred, 'Superseded');
            AssertEqualState(byNote, WORLD_NOTE.supersededSucc, 'Active');

            const seen = new Set(states.map((s) => s.State));
            for (const required of ['Active', 'Executed', 'Draft', 'Expired', 'Terminated', 'Superseded'] as const) {
                Assert(seen.has(required), `CTR-WORLD has no ${required} contract — Explorer will look empty on that filter`);
                Assert((CONTRACT_STATES as readonly string[]).includes(required), `unknown state ${required}`);
            }

            World();
        },
    },
];

function AssertEqualState(byNote: Map<string, string>, notes: string, expected: string): void {
    Assert(byNote.get(notes) === expected, `${notes} derived State = ${byNote.get(notes) ?? 'missing'}, expected ${expected}`);
}

for (const check of ContractsWorldChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-world', {
    Setup: async () => undefined,
    Teardown: async () => undefined,
});
