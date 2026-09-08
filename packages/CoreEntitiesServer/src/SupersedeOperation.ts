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
 * ADD, NOT REPLACE -- REVERSED 2026-08-30 (contracts#28 item 10). The previous reasoning is kept
 * here because it was deliberate rather than careless, and knowing why it was wrong is the point.
 * This module used to argue: the schema allows many predecessors to name one successor, the picker is
 * a single-select, therefore one predecessor is the intent, therefore release the others before
 * linking. The premise was the wrong way round. A consolidated agreement really does replace several
 * earlier ones, and a single-select picker is how you ADD them one at a time -- so "replace" meant
 * picking a second contract silently released the first, its only trace a "Released ..." suffix on a
 * success message that reads like reassurance rather than a warning.
 *
 * So: LINKING ADDS. Contracts this agreement already supersedes are left exactly as they are. Removal
 * is explicit and singular, through `ReleasePredecessorID`, which clears the one contract named and no
 * other -- item 9, where the panel passed the clicked ID to a handler that discarded it and released
 * every predecessor.
 *
 * There is deliberately NO "release everything" input any more. A call carrying neither ID is REFUSED
 * rather than quietly treated as one, because the old shape (`PredecessorID: null`) meant exactly that,
 * and a stale caller sending it should be told rather than silently change nothing.
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
     * Link this contract as a predecessor. ADDS — whatever this agreement already supersedes is left
     * exactly as it is, because one agreement may legitimately replace several.
     */
    PredecessorID?: string | null;
    /**
     * Release this ONE predecessor and no other. Named separately from `PredecessorID` so the two
     * intentions cannot be confused: no value of `PredecessorID` means "unlink".
     */
    ReleasePredecessorID?: string | null;
}

export interface SupersedeOutput {
    /** What the successor supersedes AFTER the operation — the panel renders this, so it can never be stale. */
    Supersedes: Array<{ ID: string; ContractNumber: string }>;
    /** Contract numbers released by this call. */
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

        const successor = await provider.GetEntityObject<ContractEntity>(E_CONTRACT, user);
        if (!(await successor.Load(input.SuccessorID))) {
            throw new Error('The contract doing the superseding could not be loaded.');
        }

        const released: string[] = [];
        const same = (a: string | null | undefined, b: string | null | undefined) =>
            !!a && !!b && a.toLowerCase() === b.toLowerCase();

        const toLink = input.PredecessorID ?? null;
        const toRelease = input.ReleasePredecessorID ?? null;

        // REFUSED, NOT READ AS "RELEASE EVERYTHING". Until 2026-08 a null `PredecessorID` with nothing
        // else meant "clear every predecessor" — the behaviour item 10 removed. A caller still sending
        // that shape would otherwise get a green result that changed nothing at all.
        if (!toLink && !toRelease) {
            throw new Error(
                'Supersede needs either PredecessorID (link one) or ReleasePredecessorID (release one); ' +
                    'it received neither. A null PredecessorID used to mean "release every predecessor" — ' +
                    'that meaning is gone, so this refuses rather than silently doing nothing.',
            );
        }

        // ONE predecessor: the one named. The old loop walked every predecessor and cleared all but the
        // one being linked, which is how clicking "Unlink CTR-0001" also unlinked CTR-0002 (item 9).
        if (toRelease) {
            const current = (await this.readSupersedes(provider, user, input.SuccessorID))
                .find((c) => same(c.ID, toRelease));
            if (!current) {
                // Not silence: the caller believes this contract is a predecessor and it is not, so say
                // so. A concurrent unlink elsewhere lands here, and the returned list shows the truth.
                return {
                    Supersedes: await this.readSupersedes(provider, user, input.SuccessorID),
                    Released: released,
                    Refused: 'That contract is not superseded by this agreement, so there was nothing to release.',
                };
            }
            const previous = await provider.GetEntityObject<ContractEntity>(E_CONTRACT, user);
            if (!(await previous.Load(current.ID))) {
                throw new Error(`The contract to release (${current.ContractNumber}) could not be loaded.`);
            }
            previous.SupersededByContractID = null;
            if (!(await previous.Save())) {
                return {
                    Supersedes: await this.readSupersedes(provider, user, input.SuccessorID),
                    Released: released,
                    Refused: previous.LatestResult?.Message ??
                        `Could not release ${current.ContractNumber}; nothing else was changed.`,
                };
            }
            released.push(current.ContractNumber);
        }

        if (toLink && same(toLink, input.SuccessorID)) {
            // Was a silent skip that reported success having done nothing. ContractEntity.Supersede()
            // refuses this anyway; saying so is more use than a green message.
            return {
                Supersedes: await this.readSupersedes(provider, user, input.SuccessorID),
                Released: released,
                Refused: 'A contract cannot supersede itself.',
            };
        }

        if (toLink) {
            const predecessor = await provider.GetEntityObject<ContractEntity>(E_CONTRACT, user);
            if (!(await predecessor.Load(toLink))) {
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
