import { defineConfig } from 'vitest/config';

/**
 * Unit-tier config for the INTEGRATION package.
 *
 * The checks themselves need a database and do not run here — `test-harnesses/integration.mjs` runs
 * those. What runs here is `registry-parity.test.ts`, which needs no environment at all: it imports
 * the bundles for their registration side effect and asserts the shape of the registry.
 *
 * That is deliberate. The parity floor is the one part of the integration suite a CI runner CAN
 * honestly execute, and it is the part that catches a suite silently shrinking.
 */
export default defineConfig({
    test: {
        include: ['src/**/__tests__/**/*.test.ts'],
        environment: 'node',
    },
});
