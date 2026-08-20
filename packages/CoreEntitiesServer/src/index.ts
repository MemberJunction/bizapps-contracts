/**
 * @mj-biz-apps/contracts-core-entities-server — SERVER-ONLY entity subclasses. This package must
 * NEVER be imported by client code; it is a dependency of the Server package only.
 *
 * WHAT BELONGS HERE, AND WHAT DOES NOT (plan §6.3). A rule lives here only when it CANNOT run in the
 * browser — it needs a transaction, a lock, or a cross-entity read the client has no business doing.
 * Everything the browser should be able to preflight lives on the SHARED subclass in
 * @mj-biz-apps/contracts-entities instead, so the user sees the error before the round trip.
 *
 * Dependency shape in package.json: the sibling app package (@mj-biz-apps/contracts-entities) is a
 * HARD dependency pinned to the same version (all app packages version together via changesets
 * `fixed`); every @memberjunction/* package is a PEER (^X.Y.Z).
 *
 * TWO SUBCLASSES, and that is the whole server surface. v1 had nine of these plus ContractsEngine,
 * ChildCollection, BillingDraft and seven remote operations — the billing engine wholesale. v2 is a
 * record-keeping app and MJ 6's graph save replaced the composition machinery, so what is left is
 * the contract number (needs a lock) and two modification invariants (need cross-entity reads).
 * **Zero remote operations.**
 */
import { LoadContractEntityServer } from './ContractEntityServer.js';
import { LoadContractTemplateEntityServer } from './ContractTemplateEntityServer.js';
import { LoadContractTemplateProvisionEntityServer } from './ContractTemplateProvisionEntityServer.js';
import { LoadContractTypeEntityServers } from './ContractTypeEntityServers.js';
import { LoadContractTemplateModificationEntityServer } from './ContractTemplateModificationEntityServer.js';

export { ContractEntityServer, IsNewlySelected, LoadContractEntityServer } from './ContractEntityServer.js';
export {
    ContractTemplateModificationEntityServer,
    LoadContractTemplateModificationEntityServer,
} from './ContractTemplateModificationEntityServer.js';
export { ContractTemplateEntityServer, LoadContractTemplateEntityServer } from './ContractTemplateEntityServer.js';
export {
    ContractTemplateProvisionEntityServer,
    LoadContractTemplateProvisionEntityServer,
} from './ContractTemplateProvisionEntityServer.js';
export {
    ContractTemplateTypeEntityServer,
    ContractTypeEntityServer,
    LoadContractTypeEntityServers,
} from './ContractTypeEntityServers.js';
export * from './delete-guard.js';

/**
 * Called by the server bootstrap. The imports above are what fire @RegisterClass; these calls are
 * anti-tree-shake anchors — without a live reference a production build can drop the import and the
 * subclasses silently never register, so every invariant in them stops existing with no error.
 */
export function LoadMjBizappsContractsEntitiesServer(): void {
    LoadContractEntityServer();
    LoadContractTemplateModificationEntityServer();
    // R-8's delete guards. These have NO Validate/Save rules at all, so a dropped registration is
    // completely silent: deletes keep being refused by the FK, just with a constraint name again.
    LoadContractTemplateEntityServer();
    LoadContractTemplateProvisionEntityServer();
    LoadContractTypeEntityServers();
}
