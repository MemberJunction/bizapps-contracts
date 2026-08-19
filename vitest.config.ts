import { defineConfig } from 'vitest/config';

/**
 * Root vitest config, so `vitest run` means the same thing everywhere — locally and in CI. Mirrors
 * bizapps-orders, deliberately: a developer moving between the family's apps should not have to learn
 * a second test layout.
 *
 * Each package's tests are independent and none of them touch a database, so there is no ordering
 * requirement to preserve. `passWithNoTests: false` is the point of the setting — a config that
 * silently passes when its glob matches nothing is how a whole suite goes missing without failing.
 */
export default defineConfig({
    test: {
        include: ['packages/*/src/**/*.test.ts'],
        passWithNoTests: false,
    },
});
