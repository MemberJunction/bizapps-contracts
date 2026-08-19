/**
 * Find and load the instance's `.env`, whichever workspace topology this app is sitting in.
 *
 * WHY THIS IS NOT JUST `dotenv.config()`. The harness scripts used a fixed relative path —
 * `resolve(here, '..', '..', '..', '..', '.env')` — which was correct for the pre-6.x NESTED layout,
 * where an app lived at `<instance>/mj/packages/dev-apps/<app>/` so four levels up from
 * `test-harnesses/` landed on the MJ worktree root. MJ 6.x / pnpm uses the PARENT-WORKSPACE topology:
 * the app is a flat sibling of `mj/` at `<instance>/<app>/`, so the same four levels now land on
 * `~/MJDev` and find nothing.
 *
 * The failure is not a missing-file error, which is what made it expensive: `dotenv` silently does
 * nothing when the path does not exist, so `DB_PORT` stays undefined, the connection falls back to
 * 1433, and the script dies with "Failed to connect to localhost:1433" — which reads like Docker
 * being down rather than a path bug. That is how a committed harness came to be unrunnable without
 * anyone noticing.
 *
 * So: walk UP from this file and take the first `.env` found, checking `<dir>/.env` and then
 * `<dir>/mj/.env` at each level. That resolves both topologies and any future one, because it asks
 * the filesystem instead of counting directories. An app-local `.env` still wins — it is loaded last
 * and `dotenv` does not overwrite already-set values, so the search order is most-specific-first.
 *
 * @module test-harnesses/load-env
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

/**
 * Load the first `.env` found walking up from `startDir`, plus the app-local one if present.
 *
 * @param {string} startDir directory to start the upward walk from
 * @returns {{ loaded: string[], searched: number }} which files were loaded, and how many dirs we looked in
 */
export function loadInstanceEnv(startDir) {
    const loaded = [];
    // App-local first: dotenv never overwrites an already-set key, so whatever is loaded first wins.
    const appLocal = path.resolve(startDir, '..', '.env');
    if (fs.existsSync(appLocal)) {
        dotenv.config({ path: appLocal, quiet: true });
        loaded.push(appLocal);
    }

    let dir = path.resolve(startDir);
    let searched = 0;
    // Stop at the filesystem root: path.dirname('/') === '/'.
    while (searched < 12) {
        for (const candidate of [path.join(dir, '.env'), path.join(dir, 'mj', '.env')]) {
            if (fs.existsSync(candidate) && !loaded.includes(candidate)) {
                dotenv.config({ path: candidate, quiet: true });
                loaded.push(candidate);
            }
        }
        // The instance env is the one that carries DB_*; once we have it, stop climbing.
        if (process.env.DB_DATABASE) break;
        const parent = path.dirname(dir);
        if (parent === dir) break;
        dir = parent;
        searched++;
    }
    return { loaded, searched };
}

/** Convenience for the common case: resolve relative to the calling module's own directory. */
export function loadEnvFrom(importMetaUrl) {
    return loadInstanceEnv(path.dirname(fileURLToPath(importMetaUrl)));
}
