/**
 * @fileoverview `Contracts.Supersede` — set (or clear) which contract an agreement replaces.
 *
 * WHY A REMOTABLE OPERATION AND NOT ENTITY CALLS FROM THE PANEL. The write targets a DIFFERENT record
 * from the one on screen: `SupersededByContractID` lives on the PREDECESSOR, so the successor's form
 * has to reach over and write another contract. Doing that from the browser meant the panel loading
 * and saving foreign entities itself — server work done in the client. Ruled by Marcelo (2026-08-21):
 * a cross-record write with rules is exactly what a remote operation is for.
 *
 * It also makes the feature immune to MJ#4002, where the browser resolves the CodeGen-generated entity
 * class instead of the app's subclass, so `ContractEntity.Supersede()` is simply absent client-side.
 * Here the work runs on the server, where the server subclass resolves correctly and every rule in
 * `ContractEntityServer.ValidateAsync()` — same-level, self-reference, lineage cycles — actually fires.
 *
 * ADD, NOT REPLACE — reversed 2026-08-31 (issue #28 items 9 and 10). The schema deliberately allows
 * MANY predecessors to name one successor, and that is the real business case: a consolidated
 * agreement replaces several earlier ones at once. This operation used to read the single-select
 * picker as "one predecessor is the intent" and release every other predecessor before linking, so
 * linking a second contract silently unlinked the first — the user was told "Linked … Released
 * CTR-0001." for an action they never asked for.
 *
 * So the two verbs are now separate and each touches exactly ONE record:
 *
 *   `PredecessorID`        ADDS that contract to what this agreement supersedes. Nothing else moves.
 *   `ReleasePredecessorID` RELEASES that one contract, and only that one.
 *
 * Neither is a bulk operation and neither has a "do everything" sentinel. `PredecessorID: null` used
 * to mean "release them all", which is how one ignored argument in the panel turned a single Unlink
 * button into a clear-the-lot — the defect behind item 9. A null now simply means "not asked for".
 *
 * NO transaction wrapper, deliberately. Each contract is saved through its own entity so every rule
 * runs, and the outcome is reported per-record. A half-applied change is visible in the returned list
 * rather than hidden behind a rollback that also discards the reason it failed.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import {
    BaseRemotableOperation,
    type IMetadataProvider,
    type RemoteOpServerContext,
    RunView,
    type UserInfo,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import type { ContractEntity } from '@mj-biz-apps/contracts-entities';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';

export interface SupersedeInput {
    /** The agreement doing the superseding — the record the user is looking at. */
    SuccessorID: string;
    /**
     * A contract to ADD to what this agreement supersedes. Existing predecessors are left alone —
     * a successor may replace many earlier agreements. Null/absent links nothing.
     *
     * Mutually exclusive with `ReleasePredecessorID`: one verb per call, and both set is refused.
     */
    PredecessorID?: string | null;
    /**
     * A single contract to RELEASE — exactly the one named, never the rest. Refused unless it is
     * currently superseded by this agreement, so a stale button cannot clear an unrelated record.
     */
    ReleasePredecessorID?: string | null;
}

export interface SupersedeOutput {
    /** What the successor supersedes AFTER the operation — the panel renders this, so it can never be stale. */
    Supersedes: Array<{ ID: string; ContractNumber: string }>;
    /** Contract numbers released by this call — at most one, since release names a single record. */
    Released: string[];
    /** Set when the link was refused; carries the entity's own message, not a generic failure. */
    Refused?: string;
}

@RegisterClass(BaseRemotableOperation, 'Contracts.Supersede')
export class SupersedeOperation extends BaseRemotableOperation<SupersedeInput, SupersedeOutput> {
    public readonly OperationKey = 'Contracts.Supersede';

    protected override async InternalExecute(
        input: SupersedeInput,
        provider: IMetadataProvider,
        user: UserInfo,
        _context: RemoteOpServerContext,
    ): Promise<SupersedeOutput> {
        if (!input?.SuccessorID) throw new Error('SuccessorID is required.');

        // ONE VERB PER CALL. Both inputs set is refused rather than ordered, because there is no
        // ordering that makes it mean something. The two branches below share a single pre-release
        // snapshot of the predecessor list — release checks its target is in it, link checks its
        // target is NOT — so `PredecessorID === ReleasePredecessorID` releases the contract and then
        // skips the link, having found it in a list taken before the release. The caller asked for a
        // link and got none, silently. Reading the list twice would make that particular pair work
        // and would still leave the call ambiguous: releasing X while linking Y is two decisions in
        // one request, and the panel sends one verb at a time. Say so instead of picking for them.
        if (input.PredecessorID && input.ReleasePredecessorID) {
            throw new Error(
                'Supersede takes one action at a time: PredecessorID to add a predecessor, or ' +
                    'ReleasePredecessorID to release one — not both in the same call.',
            );
        }

        const successor = await provider.GetEntityObject<ContractEntity>(E_CONTRACT, user);
        if (!(await successor.Load(input.SuccessorID))) {
            throw new Error('The contract doing the superseding could not be loaded.');
        }

        const released: string[] = [];
        const same = (a: string | null | undefined, b: string | null | undefined) =>
            !!a && !!b && a.toLowerCase() === b.toLowerCase();

        // Read the CURRENT predecessors once. Both branches below need it: release checks that its
        // target is genuinely one of them, and link checks that it is not already there.
        const current = await this.readSupersedes(provider, user, input.SuccessorID);

        // ── Release exactly the contract named, and nothing else (item 9) ─────────────────────────
        if (input.ReleasePredecessorID) {
            const target = current.find((c) => same(c.ID, input.ReleasePredecessorID));
            if (!target) {
                // Not a throw: the likeliest cause is a stale panel whose list predates someone else's
                // change, and the caller re-renders from `Supersedes` below. Clearing the column on a
                // record this agreement does not supersede would be a silent write to a stranger.
                return {
                    Supersedes: current,
                    Released: released,
                    Refused:
                        'That contract is no longer superseded by this agreement, so there was nothing ' +
                        'to release. The list has been refreshed.',
                };
            }
            const previous = await provider.GetEntityObject<ContractEntity>(E_CONTRACT, user);
            if (!(await previous.Load(target.ID))) {
                throw new Error('The contract to be released could not be loaded.');
            }
            previous.SupersededByContractID = null;
            if (!(await previous.Save())) {
                return {
                    Supersedes: await this.readSupersedes(provider, user, input.SuccessorID),
                    Released: released,
                    Refused: previous.LatestResult?.Message ??
                        `Could not release ${target.ContractNumber}; nothing else was changed.`,
                };
            }
            released.push(target.ContractNumber);
        }

        // ── Add a predecessor, leaving the existing ones in place (item 10) ───────────────────────
        if (
            input.PredecessorID &&
            !same(input.PredecessorID, input.SuccessorID) &&
            !current.some((c) => same(c.ID, input.PredecessorID))
        ) {
            const predecessor = await provider.GetEntityObject<ContractEntity>(E_CONTRACT, user);
            if (!(await predecessor.Load(input.PredecessorID))) {
                throw new Error('The contract to be superseded could not be loaded.');
            }
            // Through Supersede(), not a bare field write, so the entity keeps owning the rule.
            predecessor.Supersede(successor);
            if (!(await predecessor.Save())) {
                return {
                    Supersedes: await this.readSupersedes(provider, user, input.SuccessorID),
                    Released: released,
                    // The server guards produce field-named prose (same-level, self-reference, cycles);
                    // that message is far more use than "the save failed".
                    Refused: predecessor.LatestResult?.Message ?? 'That contract could not be marked superseded.',
                };
            }
        }

        return {
            Supersedes: await this.readSupersedes(provider, user, input.SuccessorID),
            Released: released,
        };
    }

    /** Live read of what a contract supersedes — returned to the caller so its list is never cached. */
    private async readSupersedes(
        provider: IMetadataProvider,
        user: UserInfo,
        successorID: string,
    ): Promise<Array<{ ID: string; ContractNumber: string }>> {
        const rv = RunView.FromMetadataProvider(provider);
        const r = await rv.RunView<{ ID: string; ContractNumber: string }>(
            {
                EntityName: E_CONTRACT,
                Fields: ['ID', 'ContractNumber'],
                ExtraFilter: `SupersededByContractID = '${successorID.replace(/'/g, "''")}'`,
                OrderBy: 'ContractNumber ASC',
                ResultType: 'simple',
            },
            user,
        );
        return r?.Success ? r.Results : [];
    }
}

/** Anti-tree-shake anchor — without a live reference the @RegisterClass side effect can be dropped. */
export function LoadSupersedeOperation(): void {
    // no-op
}
