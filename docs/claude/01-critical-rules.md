# 1 · Critical rules (violations are unacceptable)

The hard rules from MJ's CLAUDE.md. Everything else in this guide is
convention; these are contract.

## No commits without explicit approval
Never run `git commit` unless the user explicitly asked for that commit — each
commit needs one-time approval. Commit only what is staged; never fold extra
work into someone's staged changes.

## No `any` types — ever
No `: any`, `as any`, `<any>`, or `unknown`-as-a-shortcut. MJ is strongly
typed end-to-end; there is always a proper type. Corollaries:

- **Never** use `BaseEntity.Get('Field')`/`.Set('Field', v)` where a generated
  typed property exists (they're the `any` of the entity world — no
  IntelliSense, silent typo failures). If the types don't exist yet because
  CodeGen hasn't run, run the migration + CodeGen **first**, then write code.
- **Never hand-copy a value-list union** — derive field types from the entity:
  `MyEntity['Status']`, not `'Active' | 'Inactive'` retyped by hand. Hand
  copies silently drift when a migration widens the CHECK constraint.

## No destructive git operations without explicit approval
No `git checkout -- <file>` / `git restore` / `git reset --hard` to discard
changes without approval — they destroy uncommitted work irrecoverably. To
undo your own edits, reverse them with targeted edits instead.

## No re-exports between packages
Import types/classes from the package that defines them. A package's
`index.ts`/`public-api.ts` exports only what that package defines. Re-exports
obscure the true source and break tree-shaking. (The one sanctioned pattern:
re-exporting your OWN generated module from your own public-api.)

## No dynamic `import()` unless narrowly justified
Static imports at the top of the file, always. Dynamic import hides the
dependency from npm and the bundler — this shipped a real
`ERR_MODULE_NOT_FOUND` production crash in MJ once. The only accepted reasons:
Angular lazy routes, optional peer deps (cloud SDKs), measured bundle-size
deferral, breaking a truly untangleable cycle, runtime plugin discovery. Even
then: still declare the package in `dependencies` and comment which category
applies.

## Use `BaseSingleton` for all singletons
Never the manual `static _instance` pattern — bundler code-splitting can load
a module twice and give you two "singletons" with divergent state.
`BaseSingleton<T>` (from `@memberjunction/global`) uses the global object
store, which survives duplication:

```typescript
export class MyEngine extends BaseSingleton<MyEngine> {
    protected constructor() { super(); }
    public static get Instance(): MyEngine { return MyEngine.getInstance<MyEngine>(); }
}
```

## Persist user preferences via `UserInfoEngine` — never `localStorage`
`localStorage` is per-browser; preferences die on a new machine.
`UserInfoEngine.Instance` (from `@memberjunction/core-entities`) writes to
`MJ: User Settings` — per-user, server-side, cached in memory (synchronous
reads). Key convention: `mj.<feature>.<prefName>`, JSON-serialized, with a
`v1` suffix when the shape may evolve. `localStorage` is acceptable only for
auth-provider tokens and truly throwaway state.

## Always run and update unit tests
Modifying a package means running that package's tests before you're done
(`cd packages/X && npm run test`). Tests broken by your change are yours to
update; tests broken for other reasons are yours to fix. Report pass/fail/skip
counts honestly.

## App-repo additions (this template's own rules)
- **Never edit `src/generated/`** — CodeGen overwrites it; commit regenerated
  code together with its migration.
- **Never edit an applied migration** — add a new `V*` file (checksum drift
  breaks every install). Additive-only within a published major version.
