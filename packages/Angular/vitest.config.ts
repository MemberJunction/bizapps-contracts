/**
 * Tier 1 only — pure logic, no Angular compilation.
 *
 * Deliberately NOT the Analog/AOT setup a component test would need: everything under test here is a
 * plain function of its arguments, so pulling in the Angular compiler would add minutes of build for
 * nothing. Component-level testing is tier 4 and is a separate, opt-in scaffold.
 */
import { defineConfig } from 'vitest/config';

export default defineConfig({
    test: {
        include: ['src/**/__tests__/**/*.test.ts'],
        environment: 'node',
        globals: false,
    },
});
