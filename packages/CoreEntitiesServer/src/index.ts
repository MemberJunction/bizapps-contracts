/**
 * @mj-biz-apps/contracts-core-entities-server — SERVER-ONLY entity subclasses
 * (OPTIONAL — delete if you have no server-side entity logic).
 *
 * Override generated entities here to add server-side behavior: validation,
 * cross-record invariants (ValidateAsync — not DB triggers), Save() hooks,
 * FK cleanup before delete. This package must NEVER be imported by client
 * code — it is a dependency of the Server package only.
 *
 * NOTE the dependency shape in package.json: the sibling app package
 * (@mj-biz-apps/contracts-entities) is a HARD dependency pinned to the exact same
 * version (all app packages version together via changesets `fixed`), while
 * every @memberjunction/* package is a PEER (^X.Y.Z).
 *
 * EXAMPLE — override a generated entity's Save():
 *
 *   import { RegisterClass } from '@memberjunction/global';
 *   import { BaseEntity } from '@memberjunction/core';
 *   import { SampleRecordEntity } from '@mj-biz-apps/contracts-entities';
 *
 *   @RegisterClass(BaseEntity, 'Sample App: Sample Records')
 *   export class SampleRecordEntityServer extends SampleRecordEntity {
 *       public override async Save(): Promise<boolean> {
 *           // server-side enrichment / invariants here
 *           return super.Save();
 *       }
 *   }
 */
import { LoadContractEntityServer } from './ContractEntityServer.js';
import { LoadContractTermEntityServer } from './ContractTermEntityServer.js';
import { LoadContractEventEntityServer } from './ContractEventEntityServer.js';
import { LoadContractBillingEventEntityServer } from './ContractBillingEventEntityServer.js';
import { LoadActivateTermOperation } from './ActivateTermOperation.js';
import { LoadRenewTermOperation } from './RenewTermOperation.js';
import { LoadTerminateContractOperation } from './TerminateContractOperation.js';

export { ContractEntityServer, LoadContractEntityServer } from './ContractEntityServer.js';
export { ContractTermEntityServer, LoadContractTermEntityServer } from './ContractTermEntityServer.js';
export { ContractEventEntityServer, LoadContractEventEntityServer } from './ContractEventEntityServer.js';
export { ContractBillingEventEntityServer, LoadContractBillingEventEntityServer } from './ContractBillingEventEntityServer.js';

// The lookup cache. Exported so callers outside this package can read a contract type's rules
// without another RunView — and so the CONVENTION matches OrdersEngine, which is exported the same
// way from the same position in the orders package.
export { ContractsEngine, LoadContractsEngine } from './ContractsEngine.js';

// Remote operations — the write API the UI calls. State changes live here rather than in Actions:
// orders settled that split for the family (Actions are for agent/workflow-invocable work; the
// operations that MUTATE are the callable API), and consistency across the apps is worth more than
// this app's original plan text, which said Actions. Raised on PR #2 rather than changed silently.
export { ActivateTermOperation, LoadActivateTermOperation } from './ActivateTermOperation.js';
export type { ActivateTermInput, ActivateTermOutput } from './ActivateTermOperation.js';
export { RenewTermOperation, LoadRenewTermOperation } from './RenewTermOperation.js';
export type { RenewTermInput, RenewTermOutput, RenewedLine } from './RenewTermOperation.js';
export { TerminateContractOperation, LoadTerminateContractOperation } from './TerminateContractOperation.js';
export type { TerminateContractInput, TerminateContractOutput } from './TerminateContractOperation.js';

/**
 * Called by the server bootstrap. The imports above are what fire @RegisterClass; these calls are
 * anti-tree-shake anchors — without a live reference a production build can drop the import and the
 * subclasses silently never register, so every invariant in them stops existing with no error.
 */
export function LoadMjBizappsContractsEntitiesServer(): void {
    LoadContractEntityServer();
    LoadContractTermEntityServer();
    LoadContractEventEntityServer();
    LoadContractBillingEventEntityServer();
    LoadActivateTermOperation();
    LoadRenewTermOperation();
    LoadTerminateContractOperation();
}
