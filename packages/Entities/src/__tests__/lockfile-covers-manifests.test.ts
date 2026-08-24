/**
 * Every declared dependency is in the lockfile.
 *
 * WHY THIS EXISTS. I broke `pnpm install --frozen-lockfile` twice in one branch, the same way each
 * time: added a dependency to a `package.json`, refreshed the lockfile in a throwaway clone (because
 * a refresh must never run inside the instance's pnpm workspace — it would split-brain the store),
 * and forgot to copy the refreshed lockfile back into the commit. Both times the commit message
 * claimed the refresh had happened.
 *
 * Twice is a pattern, and this repo's habit is that a pattern gets a prevention-shaped assertion
 * rather than another apology. The failure is otherwise invisible locally — the instance workspace
 * has its own resolution, so everything builds and tests pass on the machine that made the mistake,
 * and only a clean `--frozen-lockfile` install elsewhere notices.
 *
 * Scope: `dependencies` and `devDependencies` only. `peerDependencies` are deliberately excluded —
 * pnpm does not install a peer into the declaring package's importer (`auto-install-peers=false`
 * here), so a peer legitimately has no importer entry. That distinction is the whole reason a naive
 * "every name in the lockfile" check would produce noise and get deleted.
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const ROOT = fileURLToPath(new URL('../../../../', import.meta.url));
const LOCKFILE = ROOT + 'pnpm-lock.yaml';

/**
 * Parse the lockfile's `importers:` section into `{ importerPath: Set<dependencyName> }`.
 *
 * Hand-parsed rather than pulled through a YAML library on purpose: the shape being read is two
 * levels of a known, machine-generated file, and adding a parser dependency to make one assertion is
 * a worse trade than twenty lines that fail loudly if the format moves. `expect(importers.size)`
 * below is what catches a format change — an empty parse would otherwise make this test vacuous,
 * which is the failure mode of every hand-rolled parser in a test.
 */
function parseImporters(lock: string): Map<string, Set<string>> {
    const lines = lock.split('\n');
    const importers = new Map<string, Set<string>>();
    let inImporters = false;
    let current: string | null = null;

    for (const line of lines) {
        if (/^importers:\s*$/.test(line)) {
            inImporters = true;
            continue;
        }
        if (!inImporters) continue;
        // A new top-level key ends the importers section.
        if (/^\S/.test(line)) break;

        // Importer paths sit at exactly two spaces: "  .:" or "  packages/Angular:"
        const importer = line.match(/^ {2}(\S.*):\s*$/);
        if (importer) {
            current = importer[1].replace(/^['"]|['"]$/g, '');
            importers.set(current, new Set());
            continue;
        }
        // Dependency names sit at exactly six spaces under a dependencies/devDependencies block.
        const dep = line.match(/^ {6}('?[@\w][^:']*'?):\s*$/);
        if (dep && current) {
            importers.get(current)!.add(dep[1].replace(/^'|'$/g, ''));
        }
    }
    return importers;
}

const lock = existsSync(LOCKFILE) ? readFileSync(LOCKFILE, 'utf8') : '';
const importers = parseImporters(lock);

/** Every package.json that pnpm treats as a workspace importer: the root plus each packages/* dir. */
function manifests(): Array<{ importer: string; path: string }> {
    const out = [{ importer: '.', path: ROOT + 'package.json' }];
    for (const dir of readdirSync(ROOT + 'packages')) {
        const p = `${ROOT}packages/${dir}/package.json`;
        if (existsSync(p)) out.push({ importer: `packages/${dir}`, path: p });
    }
    return out;
}

describe('pnpm-lock.yaml covers every declared dependency', () => {
    it('the lockfile parsed at all', () => {
        // Guards the whole suite against becoming vacuous if the lockfile format changes.
        expect(lock.length, 'pnpm-lock.yaml is missing or empty').toBeGreaterThan(0);
        expect(importers.size, 'parsed no importers — the lockfile format may have changed').toBeGreaterThan(1);
        expect(importers.has('.'), 'no root importer found').toBe(true);
    });

    for (const { importer, path } of manifests()) {
        it(`${importer}: every dependency and devDependency is locked`, () => {
            const pkg = JSON.parse(readFileSync(path, 'utf8')) as {
                dependencies?: Record<string, string>;
                devDependencies?: Record<string, string>;
            };
            const declared = [...Object.keys(pkg.dependencies ?? {}), ...Object.keys(pkg.devDependencies ?? {})];
            const locked = importers.get(importer);

            expect(locked, `lockfile has no importer entry for "${importer}"`).toBeDefined();
            const missing = declared.filter((d) => !locked!.has(d));
            expect(
                missing,
                `${importer}/package.json declares ${missing.length} dependency(ies) absent from the ` +
                    `lockfile: ${missing.join(', ')}. Refresh it with \`pnpm install --lockfile-only\` in a ` +
                    `THROWAWAY CLONE (never inside the instance workspace) and COPY THE RESULT BACK — ` +
                    `forgetting the copy-back is exactly what this test exists to catch.`,
            ).toEqual([]);
        });
    }
});
