# 9 · Testing

## The framework

**Vitest** is MJ's standard (Jest is deprecated). This template's packages
ship `"test"` script stubs — replace them with real suites as you add code;
a stubbed test passing vacuously is a latent failure wearing a green light.

## Running

```sh
npm test                                   # all packages (turbo, cached)
cd packages/X && npm run test              # one package
npm run test:watch                         # watch mode (per package)
npx turbo run test --filter=...[HEAD~1]    # only changed packages
```

## Writing

- Files in `src/__tests__/`, named `<Source>.test.ts`, one per source file.
- `import { describe, it, expect, vi, beforeEach } from 'vitest'`.
- **No database connections in unit tests** — mock externals
  (`@memberjunction/test-utils` has singleton-reset, mock entities, mock
  RunView helpers).
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
- Report results honestly: pass/fail/skip counts, and what wasn't run.
