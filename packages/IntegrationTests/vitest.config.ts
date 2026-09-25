/**
 * Package-local config, so `vitest run` here does not fall through to the repo root's.
 *
 * Without this file vitest walks upward and loads the root vitest.config.ts, whose include
 * (`packages/*\/src/**\/*.test.ts`) is resolved against this package's directory and matches nothing —
 * `pnpm test` then fails with "No test files found" while the suite below goes unrun. The test script
 * deliberately has no `--passWithNoTests`: an empty match here means the suite has gone missing.
 */
import { defineConfig } from 'vitest/config';

export default defineConfig({
    test: {
        include: ['src/**/__tests__/**/*.test.ts'],
        environment: 'node',
        globals: false,
    },
});
