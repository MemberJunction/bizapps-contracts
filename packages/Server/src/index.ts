/**
 * @mj-biz-apps/contracts-server — the SERVER BOOTSTRAP package.
 *
 * This is the package named in mj-app.json under packages.server with
 * role "bootstrap". At startup MJAPI dynamically imports it and calls the
 * function named by "startupExport" (LoadMjBizappsContractsServer below). That call —
 * plus the imports in this file — fires every @RegisterClass decorator in
 * this app's server-side packages, which is how MJ discovers your entities,
 * actions, and resolvers. Nothing else wires your code in.
 *
 * WHAT LIVES HERE
 *   src/generated/  — CodeGen GraphQLServer output (resolvers; do not edit)
 *   src/            — hand-written resolvers / engines / providers
 *
 * THE RESOLVERS ARE WIRED BELOW, and both halves are required. Importing
 * './generated/generated.js' fires its @Resolver registrations; exporting
 * RESOLVER_PATHS is what lets MJAPI pass the files to createMJServer() so the
 * types actually land in the GraphQL schema.
 *
 * Skipping either half fails in a way that looks like an app bug rather than a
 * wiring one: MJAPI boots clean, the app appears, reads work — and the first WRITE
 * dies with `Unknown type "Create<Entity>Input"` from the client, because the
 * mutation was never in the schema. The startup line is the tell: an app with
 * resolvers logs "(+N resolver paths)"; this app logged none.
 */
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

import { LoadMjBizappsContractsEntitiesServer } from '@mj-biz-apps/contracts-core-entities-server';
import { LoadMjBizappsContractsActions } from '@mj-biz-apps/contracts-actions';

// Generated GraphQL resolvers — the import fires their registrations.
import './generated/generated.js';
export * from './generated/generated.js';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

/**
 * Absolute paths to the resolver files, for createMJServer(). The `*Resolver.{js,ts}` suffix on the
 * custom line is deliberate: `*.{js,ts}` would also match emitted `*.d.ts`, which then fails to load.
 */
export const RESOLVER_PATHS = [
    resolve(__dirname, 'generated/generated.{js,ts}'),
    resolve(__dirname, 'resolvers/*Resolver.{js,ts}'),
];

export function LoadMjBizappsContractsServer(): void {
    // Chain the sub-package loaders so a single startupExport call registers
    // everything. Importing the modules is what triggers @RegisterClass.
    LoadMjBizappsContractsEntitiesServer();
    LoadMjBizappsContractsActions();
}
