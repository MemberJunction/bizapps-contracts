# 9 · Testing

## The framework

**Vitest** is MJ's standard (Jest is deprecated). Unit suites live in
`CoreEntitiesServer`, `Entities`, `Angular` and `IntegrationTests`, under
`src/**/__tests__/`. `Actions` and `Server` have none yet: their `test` script
only echoes a message, so a green run there proves nothing.

## Running

```sh
pnpm run build:packages                         # tests import sibling packages from dist/
pnpm run test:unit                              # root vitest.config.ts — what CI runs
pnpm test                                       # turbo `test` in every package (cached)
cd packages/X && pnpm test                      # one package
pnpm exec vitest                                # watch mode, root config
pnpm exec turbo run test --filter=...[HEAD~1]   # only changed packages
```

Database-backed checks need a database with this app migrated and an `.env`
(`test-harnesses/load-env.mjs` finds it):

```sh
pnpm run test:integration    # the integration-check bundles (test-harnesses/integration.mjs)
pnpm run test:state          # vwContracts State derivation, against the live view
pnpm run test:parent-rule    # MustBeRoot / MustBeChild, through BaseEntity saves
```

## Writing

- Files under `src/**/__tests__/`, named `<topic>.test.ts`; the root config
  collects `packages/*/src/**/*.test.ts` and fails when it finds none.
- `import { describe, it, expect, vi, beforeEach } from 'vitest'`.
- **No database connections in unit tests** — mock externals (`vi.fn`,
  `vi.mock`).
- Deterministic and fast (< 5s per file). Descriptive names that read as
  specifications; cover the normal case, edge cases, and invalid input.

```typescript
describe('MyClass', () => {
  beforeEach(() => { /* reset state */ });
  describe('MyMethod', () => {
    it('handles the normal case', () => { ... });
    it('handles edge case: empty input', () => { ... });
    it('throws on invalid input', () => { ... });
  });
});
```

## Expectations

- Changing a package = running its tests before done; broken tests are yours
  to fix (renames, changed signatures/returns, new required params — all of it).
- Every PR must be green in CI before merge.
- Report results: pass/fail/skip counts, and what wasn't run.
