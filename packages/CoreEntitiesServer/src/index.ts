/**
 * @mj-biz-apps/contracts-core-entities-server — SERVER-ONLY entity subclasses. This package must
 * NEVER be imported by client code; it is a dependency of the Server package only.
 *
 * WHAT BELONGS HERE, AND WHAT DOES NOT (plan §6.3). A rule lives here only when it CANNOT run in
 * the browser — it needs a transaction, a lock, or a cross-entity read the client has no business
 * doing. Everything the browser should be able to preflight lives on the SHARED subclass in
 * @mj-biz-apps/contracts-entities instead, so the user sees the error before the round trip.
 *
 * Dependency shape in package.json: the sibling app package (@mj-biz-apps/contracts-entities) is a
 * HARD dependency pinned to the same version (all app packages version together via changesets
 * `fixed`); every @memberjunction/* package is a PEER (^X.Y.Z).
 *
 * WHAT THE REBUILD DELETED. v1's nine `*EntityServer`s, `ContractsEngine`, `ChildCollection`,
 * `BillingDraft` and all seven remote operations — the billing engine wholesale. v2 is a
 * record-keeping app: it has no billing engine, and MJ 6's graph save replaced the hand-rolled
 * composition machinery (plan §6.3). The v2 contents are two subclasses, arriving with item 3.
 */

/**
 * Called by the server bootstrap. When subclasses land here, their imports are what fire
 * @RegisterClass and the calls below are anti-tree-shake anchors — without a live reference a
 * production build can drop the import and the subclass silently never registers, so every
 * invariant in it stops existing with no error.
 */
export function LoadMjBizappsContractsEntitiesServer(): void {
    /* item 3: LoadContractEntityServer(); LoadContractTemplateModificationEntityServer(); */
}
