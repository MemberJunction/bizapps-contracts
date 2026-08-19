/**
 * @mj-biz-apps/contracts-entities — the app's ENTITY package. SHARED: browser and server both load
 * it, so nothing server-only may leak in here.
 *
 * WHAT LIVES HERE
 *   src/generated/entity_subclasses.ts — written by MemberJunction CodeGen. One strongly-typed
 *     BaseEntity subclass + zod schema per table. COMMIT it; the committed code is what consumers
 *     install, and CodeGen on a clean branch is an expected no-op.
 *   src/*.ts — hand-written shared subclasses carrying the rules that must run in BOTH places
 *     (plan §6.3): validation the browser can preflight and the server enforces.
 *
 * PEER DEPENDENCIES (docs/template-docs/versioning-and-peer-deps.md): @memberjunction/core + global
 * are PEERS (^X.Y.Z), never hard deps — exactly one copy of each may exist in a host process; a
 * second copy splits MJ's class factory and silently breaks registration.
 *
 * NOT HERE ANY MORE: v1's `contract-draft.ts` (688 lines). A browser could not compose a contract
 * tree through BaseEntity, so v1 shipped a draft payload and a remote operation to rehydrate it.
 * MJ 6 related-record collections make the graph save native (plan §6.3), so the draft, its
 * operation and its hydrator all died with the rebuild.
 */
export * from './generated/entity_subclasses';

/* NOTE on `src/generated/remote_operations.ts`: CodeGen writes it, and it is deliberately NOT
 * re-exported. v2 ships zero remote operations (plan §6.3), so every symbol in that file is an
 * MJ-CORE operation (AISkill, PredictiveStudio, TaskGraph, …) emitted into every app's file
 * regardless of `includeSchemas`. Re-exporting them would make this package appear to own MJ core's
 * write API. Filed as an upstream CodeGen scoping question — see MJ-UPSTREAM.md. */
