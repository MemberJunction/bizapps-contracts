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

/* Hand-written SHARED subclasses. Rules that must run in BOTH tiers live here, so the browser
 * refuses before the round trip and the server refuses regardless (plan §6.3). */
export * from './ContractEntity';

/* The modification's three required fields, re-explained. It adds NO rule — the NOT NULL metadata is
 * the rule — it only replaces MJ's "<field> cannot be null" with a sentence that says what to do. */
export * from './ContractTemplateModificationEntity';

/* The provision's required fields, re-explained. Same shape and the same shared mechanism as the
 * modification's — `ProvisionText` became required in V202608200800. */
export * from './ContractTemplateProvisionEntity';

/* The template's publication lifecycle. Draft is editable and unreferenceable; Published is frozen by
 * a trigger. The subclass carries the transition rule the trigger cannot see: publishing is one-way. */
export * from './ContractTemplateEntity';
export * from './required-field-prose';

/* The two lookup entities, which exist ONLY to validate their value-list columns — a rule MJ does not
 * yet provide (MJ#3969). Deleted wholesale when it lands; see value-list-validation.ts. */
export * from './ContractTypeEntity';
export * from './value-list-validation';

/* The lifecycle rule, stated once and rendered two ways (D-19 / R-19). Exported because the UI needs
 * DeriveContractState to show a state that tracks UNSAVED edits — reading the view's stored column
 * would contradict the form on screen — and because StateSQL() is what the migration's CASE is checked
 * against by contract-state.test.ts. */
export * from './contract-state';

/** Which contracts the Supersedes picker may offer, and how it names them (#28 item 4). */
export * from './supersede-candidates';

/* Which DEALS the Source-record picker may offer, and how it names them (golive #219). Name-only:
 * sales depends on this app, so the link stays polymorphic and is resolved from metadata at runtime. */
export * from './source-record-candidates';

/* Which template a NEW contract starts with, and when we may write it there (golive #218). The
 * Agreement panel owns the query; the decisions inside it live here, where a unit test reaches them
 * without standing up Angular's DI. */
export * from './default-template';

/* Seeding the four renewal fields from the Contract Type (golive #217 / C-US1). The pure decision;
 * the I/O half is `ContractEntity.SeedRenewalDefaultsFromType()`. Exported because the form panel
 * needs the field list and the `ContractRenewalField` type, and the tests assert the decision
 * directly rather than restating it. */
export * from './renewal-defaults';

/* The file category that clears IsAwaitingDocument (golive #203 item 16 / #213). One spelling, shared by
 * the view, the migration seed and the form panel that marks a file. */
export * from './executed-agreement';

/* NOTE on `src/generated/remote_operations.ts`: CodeGen writes it, and it is deliberately NOT
 * re-exported. v2 ships zero remote operations (plan §6.3), so every symbol in that file is an
 * MJ-CORE operation (AISkill, PredictiveStudio, TaskGraph, …) emitted into every app's file
 * regardless of `includeSchemas`. Re-exporting them would make this package appear to own MJ core's
 * write API. Filed as an upstream CodeGen scoping question — see MJ-UPSTREAM.md. */
