# 7 · Code style

## Naming (MJ's signature convention)

- **PascalCase for ALL public class members** — properties, methods,
  `@Input()`/`@Output()` (`public IsLoading`, `public LoadData()`,
  `@Input() QueryId`). This is deliberate MJ style, not standard TS.
- **camelCase for private/protected members** (`private destroy$`,
  `protected applyVisualConfig()`).
- camelCase for locals and parameters; PascalCase for classes/interfaces.
- Descriptive names; no abbreviations.
- Prefer **union types over enums** (`type Status = 'active' | 'inactive'`) —
  friendlier package exports.
- Null checks with `!= null` (catches both `null` and `undefined`).

## Functional decomposition is mandatory

- Max ~30–40 lines per function (excluding comments). Longer → refactor now.
- Decompose when: you'd need a comment to explain a section; nesting exceeds
  2 levels; the name would need "And" to be accurate; logic patterns repeat.
- Each function has one clear purpose; well-named helpers beat inline blocks
  (readability, testability, meaningful stack traces).

## DRY / OO design

- 3+ classes with similar structure ⇒ a base class. Repeated parameter
  validation / error handling / entity helpers ⇒ shared utilities.
- Actions are **boundaries** (agents, workflows, low-code) — never a
  code-to-code call mechanism. Internal code imports the underlying classes
  directly (type safety, no metadata overhead, honest stack traces). Keep
  actions thin; delegate to service classes.

## Miscellany

- Group imports: external, internal, relative.
- TSDoc on public APIs.
- try/catch with meaningful messages — but remember `RunView`/`Save`/`Delete`
  signal failure via return values, not exceptions (doc 3).
